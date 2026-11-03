
-- =============================================
-- Hungarian Weather Lakehouse
-- Post-pipeline data quality validation
-- =============================================

-- CHECK 1: Fact table integrity
WITH fact_checks AS (
    SELECT
        COUNT(*) AS total_rows,
        COUNT(DISTINCT location_key, hour_utc, source_key)
            AS unique_rows,
        COUNT_IF(
            location_key IS NULL
            OR date_key IS NULL
            OR source_key IS NULL
            OR monitoring_key IS NULL
        ) AS missing_keys
    FROM hungarian_weather_lakehouse.gold.fact_hourly_weather
)
SELECT
    assert_true(
        total_rows > 0,
        'FACT CHECK FAILED: Fact table is empty'
    ) AS nonempty_check,

    assert_true(
        total_rows = unique_rows,
        'FACT CHECK FAILED: Duplicate business grain'
    ) AS uniqueness_check,

    assert_true(
        missing_keys = 0,
        'FACT CHECK FAILED: Missing dimension keys'
    ) AS dimension_check
FROM fact_checks;


-- CHECK 2: SCD2 interval consistency
WITH ordered_versions AS (
    SELECT
        city_code,
        valid_from,
        valid_to,
        is_current,
        LEAD(valid_from) OVER (
            PARTITION BY city_code
            ORDER BY valid_from, source_event_id
        ) AS next_valid_from
    FROM hungarian_weather_lakehouse.gold.dim_monitoring_status
)
SELECT
    assert_true(
        COUNT(*) > 0,
        'SCD2 CHECK FAILED: No historical versions'
    ) AS nonempty_check,

    assert_true(
        COUNT_IF(
            NOT (valid_to <=> next_valid_from)
        ) = 0,
        'SCD2 CHECK FAILED: Gap or overlap in intervals'
    ) AS interval_check,

    assert_true(
        COUNT_IF(
            is_current <> (valid_to IS NULL)
        ) = 0,
        'SCD2 CHECK FAILED: Invalid current flags'
    ) AS current_flag_check,

    assert_true(
        COUNT_IF(valid_to <= valid_from) = 0,
        'SCD2 CHECK FAILED: Invalid date interval'
    ) AS date_check
FROM ordered_versions;


-- CHECK 3: Reporting reconciliation
SELECT
    assert_true(
        (
            SELECT COUNT(*)
            FROM hungarian_weather_lakehouse.gold.fact_hourly_weather
        ) = (
            SELECT COALESCE(SUM(hours_reported), 0)
            FROM hungarian_weather_lakehouse.gold.daily_weather_local
        ),
        'REPORT CHECK FAILED: Local daily totals do not reconcile'
    ) AS local_reconciliation,

    assert_true(
        (
            SELECT COUNT(*)
            FROM hungarian_weather_lakehouse.gold.fact_hourly_weather
        ) = (
            SELECT COALESCE(SUM(hours_reported), 0)
            FROM hungarian_weather_lakehouse.gold.daily_weather_summary
        ),
        'REPORT CHECK FAILED: UTC daily totals do not reconcile'
    ) AS utc_reconciliation;
