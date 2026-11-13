-- Controles Bronze : volumes, cles, provenance (a executer apres les synchronisations Airbyte).
-- Resultat conserve dans preuves/controles_bronze.txt.

-- CONTROLE 1 - Volumes, cles distinctes et cles nulles par table Bronze
SELECT 'api_frankfurter' AS table_bronze, COUNT(*) AS lignes,
       COUNT(DISTINCT (_airbyte_data ->> 'date', _airbyte_data ->> 'base', _airbyte_data ->> 'quote')) AS cles_distinctes,
       COUNT(*) FILTER (WHERE _airbyte_data ->> 'date' IS NULL OR _airbyte_data ->> 'quote' IS NULL) AS cles_nulles
FROM bronze.api_frankfurter
UNION ALL
SELECT 'csv_communes', COUNT(*), COUNT(DISTINCT _airbyte_data ->> 'code_insee'),
       COUNT(*) FILTER (WHERE NULLIF(TRIM(_airbyte_data ->> 'code_insee'), '') IS NULL)
FROM bronze.csv_communes
UNION ALL SELECT 'account', COUNT(*), COUNT(DISTINCT id), COUNT(*) FILTER (WHERE id IS NULL) FROM bronze.account
UNION ALL SELECT 'contact', COUNT(*), COUNT(DISTINCT id), COUNT(*) FILTER (WHERE id IS NULL) FROM bronze.contact
UNION ALL SELECT 'opportunity', COUNT(*), COUNT(DISTINCT id), COUNT(*) FILTER (WHERE id IS NULL) FROM bronze.opportunity
UNION ALL SELECT 'account_contact', COUNT(*), COUNT(DISTINCT id), COUNT(*) FILTER (WHERE id IS NULL) FROM bronze.account_contact
UNION ALL SELECT 'contact_opportunity', COUNT(*), COUNT(DISTINCT id), COUNT(*) FILTER (WHERE id IS NULL) FROM bronze.contact_opportunity;

-- CONTROLE 2 - Provenance des lots fichiers : cle MinIO d'origine, job Airbyte, date d'extraction
SELECT 'api_frankfurter' AS table_bronze, _ab_source_file_url::text AS cle_minio,
       _ab_source_file_last_modified::text AS fichier_modifie_le,
       _airbyte_meta ->> 'sync_id' AS job_airbyte, MIN(_airbyte_extracted_at) AS extrait_le, COUNT(*) AS lignes
FROM bronze.api_frankfurter GROUP BY 1, 2, 3, 4
UNION ALL
SELECT 'csv_communes', _ab_source_file_url::text, _ab_source_file_last_modified::text,
       _airbyte_meta ->> 'sync_id', MIN(_airbyte_extracted_at), COUNT(*)
FROM bronze.csv_communes GROUP BY 1, 2, 3, 4
ORDER BY 1, 2;

-- CONTROLE 3 - Provenance CRM : job Airbyte et date d'extraction par table
SELECT 'account' AS table_bronze, _airbyte_meta ->> 'sync_id' AS job_airbyte, MIN(_airbyte_extracted_at) AS extrait_le, COUNT(*) AS lignes FROM bronze.account GROUP BY 1, 2
UNION ALL SELECT 'contact', _airbyte_meta ->> 'sync_id', MIN(_airbyte_extracted_at), COUNT(*) FROM bronze.contact GROUP BY 1, 2
UNION ALL SELECT 'opportunity', _airbyte_meta ->> 'sync_id', MIN(_airbyte_extracted_at), COUNT(*) FROM bronze.opportunity GROUP BY 1, 2
UNION ALL SELECT 'account_contact', _airbyte_meta ->> 'sync_id', MIN(_airbyte_extracted_at), COUNT(*) FROM bronze.account_contact GROUP BY 1, 2
UNION ALL SELECT 'contact_opportunity', _airbyte_meta ->> 'sync_id', MIN(_airbyte_extracted_at), COUNT(*) FROM bronze.contact_opportunity GROUP BY 1, 2
ORDER BY 1;

-- CONTROLE 4 - Structure observee : colonnes de chaque table Bronze
SELECT table_name, COUNT(*) AS nb_colonnes,
       STRING_AGG(column_name, ', ' ORDER BY ordinal_position) FILTER (WHERE column_name LIKE '\_a%') AS colonnes_techniques
FROM information_schema.columns
WHERE table_schema = 'bronze'
GROUP BY table_name ORDER BY table_name;
