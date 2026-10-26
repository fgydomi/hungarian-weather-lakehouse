
from datetime import datetime, timedelta

REQUIRED_FIELDS = [
    "time",
    "temperature_2m",
    "precipitation",
    "wind_speed_10m",
]


def validate_weather(data):
    if "hourly" not in data:
        raise ValueError("Missing hourly section")

    hourly = data["hourly"]

    for field in REQUIRED_FIELDS:
        if field not in hourly:
            raise ValueError(f"Missing field: {field}")

    lengths = [len(hourly[field]) for field in REQUIRED_FIELDS]

    if len(set(lengths)) != 1 or lengths[0] == 0:
        raise ValueError("Invalid or inconsistent array lengths")

    timestamps = [
        datetime.fromisoformat(t) for t in hourly["time"]
    ]

    for previous, current in zip(timestamps, timestamps[1:]):
        if current - previous != timedelta(hours=1):
            raise ValueError(
                "Duplicate, missing or unordered hourly timestamp"
            )

    return len(timestamps)
