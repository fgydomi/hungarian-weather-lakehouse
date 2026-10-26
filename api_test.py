
import requests
import json
from pathlib import Path

url = "https://archive-api.open-meteo.com/v1/archive"

params = {
    "latitude": 47.4979,
    "longitude": 19.0402,
    "start_date": "2025-01-01",
    "end_date": "2025-01-03",
    "hourly": "temperature_2m,precipitation,wind_speed_10m",
    "timezone": "UTC",
    "models": "era5"
}

response = requests.get(url, params=params, timeout=30)
response.raise_for_status()

data = response.json()

print("Hourly records:", len(data["hourly"]["time"]))
print("Weather variables:", list(data["hourly"].keys()))
print("First temperature:", data["hourly"]["temperature_2m"][0])

output = Path("data/raw/budapest_2025-01-01_2025-01-03.json")
output.parent.mkdir(parents=True, exist_ok=True)

with output.open("w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)

print("Saved:", output)
