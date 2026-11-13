-- TEMPLATE : à adapter à chaque source. Ne recopiez pas des noms de champs qui n'existent pas.
-- Objectif : standardiser sans mélanger les sources entre elles.

CREATE OR REPLACE VIEW silver.<nom_table> AS
SELECT
    CAST(<cle_source> AS text)                   AS record_id,
    NULLIF(TRIM(CAST(<champ_texte> AS text)), '') AS <champ_texte_normalise>,
    CAST(<champ_date> AS date)                   AS <champ_date_normalise>,
    CAST(<champ_nombre> AS numeric(18,2))        AS <champ_nombre_normalise>,
    '<source>'::text                             AS source_system,
    CAST(<cle_source> AS text)                   AS source_record_id,
    COALESCE(<timestamp_ingestion>, now())       AS ingested_at_utc
FROM bronze.<nom_table_bronze>;

-- Ajoutez une règle de déduplication explicite si Bronze peut contenir plusieurs versions
-- de la même clé. Conservez toujours une justification et une trace du choix effectué.
