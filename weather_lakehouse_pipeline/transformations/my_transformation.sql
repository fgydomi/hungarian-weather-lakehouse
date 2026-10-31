CREATE OR REFRESH STREAMING TABLE weather_raw
COMMENT 'One row per Open-Meteo source response file'
AS
SELECT
    *,
    _metadata.file_name AS source_file,
    _metadata.file_path AS source_file_path,
    current_timestamp() AS ingested_at_utc
FROM STREAM read_files(
    '/Volumes/hungarian_weather_lakehouse/raw/weather_landing/responses/',
    format => 'json',
    multiLine => true,
    inferColumnTypes => true
);



CREATE OR REFRESH MATERIALIZED VIEW
hungarian_weather_lakehouse.silver.weather_hourly
(
    CONSTRAINT valid_city
        EXPECT (city <> '')
        ON VIOLATION FAIL UPDATE,

    CONSTRAINT valid_timestamp
        EXPECT (hour_utc IS NOT NULL)
        ON VIOLATION FAIL UPDATE,

    CONSTRAINT non_negative_precipitation
        EXPECT (
            precipitation_mm >= 0
            OR precipitation_mm IS NULL
        )
)
COMMENT 'One accepted hourly observation per city and weather model'
AS

WITH flattened AS (
    SELECT
        regexp_extract(
            b.source_file, '^([a-z]+)_', 1
        ) AS city,

        make_timestamp(
            TRY_CAST(SUBSTRING(h.hour_string, 1, 4) AS INT),
            TRY_CAST(SUBSTRING(h.hour_string, 6, 2) AS INT),
            TRY_CAST(SUBSTRING(h.hour_string, 9, 2) AS INT),
            TRY_CAST(SUBSTRING(h.hour_string, 12, 2) AS INT),
            TRY_CAST(SUBSTRING(h.hour_string, 15, 2) AS INT),
            0,
            'UTC'
        ) AS hour_utc,

        TRY_CAST(
            get(b.hourly.temperature_2m, h.pos)
            AS DOUBLE
        ) AS temperature_c,

        TRY_CAST(
            get(b.hourly.precipitation, h.pos)
            AS DOUBLE
        ) AS precipitation_mm,

        TRY_CAST(
            get(b.hourly.wind_speed_10m, h.pos)
            AS DOUBLE
        ) AS wind_speed_kmh,

        'era5' AS weather_model,

        b.source_file,
        b.source_file_path,
        b.ingested_at_utc

    FROM hungarian_weather_lakehouse.bronze.weather_raw AS b,
    LATERAL posexplode(b.hourly.time)
        AS h(pos, hour_string)
)

SELECT *
FROM flattened

QUALIFY ROW_NUMBER() OVER (
    PARTITION BY city, hour_utc, weather_model
    ORDER BY ingested_at_utc DESC, source_file_path DESC
) = 1;



CREATE OR REFRESH MATERIALIZED VIEW
hungarian_weather_lakehouse.gold.daily_weather_summary
COMMENT 'Daily weather metrics derived from the Gold star schema'
AS
SELECT
    l.city_code AS city,
    d.full_date AS date_utc,
    w.weather_model,

    COUNT(*) AS hours_reported,
    COUNT(f.temperature_c) AS temperature_hours_reported,
    COUNT(f.precipitation_mm) AS precipitation_hours_reported,

    ROUND(AVG(f.temperature_c), 2) AS avg_temperature_c,
    MIN(f.temperature_c) AS min_temperature_c,
    MAX(f.temperature_c) AS max_temperature_c,

    ROUND(SUM(f.precipitation_mm), 2) AS total_precipitation_mm,
    MAX(f.wind_speed_kmh) AS max_wind_speed_kmh

FROM hungarian_weather_lakehouse.gold.fact_hourly_weather f

JOIN hungarian_weather_lakehouse.gold.dim_location l
    ON f.location_key = l.location_key

JOIN hungarian_weather_lakehouse.gold.dim_date d
    ON f.date_key = d.date_key

JOIN hungarian_weather_lakehouse.gold.dim_weather_source w
    ON f.source_key = w.source_key

GROUP BY
    l.city_code,
    d.full_date,
    w.weather_model;




CREATE OR REFRESH MATERIALIZED VIEW
hungarian_weather_lakehouse.gold.dim_location
COMMENT 'Reference dimension for monitored Hungarian cities'
AS
SELECT *
FROM VALUES
    (101, 'budapest', 'Budapest', 47.4979, 19.0402),
    (102, 'debrecen', 'Debrecen', 47.5316, 21.6273),
    (103, 'szeged',   'Szeged',   46.2530, 20.1414),
    (104, 'pecs',     'Pécs',     46.0727, 18.2323),
    (105, 'gyor',     'Győr',     47.6875, 17.6504)
AS locations (
    location_key,
    city_code,
    city_name,
    latitude,
    longitude
);



CREATE OR REFRESH MATERIALIZED VIEW
hungarian_weather_lakehouse.gold.dim_date
COMMENT 'Calendar dimension for weather reporting'
AS
SELECT
    CAST(DATE_FORMAT(full_date, 'yyyyMMdd') AS INT)
        AS date_key,
    full_date,
    YEAR(full_date) AS year,
    QUARTER(full_date) AS quarter,
    MONTH(full_date) AS month,
    DAYOFMONTH(full_date) AS day_of_month,
    DAYOFWEEK(full_date) AS day_of_week,
    DATE_FORMAT(full_date, 'EEEE') AS weekday_name
FROM explode(
    sequence(
        DATE '2025-01-01',
        DATE '2028-12-31',
        INTERVAL 1 DAY
    )
) AS dates(full_date);


CREATE OR REFRESH MATERIALIZED VIEW
hungarian_weather_lakehouse.gold.dim_weather_source
COMMENT 'Weather data provider and model reference dimension'
AS
SELECT *
FROM VALUES
    (
        201,
        'open-meteo',
        'Open-Meteo Historical Weather API',
        'era5',
        'ERA5 Reanalysis',
        'UTC'
    )
AS sources (
    source_key,
    provider_code,
    provider_name,
    weather_model,
    model_description,
    source_timezone
);


CREATE OR REFRESH MATERIALIZED VIEW
hungarian_weather_lakehouse.gold.fact_hourly_weather
(
    CONSTRAINT valid_dimension_keys
        EXPECT (
            location_key IS NOT NULL
            AND date_key IS NOT NULL
            AND source_key IS NOT NULL
            AND monitoring_key IS NOT NULL
        )
        ON VIOLATION FAIL UPDATE
)
COMMENT 'One weather observation per location, UTC hour and model'
AS

WITH observations AS (
    SELECT
        s.*,
        date_from_unix_date(
            CAST(
                FLOOR(unix_seconds(s.hour_utc) / 86400)
                AS INT
            )
        ) AS date_utc
    FROM hungarian_weather_lakehouse.silver.weather_hourly s
)

SELECT
    l.location_key,
    d.date_key,
    w.source_key,
    m.monitoring_key,

    o.hour_utc,
    o.temperature_c,
    o.precipitation_mm,
    o.wind_speed_kmh,

    o.source_file,
    o.ingested_at_utc

FROM observations o

LEFT JOIN hungarian_weather_lakehouse.gold.dim_location l
    ON o.city = l.city_code

LEFT JOIN hungarian_weather_lakehouse.gold.dim_date d
    ON o.date_utc = d.full_date

LEFT JOIN hungarian_weather_lakehouse.gold.dim_weather_source w
    ON o.weather_model = w.weather_model

LEFT JOIN hungarian_weather_lakehouse.gold.dim_monitoring_status m
    ON o.city = m.city_code
    AND o.date_utc >= m.valid_from
    AND (
        o.date_utc < m.valid_to
        OR m.valid_to IS NULL
    );