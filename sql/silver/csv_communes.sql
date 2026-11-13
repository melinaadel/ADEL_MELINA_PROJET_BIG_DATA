-- silver.csv_communes : liste des communes de France (CSV data.gouv.fr, Licence Ouverte 2.0)
-- Grain : une commune par ligne. Cle : code_insee (texte, 5 caracteres, zero initial conserve).
--
-- STRUCTURE BRONZE ATTENDUE (a controler avec \d bronze.csv_communes avant execution) :
--   _airbyte_raw_id, _airbyte_extracted_at, _airbyte_meta (jsonb), _airbyte_generation_id,
--   _airbyte_data (jsonb : les 62 colonnes du CSV), _ab_source_file_url, _ab_source_file_last_modified.
--   Le CSV est lu par Airbyte avec l'option {"dtype":"string"} : toutes les valeurs arrivent en texte,
--   donc les zeros initiaux des codes (ex. 01001) sont conserves. Le typage se fait ici, en Silver.
--
-- REGLES DE TRANSFORMATION (a reprendre dans le rapport) :
--   1. Texte : TRIM, puis chaine vide -> NULL (une chaine vide n'a pas de sens metier ici).
--   2. Identifiants (code_insee, dep_code, reg_code, code_postal, ...) : conserves en TEXT.
--   3. Nombres : conversion seulement si la valeur a le bon format ; sinon NULL.
--      Le nombre de valeurs non converties est mesure par le test 8b (doit rester 0).
--   4. Decimaux : numeric(18,2) pour surfaces/densites/altitudes (arrondi a 2 decimales) ;
--      numeric(9,6) pour latitudes/longitudes.
--   5. Deduplication : une ligne par code_insee, la plus recente selon _airbyte_extracted_at
--      (egalite : _airbyte_raw_id). Les lignes ecartees sont comptees par le test 6.
--   6. Lignes sans code_insee : exclues de Silver, comptees par le test 6.

CREATE OR REPLACE VIEW silver.csv_communes AS
WITH ranked AS (
    SELECT
        b._airbyte_data,
        b._airbyte_raw_id,
        b._airbyte_extracted_at,
        ROW_NUMBER() OVER (
            PARTITION BY NULLIF(TRIM(b._airbyte_data ->> 'code_insee'), '')
            ORDER BY b._airbyte_extracted_at DESC, b._airbyte_raw_id DESC
        ) AS rn
    FROM bronze.csv_communes AS b
    WHERE NULLIF(TRIM(b._airbyte_data ->> 'code_insee'), '') IS NOT NULL
)
SELECT
    NULLIF(TRIM(r._airbyte_data ->> 'code_insee'), '') AS code_insee,
    NULLIF(TRIM(r._airbyte_data ->> 'nom_standard'), '') AS nom_standard,
    NULLIF(TRIM(r._airbyte_data ->> 'nom_sans_pronom'), '') AS nom_sans_pronom,
    NULLIF(TRIM(r._airbyte_data ->> 'nom_a'), '') AS nom_a,
    NULLIF(TRIM(r._airbyte_data ->> 'nom_de'), '') AS nom_de,
    NULLIF(TRIM(r._airbyte_data ->> 'nom_sans_accent'), '') AS nom_sans_accent,
    NULLIF(TRIM(r._airbyte_data ->> 'nom_standard_majuscule'), '') AS nom_standard_majuscule,
    NULLIF(TRIM(r._airbyte_data ->> 'typecom'), '') AS typecom,
    NULLIF(TRIM(r._airbyte_data ->> 'typecom_texte'), '') AS typecom_texte,
    NULLIF(TRIM(r._airbyte_data ->> 'reg_code'), '') AS reg_code,
    NULLIF(TRIM(r._airbyte_data ->> 'reg_nom'), '') AS reg_nom,
    NULLIF(TRIM(r._airbyte_data ->> 'dep_code'), '') AS dep_code,
    NULLIF(TRIM(r._airbyte_data ->> 'dep_nom'), '') AS dep_nom,
    NULLIF(TRIM(r._airbyte_data ->> 'canton_code'), '') AS canton_code,
    NULLIF(TRIM(r._airbyte_data ->> 'canton_nom'), '') AS canton_nom,
    NULLIF(TRIM(r._airbyte_data ->> 'epci_code'), '') AS epci_code,
    NULLIF(TRIM(r._airbyte_data ->> 'epci_nom'), '') AS epci_nom,
    NULLIF(TRIM(r._airbyte_data ->> 'code_postal'), '') AS code_postal,
    NULLIF(TRIM(r._airbyte_data ->> 'codes_postaux'), '') AS codes_postaux,
    NULLIF(TRIM(r._airbyte_data ->> 'academie_code'), '') AS academie_code,
    NULLIF(TRIM(r._airbyte_data ->> 'academie_nom'), '') AS academie_nom,
    NULLIF(TRIM(r._airbyte_data ->> 'zone_emploi'), '') AS zone_emploi,
    NULLIF(TRIM(r._airbyte_data ->> 'zone_emploi_nom'), '') AS zone_emploi_nom,
    NULLIF(TRIM(r._airbyte_data ->> 'code_insee_centre_zone_emploi'), '') AS code_insee_centre_zone_emploi,
    NULLIF(TRIM(r._airbyte_data ->> 'code_unite_urbaine'), '') AS code_unite_urbaine,
    NULLIF(TRIM(r._airbyte_data ->> 'nom_unite_urbaine'), '') AS nom_unite_urbaine,
    CASE WHEN NULLIF(TRIM(r._airbyte_data ->> 'taille_unite_urbaine'), '') ~ '^-?[0-9]+$' THEN NULLIF(TRIM(r._airbyte_data ->> 'taille_unite_urbaine'), '')::integer END AS taille_unite_urbaine,
    NULLIF(TRIM(r._airbyte_data ->> 'type_commune_unite_urbaine'), '') AS type_commune_unite_urbaine,
    NULLIF(TRIM(r._airbyte_data ->> 'statut_commune_unite_urbaine'), '') AS statut_commune_unite_urbaine,
    NULLIF(TRIM(r._airbyte_data ->> 'code_aire_attraction'), '') AS code_aire_attraction,
    NULLIF(TRIM(r._airbyte_data ->> 'nom_aire_attraction'), '') AS nom_aire_attraction,
    CASE WHEN NULLIF(TRIM(r._airbyte_data ->> 'categorie_aire_attraction'), '') ~ '^-?[0-9]+$' THEN NULLIF(TRIM(r._airbyte_data ->> 'categorie_aire_attraction'), '')::integer END AS categorie_aire_attraction,
    CASE WHEN NULLIF(TRIM(r._airbyte_data ->> 'taille_aire_attraction'), '') ~ '^-?[0-9]+$' THEN NULLIF(TRIM(r._airbyte_data ->> 'taille_aire_attraction'), '')::integer END AS taille_aire_attraction,
    NULLIF(TRIM(r._airbyte_data ->> 'code_insee_centre_aire_attraction'), '') AS code_insee_centre_aire_attraction,
    NULLIF(TRIM(r._airbyte_data ->> 'code_bassin_de_vie'), '') AS code_bassin_de_vie,
    NULLIF(TRIM(r._airbyte_data ->> 'nom_bassin_de_vie'), '') AS nom_bassin_de_vie,
    CASE WHEN NULLIF(TRIM(r._airbyte_data ->> 'type_bassin_de_vie'), '') ~ '^-?[0-9]+$' THEN NULLIF(TRIM(r._airbyte_data ->> 'type_bassin_de_vie'), '')::integer END AS type_bassin_de_vie,
    CASE WHEN NULLIF(TRIM(r._airbyte_data ->> 'population'), '') ~ '^-?[0-9]+$' THEN NULLIF(TRIM(r._airbyte_data ->> 'population'), '')::integer END AS population,
    CASE WHEN NULLIF(TRIM(r._airbyte_data ->> 'superficie_hectare'), '') ~ '^-?[0-9]+(\.[0-9]+)?$' THEN (NULLIF(TRIM(r._airbyte_data ->> 'superficie_hectare'), ''))::numeric(18,2) END AS superficie_hectare,
    CASE WHEN NULLIF(TRIM(r._airbyte_data ->> 'superficie_km2'), '') ~ '^-?[0-9]+(\.[0-9]+)?$' THEN (NULLIF(TRIM(r._airbyte_data ->> 'superficie_km2'), ''))::numeric(18,2) END AS superficie_km2,
    CASE WHEN NULLIF(TRIM(r._airbyte_data ->> 'densite'), '') ~ '^-?[0-9]+(\.[0-9]+)?$' THEN (NULLIF(TRIM(r._airbyte_data ->> 'densite'), ''))::numeric(18,2) END AS densite,
    CASE WHEN NULLIF(TRIM(r._airbyte_data ->> 'superficie_cartographique_ign_hectare'), '') ~ '^-?[0-9]+(\.[0-9]+)?$' THEN (NULLIF(TRIM(r._airbyte_data ->> 'superficie_cartographique_ign_hectare'), ''))::numeric(18,2) END AS superficie_cartographique_ign_hectare,
    CASE WHEN NULLIF(TRIM(r._airbyte_data ->> 'superficie_cartographique_ign_km2'), '') ~ '^-?[0-9]+(\.[0-9]+)?$' THEN (NULLIF(TRIM(r._airbyte_data ->> 'superficie_cartographique_ign_km2'), ''))::numeric(18,2) END AS superficie_cartographique_ign_km2,
    CASE WHEN NULLIF(TRIM(r._airbyte_data ->> 'densite_cartographique'), '') ~ '^-?[0-9]+(\.[0-9]+)?$' THEN (NULLIF(TRIM(r._airbyte_data ->> 'densite_cartographique'), ''))::numeric(18,2) END AS densite_cartographique,
    CASE WHEN NULLIF(TRIM(r._airbyte_data ->> 'superficie_cadastrale_ign_hectare'), '') ~ '^-?[0-9]+(\.[0-9]+)?$' THEN (NULLIF(TRIM(r._airbyte_data ->> 'superficie_cadastrale_ign_hectare'), ''))::numeric(18,2) END AS superficie_cadastrale_ign_hectare,
    CASE WHEN NULLIF(TRIM(r._airbyte_data ->> 'superficie_cadastrale_ign_km2'), '') ~ '^-?[0-9]+(\.[0-9]+)?$' THEN (NULLIF(TRIM(r._airbyte_data ->> 'superficie_cadastrale_ign_km2'), ''))::numeric(18,2) END AS superficie_cadastrale_ign_km2,
    CASE WHEN NULLIF(TRIM(r._airbyte_data ->> 'densite_cadastrale'), '') ~ '^-?[0-9]+(\.[0-9]+)?$' THEN (NULLIF(TRIM(r._airbyte_data ->> 'densite_cadastrale'), ''))::numeric(18,2) END AS densite_cadastrale,
    CASE WHEN NULLIF(TRIM(r._airbyte_data ->> 'altitude_moyenne'), '') ~ '^-?[0-9]+(\.[0-9]+)?$' THEN (NULLIF(TRIM(r._airbyte_data ->> 'altitude_moyenne'), ''))::numeric(18,2) END AS altitude_moyenne,
    CASE WHEN NULLIF(TRIM(r._airbyte_data ->> 'altitude_minimale'), '') ~ '^-?[0-9]+(\.[0-9]+)?$' THEN (NULLIF(TRIM(r._airbyte_data ->> 'altitude_minimale'), ''))::numeric(18,2) END AS altitude_minimale,
    CASE WHEN NULLIF(TRIM(r._airbyte_data ->> 'altitude_maximale'), '') ~ '^-?[0-9]+(\.[0-9]+)?$' THEN (NULLIF(TRIM(r._airbyte_data ->> 'altitude_maximale'), ''))::numeric(18,2) END AS altitude_maximale,
    CASE WHEN NULLIF(TRIM(r._airbyte_data ->> 'latitude_mairie'), '') ~ '^-?[0-9]+(\.[0-9]+)?$' THEN (NULLIF(TRIM(r._airbyte_data ->> 'latitude_mairie'), ''))::numeric(9,6) END AS latitude_mairie,
    CASE WHEN NULLIF(TRIM(r._airbyte_data ->> 'longitude_mairie'), '') ~ '^-?[0-9]+(\.[0-9]+)?$' THEN (NULLIF(TRIM(r._airbyte_data ->> 'longitude_mairie'), ''))::numeric(9,6) END AS longitude_mairie,
    CASE WHEN NULLIF(TRIM(r._airbyte_data ->> 'latitude_centre'), '') ~ '^-?[0-9]+(\.[0-9]+)?$' THEN (NULLIF(TRIM(r._airbyte_data ->> 'latitude_centre'), ''))::numeric(9,6) END AS latitude_centre,
    CASE WHEN NULLIF(TRIM(r._airbyte_data ->> 'longitude_centre'), '') ~ '^-?[0-9]+(\.[0-9]+)?$' THEN (NULLIF(TRIM(r._airbyte_data ->> 'longitude_centre'), ''))::numeric(9,6) END AS longitude_centre,
    CASE WHEN NULLIF(TRIM(r._airbyte_data ->> 'grille_densite'), '') ~ '^-?[0-9]+$' THEN NULLIF(TRIM(r._airbyte_data ->> 'grille_densite'), '')::integer END AS grille_densite,
    NULLIF(TRIM(r._airbyte_data ->> 'grille_densite_texte'), '') AS grille_densite_texte,
    CASE WHEN NULLIF(TRIM(r._airbyte_data ->> 'niveau_equipements_services'), '') ~ '^-?[0-9]+$' THEN NULLIF(TRIM(r._airbyte_data ->> 'niveau_equipements_services'), '')::integer END AS niveau_equipements_services,
    NULLIF(TRIM(r._airbyte_data ->> 'niveau_equipements_services_texte'), '') AS niveau_equipements_services_texte,
    CASE WHEN NULLIF(TRIM(r._airbyte_data ->> 'qpv_nombre'), '') ~ '^-?[0-9]+$' THEN NULLIF(TRIM(r._airbyte_data ->> 'qpv_nombre'), '')::integer END AS qpv_nombre,
    NULLIF(TRIM(r._airbyte_data ->> 'gentile'), '') AS gentile,
    NULLIF(TRIM(r._airbyte_data ->> 'url_wikipedia'), '') AS url_wikipedia,
    NULLIF(TRIM(r._airbyte_data ->> 'url_villedereve'), '') AS url_villedereve,
    'csv_communes_data_gouv'::text                      AS source_system,
    NULLIF(TRIM(r._airbyte_data ->> 'code_insee'), '')                               AS source_record_id,
    CAST(r._airbyte_extracted_at AS timestamptz)        AS ingested_at_utc
FROM ranked AS r
WHERE r.rn = 1;
