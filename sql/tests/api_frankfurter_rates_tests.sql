-- Pour chaque test : coller la requete, le resultat obtenu et votre interpretation dans le rapport.
-- Rappel : en Bronze, le contenu de l'API est dans la colonne jsonb _airbyte_data.

-- TEST 1 - Cle non nulle. Attendu : 0
SELECT COUNT(*) AS cles_nulles
FROM silver.api_frankfurter_rates
WHERE rate_date IS NULL OR base_currency IS NULL OR quote_currency IS NULL;

-- TEST 2 - Unicite de la cle au grain annonce. Attendu : 0 ligne
SELECT rate_date, base_currency, quote_currency, COUNT(*) AS n
FROM silver.api_frankfurter_rates
GROUP BY rate_date, base_currency, quote_currency
HAVING COUNT(*) > 1;

-- TEST 3 - Doublons : quantifies en Bronze, nuls en Silver. Attendu : silver = 0
SELECT
  (SELECT COUNT(*) - COUNT(DISTINCT (_airbyte_data ->> 'date', _airbyte_data ->> 'base', _airbyte_data ->> 'quote'))
     FROM bronze.api_frankfurter) AS doublons_bronze,
  (SELECT COUNT(*) - COUNT(DISTINCT (rate_date, base_currency, quote_currency))
     FROM silver.api_frankfurter_rates) AS doublons_silver;

-- TEST 4 - Nommage snake_case. Attendu : 0 ligne
SELECT column_name
FROM information_schema.columns
WHERE table_schema = 'silver' AND table_name = 'api_frankfurter_rates'
  AND column_name !~ '^[a-z][a-z0-9_]*$';

-- TEST 5 - Types observes (contrat : rate_date date ; devises text ; exchange_rate numeric ;
-- ingested_at_utc timestamp with time zone)
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'silver' AND table_name = 'api_frankfurter_rates'
ORDER BY ordinal_position;

-- TEST 6 - Reconciliation Bronze / Silver. Attendu (lot de test) : 21 lignes chacun, ecart 0
SELECT
  (SELECT COUNT(*) FROM bronze.api_frankfurter) AS bronze_rows,
  (SELECT COUNT(*) FROM silver.api_frankfurter_rates) AS silver_rows,
  (SELECT COUNT(*) FROM bronze.api_frankfurter) - (SELECT COUNT(*) FROM silver.api_frankfurter_rates) AS ecart;

-- TEST 7 - Tracabilite. Attendu : 0, 0, 0
SELECT
  COUNT(*) FILTER (WHERE source_system IS NULL)    AS source_system_null,
  COUNT(*) FILTER (WHERE source_record_id IS NULL) AS source_record_id_null,
  COUNT(*) FILTER (WHERE ingested_at_utc IS NULL)  AS ingested_at_null
FROM silver.api_frankfurter_rates;

-- TEST 8 - Regles metier. Attendu : 0 pour chaque colonne
SELECT
  COUNT(*) FILTER (WHERE exchange_rate IS NULL OR exchange_rate <= 0)      AS taux_invalide,
  COUNT(*) FILTER (WHERE rate_date > CURRENT_DATE)                          AS date_future,
  COUNT(*) FILTER (WHERE EXTRACT(ISODOW FROM rate_date) IN (6, 7))          AS taux_un_week_end,
  COUNT(*) FILTER (WHERE base_currency <> 'EUR')                            AS base_differente_de_eur,
  COUNT(*) FILTER (WHERE quote_currency NOT IN ('USD', 'GBP', 'JPY'))       AS devise_hors_perimetre
FROM silver.api_frankfurter_rates;

-- TEST 8b - Valeurs Bronze non vides qui n'ont pas pu etre converties. Attendu : 0
SELECT
  COUNT(*) FILTER (WHERE NULLIF(TRIM(_airbyte_data ->> 'date'), '') IS NOT NULL
                     AND NULLIF(TRIM(_airbyte_data ->> 'date'), '')
                         !~ '^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$') AS dates_non_converties,
  COUNT(*) FILTER (WHERE NULLIF(TRIM(_airbyte_data ->> 'rate'), '') IS NOT NULL
                     AND NULLIF(TRIM(_airbyte_data ->> 'rate'), '') !~ '^-?[0-9]+(\.[0-9]+)?$') AS taux_non_convertis
FROM bronze.api_frankfurter;
