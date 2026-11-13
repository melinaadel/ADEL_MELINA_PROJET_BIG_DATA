# Tests attendus — couche Silver

Chaque table Silver doit être accompagnée de requêtes vérifiables pour au minimum :

1. clé métier/technique non nulle ;
2. unicité de la clé attendue ;
3. nombre de doublons = 0 après la règle documentée de déduplication ;
4. types PostgreSQL conformes au contrat cible ;
5. noms de colonnes homogènes en `snake_case` ;
6. comparaison des volumes Bronze/Silver et justification de tout écart ;
7. présence des colonnes de traçabilité retenues (`source_system`, `source_record_id`, `ingested_at_utc` ou équivalent) ;
8. contrôle de dates et valeurs obligatoires selon le jeu choisi.

Une capture d'écran seule n'est pas un test : fournissez aussi la requête et le résultat interprété.
