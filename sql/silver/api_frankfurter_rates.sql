-- silver.api_frankfurter_rates : taux de change de reference (API Frankfurter v2, source BCE)
-- Grain : un taux pour une date et une devise cotee. Cle : (rate_date, base_currency, quote_currency).
--
-- STRUCTURE BRONZE CONSTATEE (\d bronze.api_frankfurter) :
--   _airbyte_raw_id, _airbyte_extracted_at, _airbyte_meta (jsonb), _airbyte_generation_id,
--   _airbyte_data (jsonb), _ab_source_file_url, _ab_source_file_last_modified.
--   Le contenu de l'API (date, base, quote, rate) est dans la colonne jsonb _airbyte_data :
--   Bronze conserve la donnee brute, Silver l'interprete et la type.
--
-- DICTIONNAIRE (renommages justifies : "date", "base", "quote", "rate" sont des mots trop generiques
-- ou reserves ; le sens reste identique) :
--   _airbyte_data->>'date'  -> rate_date        (date du taux, type date)
--   _airbyte_data->>'base'  -> base_currency    (devise de base, texte, ex. EUR)
--   _airbyte_data->>'quote' -> quote_currency   (devise cotee, texte, ex. USD)
--   _airbyte_data->>'rate'  -> exchange_rate    (taux, numeric(18,6))
--
-- REGLES DE TRANSFORMATION :
--   1. Texte : TRIM, chaine vide -> NULL ; devises en MAJUSCULES.
--   2. Date : conversion seulement si le format est AAAA-MM-JJ, sinon NULL (compte par le test 8b).
--   3. Taux : conversion seulement si le format est numerique, sinon NULL (compte par le test 8b).
--   4. Deduplication : une ligne par (date, base, quote), la plus recente selon
--      _airbyte_extracted_at (egalite : _airbyte_raw_id). Lignes ecartees comptees par le test 6.
--   5. Lignes dont la cle est incomplete : exclues de Silver, comptees par le test 6.

CREATE OR REPLACE VIEW silver.api_frankfurter_rates AS
WITH cleaned AS (
    SELECT
        CASE WHEN NULLIF(TRIM(b._airbyte_data ->> 'date'), '')
                  ~ '^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$'
             THEN (TRIM(b._airbyte_data ->> 'date'))::date END                 AS rate_date,
        UPPER(NULLIF(TRIM(b._airbyte_data ->> 'base'), ''))                     AS base_currency,
        UPPER(NULLIF(TRIM(b._airbyte_data ->> 'quote'), ''))                    AS quote_currency,
        CASE WHEN NULLIF(TRIM(b._airbyte_data ->> 'rate'), '') ~ '^-?[0-9]+(\.[0-9]+)?$'
             THEN (TRIM(b._airbyte_data ->> 'rate'))::numeric(18,6) END         AS exchange_rate,
        b._airbyte_raw_id,
        b._airbyte_extracted_at
    FROM bronze.api_frankfurter AS b
),
ranked AS (
    SELECT
        c.*,
        ROW_NUMBER() OVER (
            PARTITION BY c.rate_date, c.base_currency, c.quote_currency
            ORDER BY c._airbyte_extracted_at DESC, c._airbyte_raw_id DESC
        ) AS rn
    FROM cleaned AS c
    WHERE c.rate_date IS NOT NULL
      AND c.base_currency IS NOT NULL
      AND c.quote_currency IS NOT NULL
)
SELECT
    r.rate_date,
    r.base_currency,
    r.quote_currency,
    r.exchange_rate,
    'api_frankfurter_ecb'::text                                              AS source_system,
    r.rate_date::text || '|' || r.base_currency || '|' || r.quote_currency   AS source_record_id,
    CAST(r._airbyte_extracted_at AS timestamptz)                             AS ingested_at_utc
FROM ranked AS r
WHERE r.rn = 1;
