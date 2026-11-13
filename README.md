# Projet Big Data — M1 MIAGE 2026-2027

**Auteur : ADEL Melina** · UE DSID · Université Paris-Saclay · Rendu du 13 novembre 2026

Chaîne d'ingestion et de standardisation de trois sources (API publique, fichier CSV, CRM EspoCRM)
vers PostgreSQL, en couches **Bronze** (données reçues telles quelles) et **Silver** (vues SQL
standardisées et testées).

Le rapport complet est dans `rapport/rapport_projet_big_data.pdf`.

---

## 1. Ce que fait le projet

| Flux | Source | Chemin | Table(s) Bronze | Vue(s) Silver | Lignes |
|---|---|---|---|---|---|
| A | API Frankfurter (taux BCE) | GET → Airbyte → MinIO → Airbyte S3 → PostgreSQL | `bronze.api_frankfurter` | `silver.api_frankfurter_rates` | 21 |
| B | CSV des communes de France (data.gouv.fr) | HTTPS → Airbyte → MinIO → Airbyte S3 → PostgreSQL | `bronze.csv_communes` | `silver.csv_communes` | 34 868 |
| C | EspoCRM / MariaDB | MariaDB → Airbyte MySQL → PostgreSQL | `bronze.account`, `contact`, `opportunity`, `account_contact`, `contact_opportunity` | `silver.crm_account`, `crm_contact`, `crm_opportunity`, `crm_account_contact`, `crm_contact_opportunity` | 1, 2, 1, 2, 2 |

Les 7 vues Silver passent les 8 tests obligatoires (clé non nulle, unicité, doublons, nommage,
types, réconciliation Bronze/Silver, traçabilité, règle métier).

## 2. Contenu du dossier

```
ADEL_MELINA_PROJET_BIG_DATA/
├─ README.md                        ce fichier
├─ rapport/
│  └─ rapport_projet_big_data.pdf   le rapport (8 sections)
├─ compose/
│  ├─ compose.yaml                  PostgreSQL, MariaDB, EspoCRM, MinIO, Adminer
│  ├─ Dockerfile.minio              construction locale de l'image MinIO
│  ├─ .env.example                  modèle de configuration, SANS mot de passe
│  ├─ README_DOCKER.md
│  └─ init/                         création des schémas et du compte Airbyte en lecture seule
├─ airbyte/
│  └─ README_AIRBYTE.md             configuration détaillée des 5 connexions + incidents
├─ sql/
│  ├─ silver/                       api_frankfurter_rates.sql, csv_communes.sql, crm_espocrm.sql
│  └─ tests/                        les 8 tests par source + bronze_controles.sql
├─ data/
│  ├─ api_frankfurter_sample.json   échantillon de la réponse de l'API
│  ├─ communes_france.csv           fichier CSV original (Licence Ouverte 2.0)
│  └─ manifestes/                   manifeste MinIO et SHA-256 des lots
├─ scripts/
│  └─ minio_manifest.py             dépôt du fichier original + manifeste SHA-256
└─ preuves/                         sorties des tests et contrôles
```

**Aucun secret n'est versionné.** Le fichier `compose/.env` est ignoré par Git ; seul
`compose/.env.example` est fourni.

## 3. Prérequis

- Docker et Docker Compose
- `abctl` pour installer Airbyte ([documentation](https://docs.airbyte.com/deploying-airbyte/))
- Python 3 avec `boto3` (seulement pour le script de manifeste)

Versions utilisées : PostgreSQL 18.6, MariaDB 11.8.9, EspoCRM 10.0.8, MinIO
RELEASE.2025-10-15T17-29-55Z, Adminer 6.1.0, Airbyte 2.5.0 (abctl v0.30.4), connecteur Source S3 4.17.1.

Le projet a été exécuté sur un GitHub Codespace Linux (4 cœurs, 16 Go). Prévoir au moins 16 Go de
mémoire : avec 8 Go, Docker Desktop et Airbyte ne tiennent pas ensemble.

## 4. Démarrage, dans l'ordre

### 4.1 Configuration

```bash
cd compose
cp .env.example .env          # Windows PowerShell : Copy-Item .env.example .env
```

Ouvrir `.env` et remplacer chaque mot de passe par le sien.

### 4.2 Services

```bash
docker compose build minio
docker compose up -d
docker compose ps             # attendre « healthy »
```

Au premier démarrage, les scripts de `compose/init/` créent les schémas `bronze` et `silver` dans
PostgreSQL et le compte MariaDB `airbyte` en lecture seule sur la base `espocrm`.

Accès : EspoCRM http://localhost:8081 · Adminer http://localhost:8082 ·
MinIO API http://localhost:9000, console http://localhost:9001

### 4.3 MinIO

Dans la console MinIO, créer le bucket **privé** `dsid-raw`.

### 4.4 Airbyte

```bash
abctl local install
abctl local credentials       # identifiants de connexion
```

Interface sur http://localhost:8000. Créer ensuite les sources, destinations et connexions
décrites dans `airbyte/README_AIRBYTE.md` (valeurs exactes de chaque champ, réglages à ne pas
oublier, et les deux corrections à appliquer dans la base interne d'Airbyte).

**Adresse des services vue depuis Airbyte.** Airbyte tourne dans un cluster kind, pas dans le
Compose : `localhost` n'y désigne pas les services. Sous Linux, utiliser l'adresse de la passerelle
du réseau Docker du cluster (`172.19.0.1` ici, à vérifier avec `docker network inspect kind`) ;
sous Windows et macOS, essayer `host.docker.internal`.

### 4.5 Synchronisations

Dans cet ordre :

1. `api_frankfurter_to_minio`
2. `s3_minio_to_postgres_api`
3. `csv_communes_to_minio`
4. `s3_minio_to_postgres_csv`
5. Saisir les données dans EspoCRM (1 compte, 2 contacts, 1 opportunité liée au compte et aux
   deux contacts), puis lancer `mariadb_espocrm_to_postgres_crm`.

### 4.6 Silver

```bash
cd ..
for f in api_frankfurter_rates csv_communes crm_espocrm; do
  docker exec -i dsid-postgres psql -U warehouse -d warehouse -v ON_ERROR_STOP=1 < sql/silver/$f.sql
done
```

### 4.7 Contrôles et tests

```bash
docker exec -i dsid-postgres psql -U warehouse -d warehouse -P pager=off -a \
  < sql/tests/bronze_controles.sql            > preuves/controles_bronze.txt 2>&1
docker exec -i dsid-postgres psql -U warehouse -d warehouse -P pager=off -a \
  < sql/tests/api_frankfurter_rates_tests.sql > preuves/tests_silver_api_frankfurter.txt 2>&1
docker exec -i dsid-postgres psql -U warehouse -d warehouse -P pager=off -a \
  < sql/tests/csv_communes_tests.sql          > preuves/tests_silver_csv_communes.txt 2>&1
docker exec -i dsid-postgres psql -U warehouse -d warehouse -P pager=off -a \
  < sql/tests/crm_espocrm_tests.sql           > preuves/tests_silver_crm_espocrm.txt 2>&1
```

Comparer avec les fichiers déjà présents dans `preuves/` : toutes les anomalies doivent valoir 0.

### 4.8 Manifeste MinIO

```bash
pip install boto3
python3 scripts/minio_manifest.py --upload-original data/communes_france.csv
```

Le script dépose le CSV original (sans le modifier) dans `raw/originaux/csv_communes/`, vérifie son
SHA-256, puis écrit `data/manifestes/minio_raw_manifest.csv` et `.json`. Il lit les identifiants
dans `compose/.env` et n'affiche aucun mot de passe.

## 5. Rejeu d'un lot

| Étape | Mode | Effet d'une relance |
|---|---|---|
| Source → MinIO | Full refresh \| Append | Ajoute un nouveau fichier daté. Le lot précédent reste en place. |
| MinIO → Bronze | Incremental \| Append (curseur `_ab_source_file_last_modified`) | Charge uniquement les fichiers nouveaux. Sans nouveau fichier : 0 ligne chargée. |
| CRM → Bronze | Incrémental sur `modified_at` pour les entités, Full refresh pour les relations | Ajoute les versions nouvelles ou modifiées ; relit les tables de liens en entier. |
| Silver | Vues | Recalculées à chaque lecture. Le dédoublonnage garde la ligne la plus récente par clé. |

Un rechargement ne rend jamais le lot d'origine introuvable : les fichiers restent dans MinIO avec
leur date et leur SHA-256. **Aucun UPDATE manuel n'est fait dans Bronze** ; les corrections sont
dans Silver.

## 6. Reprise

- **Après un arrêt de la machine** : `cd compose && docker compose up -d`, puis vérifier les pods
  Airbyte avec
  `kubectl --kubeconfig ~/.airbyte/abctl/abctl.kubeconfig -n airbyte-abctl get pods`.
  Les données sont conservées dans les volumes Docker.
- **Après une modification du SQL** : rejouer le script (`CREATE OR REPLACE VIEW`) puis les tests.
- **Repartir de zéro** : `docker compose down -v` supprime les volumes, donc aussi les données
  saisies dans EspoCRM. Reprendre ensuite à l'étape 4.2.

## 7. Sources et licences

- **API Frankfurter** : <https://frankfurter.dev/> — service gratuit et sans authentification ;
  taux issus de la Banque centrale européenne. La documentation ne précise pas de licence pour les
  données.
- **CSV des communes de France** : [fiche du jeu sur data.gouv.fr](https://www.data.gouv.fr/datasets/liste-des-communes-de-france-code-insee-codes-postaux-epci-population-superficie-62-indicateurs?resource_id=c63fd0b1-7987-46f6-b779-8b3ed889090c)
  — Licence Ouverte / Open Licence 2.0.
- **EspoCRM** : données fictives créées pour le test, aucune donnée personnelle réelle.
