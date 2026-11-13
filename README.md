# Projet Big Data — M1 MIAGE 2026-2027
Auteur : ADEL Melina

## Ordre de démarrage
1. `cd compose && copy .env.example .env` (PowerShell : `Copy-Item .env.example .env`), puis changer les mots de passe.
2. `docker compose build minio`
3. `docker compose up -d`
4. Installer Airbyte : `abctl local install`, puis `abctl local credentials`.
5. Configurer les connexions Airbyte (voir `airbyte/README_AIRBYTE.md`).
6. Exécuter `sql/silver/*.sql` puis `sql/tests/*.sql` dans PostgreSQL (Adminer, http://localhost:8082).

(À compléter au fur et à mesure : sources, réseau, incidents, rejeu des lots.)
