
-- ====================================================
-- SCD Type 2: Late-arriving historical change demo
-- Simulated monitoring configuration events
--
-- Reproduction order:
-- 1. Insert E007
-- 2. Run merge_dim_monitoring_status.sql
-- 3. Insert E008 (the late-arriving event)
-- 4. Run merge_dim_monitoring_status.sql again
-- 5. Refresh the Lakeflow weather pipeline
-- ====================================================

-- STEP 1: A newer status arrives first
-- Budapest returns to Standard on January 4.

MERGE INTO
    hungarian_weather_lakehouse.silver.monitoring_changes AS tgt
USING (
    SELECT
        'E007' AS event_id,
        'budapest' AS city_code,
        'Standard' AS monitoring_priority,
        DATE '2025-01-04' AS effective_from
) AS src
ON tgt.event_id = src.event_id
WHEN NOT MATCHED THEN INSERT (
    event_id, city_code, monitoring_priority, effective_from
)
VALUES (
    src.event_id, src.city_code,
    src.monitoring_priority, src.effective_from
);


-- Run merge_dim_monitoring_status.sql before STEP 2.


-- STEP 2: An older change arrives late
-- Budapest was Critical from January 3.

MERGE INTO
    hungarian_weather_lakehouse.silver.monitoring_changes AS tgt
USING (
    SELECT
        'E008' AS event_id,
        'budapest' AS city_code,
        'Critical' AS monitoring_priority,
        DATE '2025-01-03' AS effective_from
) AS src
ON tgt.event_id = src.event_id
WHEN NOT MATCHED THEN INSERT (
    event_id, city_code, monitoring_priority, effective_from
)
VALUES (
    src.event_id, src.city_code,
    src.monitoring_priority, src.effective_from
);

-- Run the SCD2 MERGE and weather pipeline again.
-- Expected: 8 dimension versions, 360 weather facts.