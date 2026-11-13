-- Silver CRM (EspoCRM / MariaDB) : 5 vues silver.crm_<entite>, une par table Bronze utile.
--
-- STRUCTURE BRONZE CONSTATEE (information_schema, schema bronze) :
--   bronze.account, bronze.contact, bronze.opportunity : colonnes metier typees par Airbyte
--     (id varchar, deleted boolean, created_at / modified_at timestamp sans fuseau, amount numeric,
--      close_date date, probability bigint...) + colonnes techniques _airbyte_raw_id,
--     _airbyte_extracted_at, _airbyte_meta, _airbyte_generation_id.
--     Mode de sync : Incremental | Append, curseur modified_at -> chaque modification d'une fiche
--     ajoute une nouvelle version en Bronze.
--   bronze.account_contact, bronze.contact_opportunity : tables de relation (id bigint, deleted boolean).
--     Mode de sync : Full refresh | Overwrite + Deduped (cle id), car elles n'ont pas de colonne
--     de date de modification utilisable comme curseur.
--   Bronze garde les noms physiques d'origine de MariaDB ; le prefixe de source crm_ est applique en Silver.
--
-- DICTIONNAIRE (Bronze -> Silver) :
--   id            -> account_id / contact_id / opportunity_id (identifiant metier, text : ce n'est pas un nombre)
--   name          -> account_name / opportunity_name ("name" seul est trop generique)
--   type          -> account_type ("type" est un mot trop generique)
--   billing_address_city / _country -> billing_city / billing_country
--   role          -> contact_role (role du contact dans la relation)
--   deleted       -> is_deleted (suppression logique EspoCRM, boolean)
--   created_at / modified_at -> created_at_utc / modified_at_utc (timestamptz)
--   amount -> numeric(18,2) ; probability -> integer ; close_date -> date
--   account_id, contact_id, opportunity_id gardent le meme nom partout : meme concept, meme nom.
--
-- REGLES DE TRANSFORMATION (identiques pour les 5 vues) :
--   1. Texte : TRIM, chaine vide -> NULL (une chaine vide ne porte aucune information dans EspoCRM).
--      Code devise en MAJUSCULES.
--   2. Horodatages : EspoCRM enregistre created_at / modified_at en UTC sans fuseau ;
--      Silver les declare en UTC (AT TIME ZONE 'UTC') -> timestamptz.
--   3. Deduplication (jamais de DISTINCT) :
--      - entites : une ligne par id, la version la plus recente selon modified_at,
--        puis _airbyte_extracted_at, puis _airbyte_raw_id ;
--      - relations : une ligne par couple de cles, la plus recente selon _airbyte_extracted_at, puis id.
--      Les lignes ecartees sont comptees par le test 6.
--   4. Suppression logique : les lignes deleted = true sont CONSERVEES avec is_deleted = true
--      (pas de filtrage silencieux ; le consommateur filtre s'il le souhaite).
--   5. Lignes dont la cle est NULL : exclues de Silver, comptees par le test 6.
--   6. Tracabilite : source_system = 'crm_espocrm', source_record_id = id d'origine,
--      ingested_at_utc = _airbyte_extracted_at (date d'extraction Airbyte).

-- ---------------------------------------------------------------------------
-- silver.crm_account : une ligne par compte (societe). Cle : account_id.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW silver.crm_account AS
WITH cleaned AS (
    SELECT
        NULLIF(TRIM(b.id), '')                       AS account_id,
        NULLIF(TRIM(b.name), '')                     AS account_name,
        NULLIF(TRIM(b.type), '')                     AS account_type,
        NULLIF(TRIM(b.industry), '')                 AS industry,
        NULLIF(TRIM(b.website), '')                  AS website,
        NULLIF(TRIM(b.billing_address_city), '')     AS billing_city,
        NULLIF(TRIM(b.billing_address_country), '')  AS billing_country,
        b.deleted                                    AS is_deleted,
        b.created_at  AT TIME ZONE 'UTC'             AS created_at_utc,
        b.modified_at AT TIME ZONE 'UTC'             AS modified_at_utc,
        b._airbyte_raw_id,
        b._airbyte_extracted_at
    FROM bronze.account AS b
),
ranked AS (
    SELECT
        c.*,
        ROW_NUMBER() OVER (
            PARTITION BY c.account_id
            ORDER BY c.modified_at_utc DESC NULLS LAST, c._airbyte_extracted_at DESC, c._airbyte_raw_id DESC
        ) AS rn
    FROM cleaned AS c
    WHERE c.account_id IS NOT NULL
)
SELECT
    r.account_id,
    r.account_name,
    r.account_type,
    r.industry,
    r.website,
    r.billing_city,
    r.billing_country,
    r.is_deleted,
    r.created_at_utc,
    r.modified_at_utc,
    'crm_espocrm'::text                           AS source_system,
    r.account_id                                  AS source_record_id,
    CAST(r._airbyte_extracted_at AS timestamptz)  AS ingested_at_utc
FROM ranked AS r
WHERE r.rn = 1;

-- ---------------------------------------------------------------------------
-- silver.crm_contact : une ligne par contact (personne). Cle : contact_id.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW silver.crm_contact AS
WITH cleaned AS (
    SELECT
        NULLIF(TRIM(b.id), '')            AS contact_id,
        NULLIF(TRIM(b.first_name), '')    AS first_name,
        NULLIF(TRIM(b.last_name), '')     AS last_name,
        NULLIF(TRIM(b.account_id), '')    AS account_id,
        b.deleted                         AS is_deleted,
        b.created_at  AT TIME ZONE 'UTC'  AS created_at_utc,
        b.modified_at AT TIME ZONE 'UTC'  AS modified_at_utc,
        b._airbyte_raw_id,
        b._airbyte_extracted_at
    FROM bronze.contact AS b
),
ranked AS (
    SELECT
        c.*,
        ROW_NUMBER() OVER (
            PARTITION BY c.contact_id
            ORDER BY c.modified_at_utc DESC NULLS LAST, c._airbyte_extracted_at DESC, c._airbyte_raw_id DESC
        ) AS rn
    FROM cleaned AS c
    WHERE c.contact_id IS NOT NULL
)
SELECT
    r.contact_id,
    r.first_name,
    r.last_name,
    r.account_id,
    r.is_deleted,
    r.created_at_utc,
    r.modified_at_utc,
    'crm_espocrm'::text                           AS source_system,
    r.contact_id                                  AS source_record_id,
    CAST(r._airbyte_extracted_at AS timestamptz)  AS ingested_at_utc
FROM ranked AS r
WHERE r.rn = 1;

-- ---------------------------------------------------------------------------
-- silver.crm_opportunity : une ligne par opportunite. Cle : opportunity_id.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW silver.crm_opportunity AS
WITH cleaned AS (
    SELECT
        NULLIF(TRIM(b.id), '')                      AS opportunity_id,
        NULLIF(TRIM(b.name), '')                    AS opportunity_name,
        NULLIF(TRIM(b.stage), '')                   AS stage,
        CAST(b.amount AS numeric(18,2))             AS amount,
        UPPER(NULLIF(TRIM(b.amount_currency), ''))  AS amount_currency,
        CAST(b.probability AS integer)              AS probability,
        CAST(b.close_date AS date)                  AS close_date,
        NULLIF(TRIM(b.lead_source), '')             AS lead_source,
        NULLIF(TRIM(b.account_id), '')              AS account_id,
        b.deleted                                   AS is_deleted,
        b.created_at  AT TIME ZONE 'UTC'            AS created_at_utc,
        b.modified_at AT TIME ZONE 'UTC'            AS modified_at_utc,
        b._airbyte_raw_id,
        b._airbyte_extracted_at
    FROM bronze.opportunity AS b
),
ranked AS (
    SELECT
        c.*,
        ROW_NUMBER() OVER (
            PARTITION BY c.opportunity_id
            ORDER BY c.modified_at_utc DESC NULLS LAST, c._airbyte_extracted_at DESC, c._airbyte_raw_id DESC
        ) AS rn
    FROM cleaned AS c
    WHERE c.opportunity_id IS NOT NULL
)
SELECT
    r.opportunity_id,
    r.opportunity_name,
    r.stage,
    r.amount,
    r.amount_currency,
    r.probability,
    r.close_date,
    r.lead_source,
    r.account_id,
    r.is_deleted,
    r.created_at_utc,
    r.modified_at_utc,
    'crm_espocrm'::text                           AS source_system,
    r.opportunity_id                              AS source_record_id,
    CAST(r._airbyte_extracted_at AS timestamptz)  AS ingested_at_utc
FROM ranked AS r
WHERE r.rn = 1;

-- ---------------------------------------------------------------------------
-- silver.crm_account_contact : une ligne par lien compte <-> contact.
-- Cle : (account_id, contact_id).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW silver.crm_account_contact AS
WITH cleaned AS (
    SELECT
        NULLIF(TRIM(b.account_id), '')  AS account_id,
        NULLIF(TRIM(b.contact_id), '')  AS contact_id,
        NULLIF(TRIM(b.role), '')        AS contact_role,
        b.is_inactive                   AS is_inactive,
        b.deleted                       AS is_deleted,
        b.id                            AS relation_id,
        b._airbyte_extracted_at
    FROM bronze.account_contact AS b
),
ranked AS (
    SELECT
        c.*,
        ROW_NUMBER() OVER (
            PARTITION BY c.account_id, c.contact_id
            ORDER BY c._airbyte_extracted_at DESC, c.relation_id DESC
        ) AS rn
    FROM cleaned AS c
    WHERE c.account_id IS NOT NULL
      AND c.contact_id IS NOT NULL
)
SELECT
    r.account_id,
    r.contact_id,
    r.contact_role,
    r.is_inactive,
    r.is_deleted,
    'crm_espocrm'::text                           AS source_system,
    CAST(r.relation_id AS text)                   AS source_record_id,
    CAST(r._airbyte_extracted_at AS timestamptz)  AS ingested_at_utc
FROM ranked AS r
WHERE r.rn = 1;

-- ---------------------------------------------------------------------------
-- silver.crm_contact_opportunity : une ligne par lien contact <-> opportunite.
-- Cle : (contact_id, opportunity_id).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW silver.crm_contact_opportunity AS
WITH cleaned AS (
    SELECT
        NULLIF(TRIM(b.contact_id), '')      AS contact_id,
        NULLIF(TRIM(b.opportunity_id), '')  AS opportunity_id,
        NULLIF(TRIM(b.role), '')            AS contact_role,
        b.deleted                           AS is_deleted,
        b.id                                AS relation_id,
        b._airbyte_extracted_at
    FROM bronze.contact_opportunity AS b
),
ranked AS (
    SELECT
        c.*,
        ROW_NUMBER() OVER (
            PARTITION BY c.contact_id, c.opportunity_id
            ORDER BY c._airbyte_extracted_at DESC, c.relation_id DESC
        ) AS rn
    FROM cleaned AS c
    WHERE c.contact_id IS NOT NULL
      AND c.opportunity_id IS NOT NULL
)
SELECT
    r.contact_id,
    r.opportunity_id,
    r.contact_role,
    r.is_deleted,
    'crm_espocrm'::text                           AS source_system,
    CAST(r.relation_id AS text)                   AS source_record_id,
    CAST(r._airbyte_extracted_at AS timestamptz)  AS ingested_at_utc
FROM ranked AS r
WHERE r.rn = 1;
