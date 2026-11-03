import json

from extract_weather import extract_weather
from validate_weather import validate_weather

VOLUME_ROOT = (
    "/Volumes/hungarian_weather_lakehouse/"
    "raw/weather_landing"
)

# Re-extract an existing day to test direct ingestion.
output_path = extract_weather(
    city="budapest",
    start_date="2025-07-01",
    end_date="2025-07-01",
    output_root=VOLUME_ROOT,
)

# Validate the saved response.
with output_path.open(encoding="utf-8") as f:
    data = json.load(f)

record_count = validate_weather(data)

assert record_count == 24, (
    f"Expected 24 hourly observations, got {record_count}"
)

print("Volume ingestion test successful!")
print("Validated hourly records:", record_count)
print("Raw file:", output_path)