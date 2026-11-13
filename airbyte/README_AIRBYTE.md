# Airbyte — configuration du projet

**ADEL Melina** · Projet Big Data · M1 MIAGE 2026-2027

Ce fichier décrit la configuration Airbyte telle qu'elle a été réellement utilisée, champ par
champ, pour pouvoir la refaire à l'identique. Aucun mot de passe n'y figure : les valeurs sont
dans `compose/.env`, qui n'est pas versionné.

---

## 1. Installation

Airbyte Open Source n'est plus déployé avec Docker Compose. Le projet utilise donc :

- **Docker Compose** pour PostgreSQL, MariaDB, EspoCRM, MinIO et Adminer ;
- **`abctl`** pour installer Airbyte dans un cluster Kubernetes-in-Docker (kind).

```bash
abctl version                 # v0.30.4
abctl local install           # installe Airbyte 2.5.0
abctl local credentials       # affiche l'identifiant et le mot de passe de l'interface
```

Interface sur <http://localhost:8000>.

### Réseau : comment joindre les services depuis Airbyte

Airbyte tourne dans le cluster kind, pas dans le Compose : depuis un pod, `localhost` ne désigne
pas les services du projet.

- **Linux / GitHub Codespace (configuration testée)** : adresse de la passerelle du réseau Docker
  du cluster kind, ici **`172.19.0.1`**, avec les ports publiés par le Compose. On la retrouve
  avec `docker network inspect kind`.
- **Windows / macOS** : essayer `host.docker.internal`.

| Service | Adresse utilisée dans Airbyte |
|---|---|
| PostgreSQL | `172.19.0.1:5432` |
| MariaDB | `172.19.0.1:3306` |
| MinIO | `http://172.19.0.1:9000` |

> **Important pour MinIO** : ne pas utiliser l'URL publique HTTPS d'un Codespace comme endpoint S3.
> La requête signée passe par le proxy de GitHub et MinIO rejette la signature
> (« The request signature we calculated does not match »). Voir l'incident 2 plus bas.

---

## 2. Sources

### 2.1 `frankfurter_api` — connecteur créé dans le Builder

| Champ | Valeur |
|---|---|
| Type | Connector Builder (connecteur personnalisé) |
| URL de base | `https://api.frankfurter.dev` |
| Chemin | `/v2/rates` |
| Méthode | GET |
| Paramètres | `from=2026-11-02`, `to=2026-11-10`, `base=EUR`, `quotes=USD,GBP,JPY`, `providers=ECB` |
| Clé primaire | `date`, `quote` (Composite Key) |
| Pagination | aucune |

`providers=ECB` est important : sans ce paramètre, la v2 renvoie des taux combinés entre plusieurs
fournisseurs. Avec lui, les valeurs sont celles de la BCE et sont reproductibles.

### 2.2 `file_csv_communes` — Source File

| Champ | Valeur |
|---|---|
| Dataset Name | `communes_france` |
| File Format | `csv` |
| URL | `https://www.data.gouv.fr/api/1/datasets/r/c63fd0b1-7987-46f6-b779-8b3ed889090c` |
| Storage Provider | HTTPS Public Web |
| Reader Options | `{"dtype": "string"}` |

**`dtype=string` est obligatoire.** Sans cette option, Airbyte devine les types et le code INSEE
`01001` est lu comme le nombre `1001` : les zéros initiaux sont perdus. Avec elle, tout arrive en
texte et le typage est fait en Silver.

### 2.3 `s3_minio_api_frankfurter` et `s3_minio_csv_communes` — Source S3 (v4.17.1)

| Champ | `s3_minio_api_frankfurter` | `s3_minio_csv_communes` |
|---|---|---|
| Bucket | `dsid-raw` | `dsid-raw` |
| Authentification | IAM User (clés MinIO, voir `.env`) | idem |
| Endpoint (Advanced) | `http://172.19.0.1:9000` | `http://172.19.0.1:9000` |
| Nom du stream | `api_frankfurter` | `csv_communes` |
| Globs | `raw/api/frankfurter/frankfurter_api/*.jsonl` | `raw/csv/communes/communes_france/*.jsonl` |
| Format | Jsonl Format | Jsonl Format |
| Delivery Method | Replicate Records | Replicate Records |

Deux pièges rencontrés :

- le champ **Globs** doit être validé avec la touche **Entrée**, sinon il reste vide ;
- le **nom du stream donne le nom de la table Bronze** : d'où `api_frankfurter` et `csv_communes`,
  qui respectent les formes `bronze.api_<source>` et `bronze.csv_<source>`.

### 2.4 `mariadb_espocrm` — Source MySQL

| Champ | Valeur |
|---|---|
| Host | `172.19.0.1` |
| Port | `3306` |
| Database | `espocrm` |
| Username | `airbyte` (lecture seule, créé par `compose/init/mariadb/01_airbyte_user.sh`) |
| Password | voir `AIRBYTE_MARIADB_PASSWORD` dans `compose/.env` |
| SSL / Encryption | `preferred` |
| SSH Tunnel | No Tunnel |
| Update Method | **Scan Changes with User Defined Cursor** |

Le compte `airbyte` n'a que le droit `SELECT` sur la base `espocrm`.

---

## 3. Destinations

### 3.1 `minio_raw` et `minio_raw_csv` — Destination S3

| Champ | `minio_raw` (API) | `minio_raw_csv` (CSV) |
|---|---|---|
| Bucket Name | `dsid-raw` | `dsid-raw` |
| Bucket Path | `raw/api/frankfurter` | `raw/csv/communes` |
| Endpoint | `http://172.19.0.1:9000` | `http://172.19.0.1:9000` |
| Région | `us-east-1` | `us-east-1` |
| Format | JSON Lines (JSONL) | JSON Lines (JSONL) |

Airbyte nomme les fichiers
`<bucket path>/<stream>/<AAAA_MM_JJ>_<horodatage en ms>_<numéro>.jsonl` : la date du lot est donc
dans le nom du fichier.

### 3.2 `postgres_bronze` — Destination Postgres

| Champ | Valeur |
|---|---|
| Host | `172.19.0.1` |
| Port | `5432` |
| Database Name | `warehouse` |
| Username | `warehouse` (ne pas laisser le navigateur remplir ce champ automatiquement) |
| Password | voir `POSTGRES_PASSWORD` dans `compose/.env` |
| Default Schema | **`bronze`** |
| SSL Modes | `disable` |
| SSH Tunnel Method | **No Tunnel** |

---

## 4. Connexions

Les 5 connexions sont en déclenchement **Manual** et en Destination Namespace
**Destination-defined**.

| Connexion | Source → destination | Stream | Mode de synchronisation |
|---|---|---|---|
| `api_frankfurter_to_minio` | `frankfurter_api` → `minio_raw` | `frankfurter_api` | Full refresh \| Append |
| `s3_minio_to_postgres_api` | `s3_minio_api_frankfurter` → `postgres_bronze` | `api_frankfurter` | Incremental \| Append, curseur `_ab_source_file_last_modified` |
| `csv_communes_to_minio` | `file_csv_communes` → `minio_raw_csv` | `communes_france` | Full refresh \| Append |
| `s3_minio_to_postgres_csv` | `s3_minio_csv_communes` → `postgres_bronze` | `csv_communes` | Incremental \| Append, même curseur |
| `mariadb_espocrm_to_postgres_crm` | `mariadb_espocrm` → `postgres_bronze` | 5 tables, voir ci-dessous | voir ci-dessous |

### 4.1 Champs à décocher dans les connexions MinIO → PostgreSQL

Dans l'onglet **Schema** des connexions `s3_minio_to_postgres_api` et `s3_minio_to_postgres_csv`,
**décocher les 4 champs** `_airbyte_raw_id`, `_airbyte_extracted_at`, `_airbyte_generation_id` et
`_airbyte_meta`. Garder les 3 autres : `_airbyte_data`, `_ab_source_file_url` et
`_ab_source_file_last_modified`.

Sans cela, la synchronisation échoue avec
`column "_airbyte_raw_id" specified more than once` : les fichiers JSONL contiennent déjà ces
champs techniques et la destination Postgres ajoute les siens, avec les mêmes noms.

### 4.2 Connexion du CRM

Ne cocher que les 5 tables utiles sur les 141 découvertes.

| Stream | Mode | Curseur | Clé |
|---|---|---|---|
| `account` | Incremental \| Append | `modified_at` | `id` |
| `contact` | Incremental \| Append | `modified_at` | `id` |
| `opportunity` | Incremental \| Append + Deduped | `modified_at` | `id` |
| `account_contact` | Full refresh \| Overwrite + Deduped | — | `id` |
| `contact_opportunity` | Full refresh \| Overwrite | — | — |

Les deux tables de relation n'ont pas de colonne de date utilisable comme curseur, d'où le Full
refresh. Pour une prochaine version, il faudrait harmoniser les trois entités sur le même mode
(Append ou Append + Deduped) ; cela ne change pas le résultat, les vues Silver dédoublonnant par
clé.

---

## 5. Incidents rencontrés et corrections

### Incident 1 — Publication du connecteur du Builder : `errors.http.internalServerError`

Les logs du serveur Airbyte mentionnaient « major version 7 ». Le manifeste du Builder est en
version majeure 7, mais la table `declarative_manifest_image_version` de la base interne d'Airbyte
ne contenait que les versions 0 à 4 (problème signalé sur le GitHub d'Airbyte, issue n° 84928).

Correction : ajouter la ligne manquante.

```bash
kubectl --kubeconfig ~/.airbyte/abctl/abctl.kubeconfig -n airbyte-abctl exec airbyte-db-0 -- \
  psql -U airbyte -d db-airbyte -c "insert into declarative_manifest_image_version \
  (major_version, image_version, image_sha, created_at, updated_at) values \
  (7, '7.47.0', 'sha256:b2ecb78040d4c4b42fa3537488d68a3b195f64b5fefcbc48ac0591479591a3f0', \
  now(), now()) on conflict (major_version) do nothing;"
```

Résultat attendu : `INSERT 0 1`. La publication fonctionne ensuite.

### Incident 2 — Source et destination S3 : « The request signature we calculated does not match »

Cause : l'URL publique HTTPS du port 9000 du Codespace avait été mise comme endpoint. La requête
signée passe alors par le proxy de GitHub et la signature n'est plus reconnue.

Correction : endpoint interne `http://172.19.0.1:9000`. Le connecteur Source S3 4.17.1 l'accepte
en HTTP. Le port 9000 a été remis en privé après vérification.

### Incident 3 — `column "_airbyte_raw_id" specified more than once`

Voir le point 4.1 : décocher les 4 champs techniques dans l'onglet Schema.

### Incident 4 — Job du CRM bloqué en `Pending` (`Insufficient cpu`)

Diagnostic :

```bash
kubectl --kubeconfig ~/.airbyte/abctl/abctl.kubeconfig -n airbyte-abctl get pods | grep replication
kubectl --kubeconfig ~/.airbyte/abctl/abctl.kubeconfig -n airbyte-abctl \
  describe pod <pod> | tail -15
```

Message : `0/1 nodes are available: 1 Insufficient cpu`. Le pod réservait 4 CPU (2 pour
l'orchestrateur, 1 pour la source, 1 pour la destination) sur une machine de 4 cœurs dont Airbyte
occupe déjà 1,1.

Correction : réduire les ressources demandées par cette connexion.

```bash
kubectl --kubeconfig ~/.airbyte/abctl/abctl.kubeconfig -n airbyte-abctl exec airbyte-db-0 -- \
  psql -U airbyte -d db-airbyte -c "update connection set resource_requirements = \
  '{\"cpu_request\":\"500m\",\"cpu_limit\":\"1\",\"memory_request\":\"512Mi\",\"memory_limit\":\"1Gi\"}' \
  where name = 'mariadb_espocrm_to_postgres_crm';"
```

Résultat attendu : `UPDATE 1`. Supprimer ensuite le pod bloqué et relancer **Sync now** : le job
démarre immédiatement (72 secondes pour les 5 tables).

### Incident 5 — Préfixe `crm_` non enregistré

Le Stream Prefix `crm_` n'a pas été pris en compte à la création de la connexion du CRM. Les
tables Bronze gardent donc les noms d'origine de MariaDB (`account`, `contact`…), ce qui reste
conforme à l'énoncé pour ce flux, et le préfixe `crm_` est appliqué en Silver
(`silver.crm_account`…).

---

## 6. Commandes de vérification utiles

```bash
# État des pods Airbyte
kubectl --kubeconfig ~/.airbyte/abctl/abctl.kubeconfig -n airbyte-abctl get pods

# Logs du dernier job de réplication
P=$(kubectl --kubeconfig ~/.airbyte/abctl/abctl.kubeconfig -n airbyte-abctl get pods \
    --sort-by=.metadata.creationTimestamp --no-headers \
    -o custom-columns=NAME:.metadata.name | grep replication-job | tail -n 1)
kubectl --kubeconfig ~/.airbyte/abctl/abctl.kubeconfig -n airbyte-abctl logs "$P" \
  --all-containers | grep -iE "error|exception|failed" | tail -20

# Relire la configuration des connexions (modes de synchronisation réellement enregistrés)
kubectl --kubeconfig ~/.airbyte/abctl/abctl.kubeconfig -n airbyte-abctl exec airbyte-db-0 -- \
  psql -U airbyte -d db-airbyte -P pager=off -At -c \
  "select c.name, s->'stream'->>'name', s->>'sync_mode', s->>'destination_sync_mode', s->>'cursor_field' \
   from connection c, jsonb_array_elements(c.catalog->'streams') s order by 1"
```

**Ne jamais mettre de mot de passe réel dans Git ni dans le PDF.**
