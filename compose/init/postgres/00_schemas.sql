CREATE SCHEMA IF NOT EXISTS bronze AUTHORIZATION warehouse;
CREATE SCHEMA IF NOT EXISTS silver AUTHORIZATION warehouse;

COMMENT ON SCHEMA bronze IS 'Couche Bronze : données proches de la source, traçables, sans correction métier silencieuse.';
COMMENT ON SCHEMA silver IS 'Couche Silver : données standardisées, typées, dédupliquées et contrôlées.';
