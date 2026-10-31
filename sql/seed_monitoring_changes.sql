-- ===================================================
-- Hungarian Weather Lakehouse
-- Initial monitoring configuration change events
-- Source: simulated internal monitoring registry
-- ===================================================

-- 1. Create source change-event table

CREATE TABLE IF NOT EXISTS
hungarian_weather_lakehouse.silver.monitoring_changes (
    event_id STRING,
    city_code STRING,
    monitoring_priority STRING,
    effective_from DATE
)
USING DELTA;


-- 2. Insert initial events without duplicating
--    previously loaded event IDs

MERGE INTO
    hungarian_weather_lakehouse.silver.monitoring_changes AS tgt

USING (
    SELECT *
    FROM VALUES
        ('E001', 'budapest', 'Standard', DATE '2025-01-01'),
        ('E002', 'debrecen', 'Standard', DATE '2025-01-01'),
        ('E003', 'szeged',   'Standard', DATE '2025-01-01'),
        ('E004', 'pecs',     'Standard', DATE '2025-01-01'),
        ('E005', 'gyor',     'Standard', DATE '2025-01-01'),
        ('E006', 'budapest', 'Priority', DATE '2025-01-02')
    AS events (
        event_id,
        city_code,
        monitoring_priority,
        effective_from
    )
) AS src

ON tgt.event_id = src.event_id

WHEN NOT MATCHED THEN
    INSERT (
        event_id,
        city_code,
        monitoring_priority,
        effective_from
    )
    VALUES (
        src.event_id,
        src.city_code,
        src.monitoring_priority,
        src.effective_from
    );