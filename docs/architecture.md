# Hungarian Weather Lakehouse — Architecture


flowchart TB
    API["Open-Meteo Historical Weather API<br/>ERA5"]
    EXTRACT["Python API ingestion<br/>ingest_weather_job.py"]
    RAW["Unity Catalog Volume<br/>Raw JSON responses"]
    META["Unity Catalog Volume<br/>Extraction metadata"]

    BRONZE["BRONZE<br/>weather_raw<br/>Auto Loader streaming table"]
    SILVER["SILVER<br/>weather_hourly<br/>Flatten, validate, deduplicate"]

    EVENTS["Simulated monitoring change events<br/>Silver Delta table"]
    SCD["GOLD<br/>dim_monitoring_status<br/>SCD Type 2 via SQL MERGE"]

    LOCATION["dim_location"]
    DATE["dim_date"]
    SOURCE["dim_weather_source"]
    FACT["GOLD<br/>fact_hourly_weather<br/>Hourly observation grain"]

    UTC["daily_weather_summary<br/>UTC daily metrics"]
    LOCAL["daily_weather_local<br/>Hungarian-local daily metrics<br/>DST-aware completeness"]
    DASH["Databricks AI/BI Dashboard<br/>Hungarian Weather Analytics 2025"]
    VALIDATE["Automated SQL validation<br/>Integrity and reconciliation"]

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
    

## Orchestration

The pipeline is orchestrated using Databricks Lakeflow Jobs, with four sequential tasks:

API Extraction: Retrieve missing ERA5 observations from Open-Meteo and write validated JSON responses to a Unity Catalog Volume.

SCD2 Maintenance: Apply SQL MERGE to synchronize historical monitoring-status versions.

Pipeline Refresh: Execute the declarative Bronze → Silver → Gold transformations.

Data Quality Validation: Check fact uniqueness, dimension mappings, SCD2 intervals and reporting reconciliation.

The Job runs daily at 08:00 UTC, using a seven-day extraction delay and a seven-day rolling lookback window.

All pipeline source code and the Job configuration are version-controlled in GitHub.
    LOCAL -.-> VALIDATE
