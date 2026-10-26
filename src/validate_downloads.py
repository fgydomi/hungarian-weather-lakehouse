
import json
from pathlib import Path

from validate_weather import validate_weather

files = sorted(Path("data/raw").glob("*/*.json"))

if not files:
    raise RuntimeError("No raw weather files found")

for path in files:
    with path.open(encoding="utf-8") as f:
        data = json.load(f)

    count = validate_weather(data)
    print(f"PASS: {path.name} ({count} hours)")
