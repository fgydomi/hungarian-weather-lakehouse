-- ===================================================
-- Hungarian Weather Lakehouse
-- SCD Type 2 - Monitoring Status Dimension
-- ===================================================

-- 1. Create the historical dimension

CREATE TABLE IF NOT EXISTS
hungarian_weather_lakehouse.gold.dim_monitoring_status (
    monitoring_key BIGINT
        GENERATED ALWAYS AS IDENTITY
        (START WITH 301 INCREMENT BY 1),

    source_event_id STRING NOT NULL,
    city_code STRING NOT NULL,
    monitoring_priority STRING NOT NULL,

    valid_from DATE NOT NULL,
    valid_to DATE,
    is_current BOOLEAN NOT NULL
)
USING DELTA;


-- 2. Derive validity intervals and synchronize SCD2

MERGE INTO
    hungarian_weather_lakehouse.gold.dim_monitoring_status AS tgt

USING (
    SELECT
        event_id,
        city_code,
        monitoring_priority,

        effective_from AS valid_from,

        LEAD(effective_from) OVER (
            PARTITION BY city_code
            ORDER BY effective_from, event_id
        ) AS valid_to

    FROM hungarian_weather_lakehouse.silver.monitoring_changes
) AS src

ON tgt.source_event_id = src.event_id


-- Update existing historical versions when
-- their attributes or validity intervals change

WHEN MATCHED AND (
    tgt.city_code <> src.city_code
    OR tgt.monitoring_priority <> src.monitoring_priority
    OR tgt.valid_from <> src.valid_from
    OR NOT (tgt.valid_to <=> src.valid_to)
    OR tgt.is_current <> (src.valid_to IS NULL)
)
THEN UPDATE SET
    tgt.city_code = src.city_code,
    tgt.monitoring_priority = src.monitoring_priority,
    tgt.valid_from = src.valid_from,
    tgt.valid_to = src.valid_to,
    tgt.is_current = (src.valid_to IS NULL)


-- New events create new historical versions
-- and receive automatically generated surrogate keys

WHEN NOT MATCHED THEN
INSERT (
    source_event_id,
    city_code,
    monitoring_priority,
    valid_from,
    valid_to,
    is_current
)
VALUES (
    src.event_id,
    src.city_code,
    src.monitoring_priority,
    src.valid_from,
    src.valid_to,
    src.valid_to IS NULL
);