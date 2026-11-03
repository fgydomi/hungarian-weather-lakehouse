
import argparse
import json
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

import requests

from extract_weather import API_URL, CITIES
from validate_weather import validate_weather


VOLUME_ROOT = Path(
    "/Volumes/hungarian_weather_lakehouse/"
    "raw/weather_landing"
)

RESPONSES = VOLUME_ROOT / "responses"
METADATA = VOLUME_ROOT / "metadata"


def main():
    parser = argparse.ArgumentParser()

    default_day = (
        datetime.now(timezone.utc).date()
        - timedelta(days=7)
    )

    parser.add_argument(
        "--date",
        default=default_day.isoformat(),
        help="UTC date to ingest, YYYY-MM-DD"
    )

    args = parser.parse_args()
    day = date.fromisoformat(args.date).isoformat()

    RESPONSES.mkdir(parents=True, exist_ok=True)

    for city, (latitude, longitude) in CITIES.items():

        # Skip a date already delivered as a daily file.
        pattern = f"{city}_{day}_{day}_*.json"

        if any(RESPONSES.glob(pattern)):
            print(f"SKIP: {city} {day} already ingested")
            continue

        params = {
            "latitude": latitude,
            "longitude": longitude,
            "start_date": day,
            "end_date": day,
            "hourly": (
                "temperature_2m,"
                "precipitation,"
                "wind_speed_10m"
            ),
            "timezone": "UTC",
            "models": "era5",
        }

        response = requests.get(
            API_URL,
            params=params,
            timeout=60
        )
        response.raise_for_status()
        data = response.json()

        # Validate before publishing to Auto Loader.
        count = validate_weather(data)

        times = data["hourly"]["time"]

        if (
            count != 24
            or times[0] != f"{day}T00:00"
            or times[-1] != f"{day}T23:00"
        ):
            raise ValueError(
                f"Invalid daily coverage: {city}, {day}"
            )

        extracted_at = datetime.now(timezone.utc)

        stamp = extracted_at.strftime(
            "%Y%m%dT%H%M%S%fZ"
        )

        filename = f"{city}_{day}_{day}_{stamp}.json"
        raw_path = RESPONSES / filename

        metadata_dir = METADATA / city
        metadata_dir.mkdir(parents=True, exist_ok=True)

        metadata = {
            "source_system": "Open-Meteo Historical Weather API",
            "source_url": API_URL,
            "city": city,
            "start_date": day,
            "end_date": day,
            "weather_model": "era5",
            "timezone": "UTC",
            "extracted_at_utc": extracted_at.isoformat(),
            "record_count": count,
            "raw_file": str(raw_path),
        }

        metadata_path = (
            metadata_dir
            / f"{raw_path.stem}.metadata.json"
        )

        # Write metadata first, then publish the
        # validated JSON response into the landing area.
        metadata_path.write_text(
            json.dumps(metadata, indent=2),
            encoding="utf-8"
        )

        try:
            raw_path.write_text(
                json.dumps(data, indent=2),
                encoding="utf-8"
            )
        except Exception:
            raw_path.unlink(missing_ok=True)
            raise

        print(f"SUCCESS: {city} {day}, {count} hours")

    print("API ingestion task completed.")


if __name__ == "__main__":
    main()