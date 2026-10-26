
import json
from pathlib import Path

path = Path(
    "data/raw/budapest_2025-01-01_2025-01-03.json"
)

with path.open(encoding="utf-8") as f:
    data = json.load(f)

hourly = data["hourly"]

columns = [
    "time",
    "temperature_2m",
    "precipitation",
    "wind_speed_10m",
]

lengths = {col: len(hourly[col]) for col in columns}

print("Array lengths:", lengths)

assert len(set(lengths.values())) == 1, (
    "Weather arrays have different lengths!"
)

# Create a preview of the first three hourly observations.
for i in range(3):
    print({
        "time_utc": hourly["time"][i],
        "temperature_c": hourly["temperature_2m"][i],
        "precipitation_mm": hourly["precipitation"][i],
        "wind_speed_kmh": hourly["wind_speed_10m"][i],
    })
