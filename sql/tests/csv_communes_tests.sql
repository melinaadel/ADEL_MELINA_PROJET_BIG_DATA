-- Tests Silver : silver.csv_communes (a executer dans Adminer ou psql).
-- Pour chaque test : coller la requete, le resultat obtenu et votre interpretation dans le rapport.

-- TEST 1 - Cle non nulle. Attendu : 0
SELECT COUNT(*) AS cles_nulles
FROM silver.csv_communes
WHERE source_record_id IS NULL OR source_record_id = '';

-- TEST 2 - Unicite de la cle au grain annonce. Attendu : 0 ligne
SELECT source_record_id, COUNT(*) AS n
FROM silver.csv_communes
GROUP BY source_record_id
HAVING COUNT(*) > 1;

-- TEST 3 - Doublons : quantifies en Bronze, nuls en Silver. Attendu : silver = 0
SELECT
  (SELECT COUNT(*) - COUNT(DISTINCT NULLIF(TRIM(CAST(code_insee AS text)), ''))
     FROM bronze.csv_communes
    WHERE NULLIF(TRIM(CAST(code_insee AS text)), '') IS NOT NULL) AS doublons_bronze,
  (SELECT COUNT(*) - COUNT(DISTINCT source_record_id)
     FROM silver.csv_communes)                                       AS doublons_silver;

-- TEST 4 - Nommage snake_case. Attendu : 0 ligne
SELECT column_name
FROM information_schema.columns
WHERE table_schema = 'silver' AND table_name = 'csv_communes'
  AND column_name !~ '^[a-z][a-z0-9_]*$';

-- TEST 5 - Types observes (a comparer au contrat : identifiants en text, population en integer,
-- surfaces numeric(18,2), coordonnees numeric(9,6), ingested_at_utc timestamptz)
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'silver' AND table_name = 'csv_communes'
ORDER BY ordinal_position;

-- TEST 6 - Reconciliation Bronze / Silver. L'ecart doit etre = lignes sans cle + doublons ecartes
SELECT
  (SELECT COUNT(*) FROM bronze.csv_communes) AS bronze_rows,
  (SELECT COUNT(*) FROM silver.csv_communes) AS silver_rows,
  (SELECT COUNT(*) FROM bronze.csv_communes
    WHERE NULLIF(TRIM(CAST(code_insee AS text)), '') IS NULL) AS lignes_sans_cle,
  (SELECT COUNT(*) FROM bronze.csv_communes) - (SELECT COUNT(*) FROM silver.csv_communes) AS ecart;

-- TEST 7 - Tracabilite. Attendu : 0, 0, 0
SELECT
  COUNT(*) FILTER (WHERE source_system IS NULL)    AS source_system_null,
  COUNT(*) FILTER (WHERE source_record_id IS NULL) AS source_record_id_null,
  COUNT(*) FILTER (WHERE ingested_at_utc IS NULL)  AS ingested_at_null
FROM silver.csv_communes;

-- TEST 8 - Regles metier. Attendu : 0 pour chaque colonne
SELECT
  COUNT(*) FILTER (WHERE code_insee !~ '^([0-9]{5}|2[AB][0-9]{3})$')   AS code_insee_format_invalide,
  COUNT(*) FILTER (WHERE population < 0)                               AS population_negative,
  COUNT(*) FILTER (WHERE latitude_mairie  NOT BETWEEN -90  AND 90)     AS latitude_hors_plage,
  COUNT(*) FILTER (WHERE longitude_mairie NOT BETWEEN -180 AND 180)    AS longitude_hors_plage
FROM silver.csv_communes;

-- TEST 8b - Valeurs non vides en Bronze qui n'ont pas pu etre converties en nombre. Attendu : 0
SELECT COUNT(*) AS population_non_convertie
FROM bronze.csv_communes b
WHERE NULLIF(TRIM(CAST(b.population AS text)), '') IS NOT NULL
  AND NULLIF(TRIM(CAST(b.population AS text)), '') !~ '^-?[0-9]+$';
