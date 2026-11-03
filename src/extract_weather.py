
import json
from pathlib import Path
from datetime import datetime, timezone

import requests

API_URL = "https://archive-api.open-meteo.com/v1/archive"

CITIES = {
    "budapest": (47.4979, 19.0402),
    "debrecen": (47.5316, 21.6273),
    "szeged": (46.2530, 20.1414),
    "pecs": (46.0727, 18.2323),
    "gyor": (47.6875, 17.6504),
}


def extract_weather(
    city,
    start_date,
    end_date,
    output_root=None,
):
    latitude, longitude = CITIES[city]

    params = {
        "latitude": latitude,
        "longitude": longitude,
        "start_date": start_date,
        "end_date": end_date,
        "hourly": "temperature_2m,precipitation,wind_speed_10m",
        "timezone": "UTC",
        "models": "era5",
    }

    response = requests.get(API_URL, params=params, timeout=30)
    response.raise_for_status()
    data = response.json()

    # Validate the parallel arrays
    hourly = data["hourly"]
    lengths = [len(values) for values in hourly.values()]

    if len(set(lengths)) != 1:
        raise ValueError(f"Inconsistent hourly arrays for {city}")

    # Use a unique filename for each extraction
    extracted_at = datetime.now(timezone.utc).strftime(
        "%Y%m%dT%H%M%S%fZ"
    )

    if output_root is None:
        output_dir = Path("data/raw") / city
        metadata_dir = Path("data/metadata") / city
    else:
        root = Path(output_root)
        output_dir = root / "responses"
        metadata_dir = root / "metadata" / city

    output_dir.mkdir(parents=True, exist_ok=True)

    filename = (
        f"{city}_{start_date}_{end_date}_{extracted_at}.json"
    )
    output_path = output_dir / filename

    with output_path.open("w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)

    # Store extraction metadata separately from the raw API response
    metadata = {
        "source_system": "Open-Meteo Historical Weather API",
        "source_url": API_URL,
        "city": city,
        "latitude": latitude,
        "longitude": longitude,
        "start_date": start_date,
        "end_date": end_date,
        "weather_model": params["models"],
        "timezone": params["timezone"],
        "extracted_at_utc": datetime.now(timezone.utc).isoformat(),
        "record_count": len(hourly["time"]),
        "raw_file": output_path.as_posix(),
    }

    metadata_dir.mkdir(parents=True, exist_ok=True)

    metadata_path = metadata_dir / f"{output_path.stem}.metadata.json"

    with metadata_path.open("w", encoding="utf-8") as f:
        json.dump(metadata, f, indent=2)

    print(f"{city}: {len(hourly['time'])} records saved")

    return output_path


if __name__ == "__main__":
    for city in CITIES:
        extract_weather(
            city,
            start_date="2025-01-01",
            end_date="2025-01-03",
        )
