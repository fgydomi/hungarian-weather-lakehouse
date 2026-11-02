import json

from src.extract_weather import CITIES, extract_weather
from src.validate_weather import validate_weather

START_DATE = "2025-01-01"
END_DATE = "2025-12-31"

total_records = 0

for city in CITIES:
    output_path = extract_weather(
        city,
        start_date=START_DATE,
        end_date=END_DATE,
    )

    with output_path.open(encoding="utf-8") as f:
        data = json.load(f)

    record_count = validate_weather(data)

    if record_count != 8760:
        raise ValueError(
            f"{city}: expected 8760 hours, got {record_count}"
        )

    total_records += record_count
    print(f"VALIDATED: {city} - {record_count} hours")

print(f"\nTotal validated observations: {total_records}")
