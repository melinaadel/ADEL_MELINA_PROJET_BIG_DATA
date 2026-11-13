-- silver.csv_communes : liste des communes de France (CSV data.gouv.fr, Licence Ouverte 2.0)
-- Grain : une commune par ligne. Cle : code_insee (texte, 5 caracteres, zero initial conserve).
--
-- HYPOTHESES A VERIFIER AVANT EXECUTION (ne pas inventer : controler dans Adminer / psql) :
--   * table Bronze nommee bronze.csv_communes (nom du stream choisi dans Airbyte) ;
--   * colonnes Bronze = en-tete du CSV (deja en snake_case) ;
--   * colonnes techniques Airbyte presentes : _airbyte_raw_id, _airbyte_extracted_at.
--   Si un nom differe, adapter ce script ET le rapport.
--
-- REGLES DE TRANSFORMATION (a reprendre dans le rapport) :
--   1. Texte : TRIM, puis chaine vide -> NULL (une chaine vide n'a pas de sens metier ici).
--   2. Identifiants (code_insee, dep_code, reg_code, code_postal, ...) : conserves en TEXT.
--   3. Nombres : conversion seulement si la valeur a le bon format ; sinon NULL.
--      Le nombre de valeurs non converties est mesure par le test 8 (doit rester 0).
--   4. Decimaux : numeric(18,2) pour surfaces/densites/altitudes (arrondi a 2 decimales
--      ex. 55.060001373291016 -> 55.06) ; numeric(9,6) pour latitudes/longitudes.
--   5. Deduplication : une ligne par code_insee, la plus recente selon _airbyte_extracted_at
--      (egalite : _airbyte_raw_id). Les lignes ecartees sont comptees par le test 6.
--   6. Lignes sans code_insee : exclues de Silver, comptees par le test 6.

CREATE OR REPLACE VIEW silver.csv_communes AS
WITH ranked AS (
    SELECT
        b.*,
        ROW_NUMBER() OVER (
            PARTITION BY NULLIF(TRIM(CAST(b.code_insee AS text)), '')
            ORDER BY b._airbyte_extracted_at DESC, b._airbyte_raw_id DESC
        ) AS rn
    FROM bronze.csv_communes AS b
    WHERE NULLIF(TRIM(CAST(b.code_insee AS text)), '') IS NOT NULL
)
SELECT
    NULLIF(TRIM(CAST(r.code_insee AS text)), '') AS code_insee,
    NULLIF(TRIM(CAST(r.nom_standard AS text)), '') AS nom_standard,
    NULLIF(TRIM(CAST(r.nom_sans_pronom AS text)), '') AS nom_sans_pronom,
    NULLIF(TRIM(CAST(r.nom_a AS text)), '') AS nom_a,
    NULLIF(TRIM(CAST(r.nom_de AS text)), '') AS nom_de,
    NULLIF(TRIM(CAST(r.nom_sans_accent AS text)), '') AS nom_sans_accent,
    NULLIF(TRIM(CAST(r.nom_standard_majuscule AS text)), '') AS nom_standard_majuscule,
    NULLIF(TRIM(CAST(r.typecom AS text)), '') AS typecom,
    NULLIF(TRIM(CAST(r.typecom_texte AS text)), '') AS typecom_texte,
    NULLIF(TRIM(CAST(r.reg_code AS text)), '') AS reg_code,
    NULLIF(TRIM(CAST(r.reg_nom AS text)), '') AS reg_nom,
    NULLIF(TRIM(CAST(r.dep_code AS text)), '') AS dep_code,
    NULLIF(TRIM(CAST(r.dep_nom AS text)), '') AS dep_nom,
    NULLIF(TRIM(CAST(r.canton_code AS text)), '') AS canton_code,
    NULLIF(TRIM(CAST(r.canton_nom AS text)), '') AS canton_nom,
    NULLIF(TRIM(CAST(r.epci_code AS text)), '') AS epci_code,
    NULLIF(TRIM(CAST(r.epci_nom AS text)), '') AS epci_nom,
    NULLIF(TRIM(CAST(r.code_postal AS text)), '') AS code_postal,
    NULLIF(TRIM(CAST(r.codes_postaux AS text)), '') AS codes_postaux,
    NULLIF(TRIM(CAST(r.academie_code AS text)), '') AS academie_code,
    NULLIF(TRIM(CAST(r.academie_nom AS text)), '') AS academie_nom,
    NULLIF(TRIM(CAST(r.zone_emploi AS text)), '') AS zone_emploi,
    NULLIF(TRIM(CAST(r.zone_emploi_nom AS text)), '') AS zone_emploi_nom,
    NULLIF(TRIM(CAST(r.code_insee_centre_zone_emploi AS text)), '') AS code_insee_centre_zone_emploi,
    NULLIF(TRIM(CAST(r.code_unite_urbaine AS text)), '') AS code_unite_urbaine,
    NULLIF(TRIM(CAST(r.nom_unite_urbaine AS text)), '') AS nom_unite_urbaine,
    CASE WHEN NULLIF(TRIM(CAST(r.taille_unite_urbaine AS text)), '') ~ '^-?[0-9]+$' THEN NULLIF(TRIM(CAST(r.taille_unite_urbaine AS text)), '')::integer END AS taille_unite_urbaine,
    NULLIF(TRIM(CAST(r.type_commune_unite_urbaine AS text)), '') AS type_commune_unite_urbaine,
    NULLIF(TRIM(CAST(r.statut_commune_unite_urbaine AS text)), '') AS statut_commune_unite_urbaine,
    NULLIF(TRIM(CAST(r.code_aire_attraction AS text)), '') AS code_aire_attraction,
    NULLIF(TRIM(CAST(r.nom_aire_attraction AS text)), '') AS nom_aire_attraction,
    CASE WHEN NULLIF(TRIM(CAST(r.categorie_aire_attraction AS text)), '') ~ '^-?[0-9]+$' THEN NULLIF(TRIM(CAST(r.categorie_aire_attraction AS text)), '')::integer END AS categorie_aire_attraction,
    CASE WHEN NULLIF(TRIM(CAST(r.taille_aire_attraction AS text)), '') ~ '^-?[0-9]+$' THEN NULLIF(TRIM(CAST(r.taille_aire_attraction AS text)), '')::integer END AS taille_aire_attraction,
    NULLIF(TRIM(CAST(r.code_insee_centre_aire_attraction AS text)), '') AS code_insee_centre_aire_attraction,
    NULLIF(TRIM(CAST(r.code_bassin_de_vie AS text)), '') AS code_bassin_de_vie,
    NULLIF(TRIM(CAST(r.nom_bassin_de_vie AS text)), '') AS nom_bassin_de_vie,
    CASE WHEN NULLIF(TRIM(CAST(r.type_bassin_de_vie AS text)), '') ~ '^-?[0-9]+$' THEN NULLIF(TRIM(CAST(r.type_bassin_de_vie AS text)), '')::integer END AS type_bassin_de_vie,
    CASE WHEN NULLIF(TRIM(CAST(r.population AS text)), '') ~ '^-?[0-9]+$' THEN NULLIF(TRIM(CAST(r.population AS text)), '')::integer END AS population,
    CASE WHEN NULLIF(TRIM(CAST(r.superficie_hectare AS text)), '') ~ '^-?[0-9]+(\.[0-9]+)?$' THEN (NULLIF(TRIM(CAST(r.superficie_hectare AS text)), ''))::numeric(18,2) END AS superficie_hectare,
    CASE WHEN NULLIF(TRIM(CAST(r.superficie_km2 AS text)), '') ~ '^-?[0-9]+(\.[0-9]+)?$' THEN (NULLIF(TRIM(CAST(r.superficie_km2 AS text)), ''))::numeric(18,2) END AS superficie_km2,
    CASE WHEN NULLIF(TRIM(CAST(r.densite AS text)), '') ~ '^-?[0-9]+(\.[0-9]+)?$' THEN (NULLIF(TRIM(CAST(r.densite AS text)), ''))::numeric(18,2) END AS densite,
    CASE WHEN NULLIF(TRIM(CAST(r.superficie_cartographique_ign_hectare AS text)), '') ~ '^-?[0-9]+(\.[0-9]+)?$' THEN (NULLIF(TRIM(CAST(r.superficie_cartographique_ign_hectare AS text)), ''))::numeric(18,2) END AS superficie_cartographique_ign_hectare,
    CASE WHEN NULLIF(TRIM(CAST(r.superficie_cartographique_ign_km2 AS text)), '') ~ '^-?[0-9]+(\.[0-9]+)?$' THEN (NULLIF(TRIM(CAST(r.superficie_cartographique_ign_km2 AS text)), ''))::numeric(18,2) END AS superficie_cartographique_ign_km2,
    CASE WHEN NULLIF(TRIM(CAST(r.densite_cartographique AS text)), '') ~ '^-?[0-9]+(\.[0-9]+)?$' THEN (NULLIF(TRIM(CAST(r.densite_cartographique AS text)), ''))::numeric(18,2) END AS densite_cartographique,
    CASE WHEN NULLIF(TRIM(CAST(r.superficie_cadastrale_ign_hectare AS text)), '') ~ '^-?[0-9]+(\.[0-9]+)?$' THEN (NULLIF(TRIM(CAST(r.superficie_cadastrale_ign_hectare AS text)), ''))::numeric(18,2) END AS superficie_cadastrale_ign_hectare,
    CASE WHEN NULLIF(TRIM(CAST(r.superficie_cadastrale_ign_km2 AS text)), '') ~ '^-?[0-9]+(\.[0-9]+)?$' THEN (NULLIF(TRIM(CAST(r.superficie_cadastrale_ign_km2 AS text)), ''))::numeric(18,2) END AS superficie_cadastrale_ign_km2,
    CASE WHEN NULLIF(TRIM(CAST(r.densite_cadastrale AS text)), '') ~ '^-?[0-9]+(\.[0-9]+)?$' THEN (NULLIF(TRIM(CAST(r.densite_cadastrale AS text)), ''))::numeric(18,2) END AS densite_cadastrale,
    CASE WHEN NULLIF(TRIM(CAST(r.altitude_moyenne AS text)), '') ~ '^-?[0-9]+(\.[0-9]+)?$' THEN (NULLIF(TRIM(CAST(r.altitude_moyenne AS text)), ''))::numeric(18,2) END AS altitude_moyenne,
    CASE WHEN NULLIF(TRIM(CAST(r.altitude_minimale AS text)), '') ~ '^-?[0-9]+(\.[0-9]+)?$' THEN (NULLIF(TRIM(CAST(r.altitude_minimale AS text)), ''))::numeric(18,2) END AS altitude_minimale,
    CASE WHEN NULLIF(TRIM(CAST(r.altitude_maximale AS text)), '') ~ '^-?[0-9]+(\.[0-9]+)?$' THEN (NULLIF(TRIM(CAST(r.altitude_maximale AS text)), ''))::numeric(18,2) END AS altitude_maximale,
    CASE WHEN NULLIF(TRIM(CAST(r.latitude_mairie AS text)), '') ~ '^-?[0-9]+(\.[0-9]+)?$' THEN (NULLIF(TRIM(CAST(r.latitude_mairie AS text)), ''))::numeric(9,6) END AS latitude_mairie,
    CASE WHEN NULLIF(TRIM(CAST(r.longitude_mairie AS text)), '') ~ '^-?[0-9]+(\.[0-9]+)?$' THEN (NULLIF(TRIM(CAST(r.longitude_mairie AS text)), ''))::numeric(9,6) END AS longitude_mairie,
    CASE WHEN NULLIF(TRIM(CAST(r.latitude_centre AS text)), '') ~ '^-?[0-9]+(\.[0-9]+)?$' THEN (NULLIF(TRIM(CAST(r.latitude_centre AS text)), ''))::numeric(9,6) END AS latitude_centre,
    CASE WHEN NULLIF(TRIM(CAST(r.longitude_centre AS text)), '') ~ '^-?[0-9]+(\.[0-9]+)?$' THEN (NULLIF(TRIM(CAST(r.longitude_centre AS text)), ''))::numeric(9,6) END AS longitude_centre,
    CASE WHEN NULLIF(TRIM(CAST(r.grille_densite AS text)), '') ~ '^-?[0-9]+$' THEN NULLIF(TRIM(CAST(r.grille_densite AS text)), '')::integer END AS grille_densite,
    NULLIF(TRIM(CAST(r.grille_densite_texte AS text)), '') AS grille_densite_texte,
    CASE WHEN NULLIF(TRIM(CAST(r.niveau_equipements_services AS text)), '') ~ '^-?[0-9]+$' THEN NULLIF(TRIM(CAST(r.niveau_equipements_services AS text)), '')::integer END AS niveau_equipements_services,
    NULLIF(TRIM(CAST(r.niveau_equipements_services_texte AS text)), '') AS niveau_equipements_services_texte,
    CASE WHEN NULLIF(TRIM(CAST(r.qpv_nombre AS text)), '') ~ '^-?[0-9]+$' THEN NULLIF(TRIM(CAST(r.qpv_nombre AS text)), '')::integer END AS qpv_nombre,
    NULLIF(TRIM(CAST(r.gentile AS text)), '') AS gentile,
    NULLIF(TRIM(CAST(r.url_wikipedia AS text)), '') AS url_wikipedia,
    NULLIF(TRIM(CAST(r.url_villedereve AS text)), '') AS url_villedereve,
    'csv_communes_data_gouv'::text                      AS source_system,
    NULLIF(TRIM(CAST(r.code_insee AS text)), '')        AS source_record_id,
    CAST(r._airbyte_extracted_at AS timestamptz)        AS ingested_at_utc
FROM ranked AS r
WHERE r.rn = 1;
