
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


def ingest_day(city, latitude, longitude, day):
    day_str = day.isoformat()

    pattern = f"{city}_{day_str}_{day_str}_*.json"
    existing_files = list(RESPONSES.glob(pattern))

    # Verify existing deliveries before skipping.
    if existing_files:
        for path in existing_files:
            with path.open(encoding="utf-8") as f:
                existing_data = json.load(f)

            count = validate_weather(existing_data)
            times = existing_data["hourly"]["time"]

            if (
                count != 24
                or times[0] != f"{day_str}T00:00"
                or times[-1] != f"{day_str}T23:00"
            ):
                raise ValueError(
                    f"Invalid existing delivery: {path}"
                )

        print(f"SKIP: {city} {day_str} already ingested")
        return

    params = {
        "latitude": latitude,
        "longitude": longitude,
        "start_date": day_str,
        "end_date": day_str,
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
    count = validate_weather(data)
    times = data["hourly"]["time"]

    if (
        count != 24
        or times[0] != f"{day_str}T00:00"
        or times[-1] != f"{day_str}T23:00"
    ):
        raise ValueError(
            f"Invalid API coverage: {city} {day_str}"
        )

    extracted_at = datetime.now(timezone.utc)
    stamp = extracted_at.strftime("%Y%m%dT%H%M%S%fZ")

    filename = f"{city}_{day_str}_{day_str}_{stamp}.json"
    raw_path = RESPONSES / filename

    metadata_dir = METADATA / city
    metadata_dir.mkdir(parents=True, exist_ok=True)

    metadata_path = (
        metadata_dir / f"{raw_path.stem}.metadata.json"
    )

    metadata = {
        "source_system": "Open-Meteo Historical Weather API",
        "source_url": API_URL,
        "city": city,
        "start_date": day_str,
        "end_date": day_str,
        "weather_model": "era5",
        "timezone": "UTC",
        "extracted_at_utc": extracted_at.isoformat(),
        "record_count": count,
        "raw_file": str(raw_path),
    }

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

    print(f"SUCCESS: {city} {day_str}, {count} hours")


def main():
    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--date",
        default=None,
        help="Optional single UTC date, YYYY-MM-DD"
    )

    parser.add_argument(
        "--lookback-days",
        type=int,
        default=7
    )

    parser.add_argument(
        "--delay-days",
        type=int,
        default=7
    )

    args = parser.parse_args()

    if args.lookback_days < 1 or args.delay_days < 1:
        parser.error("Days must be positive integers")

    if args.date:
        # Manual backfill or idempotency test.
        target_dates = [date.fromisoformat(args.date)]
    else:
        # Latest safe historical date.
        newest = (
            datetime.now(timezone.utc).date()
            - timedelta(days=args.delay_days)
        )

        # Process oldest to newest.
        target_dates = [
            newest - timedelta(days=offset)
            for offset in range(
                args.lookback_days - 1,
                -1,
                -1
            )
        ]

    RESPONSES.mkdir(parents=True, exist_ok=True)

    for target_date in target_dates:
        for city, (latitude, longitude) in CITIES.items():
            ingest_day(
                city,
                latitude,
                longitude,
                target_date
            )

    print("API ingestion task completed.")


if __name__ == "__main__":
    main()