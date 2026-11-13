# Airbyte — principe de déploiement du projet

Airbyte Open Source n'est plus déployé officiellement avec Docker Compose. Le projet utilise donc :

- Docker Compose pour PostgreSQL, MariaDB, EspoCRM, MinIO et Adminer ;
- `abctl` pour déployer Airbyte localement dans Kubernetes-in-Docker.

Commandes de base :

```bash
abctl version
abctl local install
abctl local credentials
```

Airbyte est ensuite accessible sur `http://localhost:8000` par défaut.

Pour joindre les services Docker Compose depuis Airbyte :

- Windows/macOS : tester `host.docker.internal` avec les ports exposés (5432, 3306, 9000) ;
- Linux : si `host.docker.internal` ne résout pas, utiliser l'adresse de passerelle Docker accessible depuis le nœud kind et la documenter dans le README du projet.

Ne mettez jamais de mot de passe réel dans Git ou dans le PDF.

## Qualification obligatoire du flux MinIO → PostgreSQL

Le projet prévoit une lecture des objets MinIO avec **Airbyte Source S3**. La version actuelle du connecteur valide les endpoints personnalisés en HTTPS. Le MinIO de développement du Compose est volontairement simple et expose son API en HTTP ; cette combinaison n'est donc pas déclarée « validée » par ce kit.

Avant diffusion aux étudiants, figer une configuration testée : endpoint MinIO HTTPS de confiance, ou version de Source S3 compatible et qualifiée. Conserver dans le kit la version exacte du connecteur et la preuve d'un **Test connection** réussi puis d'une synchronisation vers PostgreSQL.
