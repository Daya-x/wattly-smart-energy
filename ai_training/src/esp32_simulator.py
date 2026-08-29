"""Local ESP32 simulator for the Wattly dashboard."""

from __future__ import annotations

import argparse
import json
import math
import os
import random
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


def generate_reading(
    sequence: int,
    energy_kwh: float,
    scenario: str = "normal",
    rng: random.Random | None = None,
) -> dict:
    randomizer = rng or random
    voltage = randomizer.uniform(226, 234)
    current = max(0.05, 1.25 + 0.55 * math.sin(sequence / 8) + randomizer.uniform(-0.08, 0.08))
    temperature = 30.5 + 1.2 * math.sin(sequence / 20) + randomizer.uniform(-0.2, 0.2)
    gas = int(randomizer.uniform(380, 470))
    if scenario == "power_spike" and sequence % 15 in range(8, 12):
        current += 8
    elif scenario == "gas_alert" and sequence % 15 in range(8, 12):
        gas = int(randomizer.uniform(1800, 2300))
    elif scenario == "overheat" and sequence % 15 in range(8, 12):
        temperature = randomizer.uniform(55, 65)
    power = voltage * current
    return {
        "voltage": round(voltage, 2),
        "current": round(current, 3),
        "power": round(power, 2),
        "energy": round(energy_kwh, 5),
        "temperature": round(temperature, 2),
        "humidity": round(randomizer.uniform(66, 76), 2),
        "gas": gas,
        "motion": randomizer.random() > 0.35,
        "relay": True,
    }


def send_reading(url: str, reading: dict, device_key: str | None = None) -> dict:
    headers = {"Content-Type": "application/json"}
    if device_key:
        headers["X-Device-Key"] = device_key
    request = Request(
        url,
        data=json.dumps(reading).encode(),
        headers=headers,
        method="POST",
    )
    with urlopen(request, timeout=5) as response:
        return json.loads(response.read())


def main() -> None:
    parser = argparse.ArgumentParser(description="Send fake ESP32 readings")
    parser.add_argument("--api-url", default="http://127.0.0.1:8000")
    parser.add_argument(
        "--scenario",
        choices=("normal", "power_spike", "gas_alert", "overheat"),
        default="normal",
    )
    parser.add_argument("--interval", type=float, default=2)
    parser.add_argument("--count", type=int, default=0, help="0 sends forever")
    args = parser.parse_args()
    endpoint = f"{args.api_url.rstrip('/')}/devices/EM-2048/readings"
    device_key = os.environ.get("DEVICE_API_KEY")
    energy = 4.8
    sequence = 0
    print(f"ESP32 simulator sending {args.scenario} readings to {endpoint}")
    print("Press Control+C to stop.")
    try:
        while args.count == 0 or sequence < args.count:
            reading = generate_reading(sequence, energy, args.scenario)
            energy += reading["power"] * args.interval / 3_600_000
            try:
                result = send_reading(endpoint, reading, device_key)
                print(
                    f"#{sequence + 1} accepted {result['received_at']} | "
                    f"{reading['voltage']:.1f} V | {reading['power']:.0f} W | "
                    f"gas {reading['gas']}"
                )
            except (HTTPError, URLError, TimeoutError) as error:
                print(f"Send failed: {error}. Is the Uvicorn API running?")
            sequence += 1
            if args.count == 0 or sequence < args.count:
                time.sleep(max(args.interval, 0.1))
    except KeyboardInterrupt:
        print("\nSimulator stopped.")


if __name__ == "__main__":
    main()
