# Projet Big Data — démarrage de la stack

## 1. Architecture technique

Le `compose.yaml` démarre :

- PostgreSQL 18.6 — base `warehouse`, schémas `bronze` et `silver` ;
- MariaDB 11.8.9 — base opérationnelle d'EspoCRM ;
- EspoCRM 10.0.8 + daemon ;
- MinIO — construit localement depuis la release communautaire `RELEASE.2025-10-15T17-29-55Z` ;
- Adminer 6.1.0.

Airbyte est installé séparément avec `abctl`, car le déploiement Docker Compose d'Airbyte n'est plus supporté officiellement.

## 2. Prérequis communs

- Git ;
- Docker Desktop (Windows/macOS) ou Docker Engine/Desktop (Linux) ;
- Docker Compose v2 (`docker compose version`) ;
- 4 CPU et 8 Go de RAM au minimum pour Airbyte ; 16 Go recommandés lorsque toute la stack tourne en même temps ;
- accès Internet lors du premier téléchargement/build des images.

## 3. Démarrage — Windows PowerShell

```powershell
Copy-Item .env.example .env
notepad .env

docker version
docker compose version
docker compose build minio
docker compose up -d
docker compose ps
```

Installez `abctl` depuis la dernière release Windows officielle, ajoutez son dossier au `Path`, puis :

```powershell
abctl version
abctl local install
abctl local credentials
```

## 4. Démarrage — macOS

```bash
cp .env.example .env
nano .env

docker version
docker compose version
docker compose build minio
docker compose up -d
docker compose ps

curl -LsfS https://get.airbyte.com | bash -
abctl version
abctl local install
abctl local credentials
```

Homebrew est également possible :

```bash
brew tap airbytehq/tap
brew install abctl
```

## 5. Démarrage — Linux

```bash
cp .env.example .env
nano .env

docker version
docker compose version
docker compose build minio
docker compose up -d
docker compose ps

curl -LsfS https://get.airbyte.com | bash -
abctl version
abctl local install
abctl local credentials
```

Sur une machine Linux sans interface graphique, Docker Engine peut remplacer Docker Desktop.

## 6. URLs locales

- Airbyte : http://localhost:8000
- EspoCRM : http://localhost:8081
- Adminer : http://localhost:8082
- MinIO API : http://localhost:9000
- MinIO Console : http://localhost:9001
- PostgreSQL : localhost:5432
- MariaDB : localhost:3306

## 7. Adresse à utiliser depuis Airbyte

Airbyte tourne dans un cluster kind séparé du réseau Compose. `localhost` dans un connecteur Airbyte ne désigne donc pas nécessairement votre machine hôte.

- Windows/macOS : utilisez d'abord `host.docker.internal`.
- Linux : testez `host.docker.internal`. S'il n'est pas résolu, récupérez la passerelle Docker du nœud kind :

```bash
NODE=$(docker ps --filter name=airbyte-abctl-control-plane --format '{{.Names}}' | head -n 1)
docker inspect "$NODE" --format '{{range .NetworkSettings.Networks}}{{.Gateway}}{{end}}'
```

Utilisez l'IP obtenue comme hôte dans les connecteurs Airbyte et notez-la dans votre README. Le test de connexion Airbyte doit réussir avant de continuer.

## 8. Première vérification

Dans PostgreSQL :

```sql
SELECT schema_name
FROM information_schema.schemata
WHERE schema_name IN ('bronze','silver')
ORDER BY schema_name;
```

Dans MariaDB, le compte Airbyte doit être en lecture seule sur `espocrm`.

Dans MinIO, créez le bucket privé `dsid-raw` puis utilisez des préfixes explicites, par exemple :

```text
raw/api/<nom_source>/...
raw/csv/<nom_source>/...
```

## 9. Arrêt

```bash
docker compose stop
```

Ne faites pas `docker compose down -v` sauf si vous voulez volontairement supprimer toutes les données locales.

Airbyte :

```bash
abctl local uninstall
```

Sans `--persisted`, l'installation Airbyte est retirée mais ses données persistées sont conservées selon le comportement d'`abctl`.

## 10. Règles de rendu

- Rendez `.env.example`, jamais `.env`.
- Figez les versions utilisées et copiez les sorties de `docker compose images` et `abctl version` dans le PDF.
- Le projet doit pouvoir être repris sur Windows, macOS ou Linux à partir du README ; les éventuelles différences d'hôte réseau doivent être documentées.

## 11. Point technique à qualifier avant diffusion du sujet

Le flux **MinIO → Airbyte Source S3 → PostgreSQL** doit être testé avec la version exacte du connecteur retenue pour le cours.

La branche actuelle du connecteur **Airbyte Source S3** applique une validation HTTPS aux endpoints S3 compatibles personnalisés. Un MinIO local exposé uniquement en `http://...:9000` peut donc être refusé par le connecteur, même si le service MinIO fonctionne correctement.

Avant de remettre le kit aux étudiants, l'enseignant doit retenir et tester l'une des deux configurations suivantes :

1. un endpoint MinIO HTTPS dont le certificat est accepté par les workloads Airbyte ; ou
2. une version du connecteur S3 Source explicitement figée et testée avec le MinIO local du kit.

Ne considérez pas le simple démarrage des conteneurs comme une validation de ce flux. Le bouton **Test connection** de la Source S3 puis une synchronisation complète MinIO → PostgreSQL doivent réussir sur Windows, macOS et Linux retenus pour le cours.
