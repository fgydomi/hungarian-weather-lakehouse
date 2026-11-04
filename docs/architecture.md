
# Hungarian Weather Lakehouse — Architecture

```mermaid
flowchart TB
    API["Open-Meteo Historical Weather API - ERA5"]
    EXTRACT["Python API ingestion - ingest_weather_job.py"]
    RAW["Unity Catalog Volume - Raw JSON responses"]
    META["Unity Catalog Volume - Extraction metadata"]

    BRONZE["BRONZE - weather_raw - Auto Loader"]
    SILVER["SILVER - weather_hourly - Clean and deduplicate"]

    EVENTS["Simulated monitoring change events"]
    SCD["GOLD - dim_monitoring_status - SCD Type 2"]

    LOCATION["dim_location"]
    DATE["dim_date"]
    SOURCE["dim_weather_source"]

    FACT["GOLD - fact_hourly_weather"]

    UTC["daily_weather_summary - UTC metrics"]
    LOCAL["daily_weather_local - Local time and DST"]
    DASH["Databricks AI/BI Dashboard"]
    VALIDATE["Automated SQL data quality checks"]

    API --> EXTRACT
    EXTRACT --> RAW
    EXTRACT -.-> META

    RAW --> BRONZE
    BRONZE --> SILVER
    SILVER --> FACT

    EVENTS --> SCD
    SCD --> FACT

    LOCATION --> FACT
    DATE --> FACT
    SOURCE --> FACT

    FACT --> UTC
    FACT --> LOCAL
    LOCAL --> DASH

    FACT -.-> VALIDATE
    SCD -.-> VALIDATE
    UTC -.-> VALIDATE
    LOCAL -.-> VALIDATE
```

## Orchestration

The pipeline is orchestrated using Databricks Lakeflow Jobs, with four sequential tasks:

1. **API Extraction:** Retrieve missing ERA5 observations from Open-Meteo and write validated JSON responses to a Unity Catalog Volume.
2. **SCD2 Maintenance:** Apply SQL MERGE to synchronize historical monitoring-status versions.
3. **Pipeline Refresh:** Execute the declarative Bronze → Silver → Gold transformations.
4. **Data Quality Validation:** Check fact uniqueness, dimension mappings, SCD2 intervals, and reporting reconciliation.

The Job runs daily at **08:00 UTC**, using a seven-day extraction delay and a seven-day rolling lookback window.

All pipeline source code and the Job configuration are version-controlled in GitHub.
