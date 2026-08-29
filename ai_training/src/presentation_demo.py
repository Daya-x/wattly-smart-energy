"""Presentation demo runner for Wattly without physical ESP32 hardware.

This script is intentionally API-based: it does not edit dashboard code and it
does not write directly to Firestore/SQLite. Start FastAPI first, then run this
script to keep the dashboard populated with realistic readings during a demo.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import random
import time
from dataclasses import dataclass
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


DEVICE_ID = "EM-2048"


@dataclass(frozen=True)
class Phase:
    name: str
    seconds: int


DEMO_PHASES = (
    Phase("normal", 35),
    Phase("gas_alert", 24),
    Phase("recovery", 28),
    Phase("power_spike", 24),
    Phase("recovery", 28),
    Phase("overheat", 24),
    Phase("normal", 35),
)


def _json_request(
    method: str,
    url: str,
    payload: dict | None = None,
    headers: dict | None = None,
) -> dict:
    request_headers = {"Content-Type": "application/json"}
    request_headers.update(headers or {})
    request = Request(
        url,
        data=None if payload is None else json.dumps(payload).encode(),
        headers=request_headers,
        method=method,
    )
    with urlopen(request, timeout=6) as response:
        body = response.read()
    return {} if not body else json.loads(body)


def _phase_for_elapsed(elapsed: float) -> str:
    cursor = 0
    cycle = sum(phase.seconds for phase in DEMO_PHASES)
    position = elapsed % cycle
    for phase in DEMO_PHASES:
        cursor += phase.seconds
        if position < cursor:
            return phase.name
    return "normal"


def _reading(sequence: int, energy_kwh: float, phase: str, rng: random.Random) -> dict:
    voltage = rng.uniform(226.0, 234.0)
    current = max(0.04, 0.055 + 0.012 * math.sin(sequence / 5) + rng.uniform(-0.004, 0.004))
    temperature = 28.7 + 0.6 * math.sin(sequence / 12) + rng.uniform(-0.15, 0.15)
    gas = int(rng.uniform(410, 540))
    motion = rng.random() > 0.65

    if phase == "gas_alert":
        gas = int(rng.uniform(1100, 1450))
    elif phase == "power_spike":
        current = rng.uniform(8.0, 10.5)
    elif phase == "overheat":
        temperature = rng.uniform(42.0, 52.0)
    elif phase == "recovery":
        gas = int(rng.uniform(520, 700))
        temperature = rng.uniform(29.0, 31.5)

    power = voltage * current
    return {
        "voltage": round(voltage, 2),
        "current": round(current, 3),
        "power": round(power, 2),
        "energy": round(energy_kwh, 5),
        "temperature": round(temperature, 2),
        "humidity": round(rng.uniform(66, 78), 2),
        "gas": gas,
        "motion": motion,
        "relay": False,
    }


def _post_reading(api_url: str, device_key: str | None, reading: dict) -> dict:
    headers = {}
    if device_key:
        headers["X-Device-Key"] = device_key
    return _json_request(
        "POST",
        f"{api_url}/devices/{DEVICE_ID}/readings",
        reading,
        headers,
    )


def _post_recharge(api_url: str, amount: float) -> None:
    result = _json_request(
        "POST",
        f"{api_url}/devices/{DEVICE_ID}/account/recharge",
        {"amount_lkr": amount, "payment_method": "demo_card"},
    )
    print(
        "Recharge demo:",
        result.get("receipt_id", "accepted"),
        f"+Rs. {amount:.0f}",
    )


def _post_test_alert(api_url: str, admin_key: str, alert_type: str, severity: str) -> None:
    result = _json_request(
        "POST",
        f"{api_url}/devices/{DEVICE_ID}/alerts/test",
        {"alert_type": alert_type, "severity": severity},
        {"X-Admin-Key": admin_key},
    )
    alert = result.get("alert", {})
    print(
        "Test alert demo:",
        alert.get("title", alert_type),
        alert.get("severity", severity),
    )


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Run a no-hardware presentation demo for the Wattly dashboard."
    )
    parser.add_argument("--api-url", default="http://127.0.0.1:8000")
    parser.add_argument("--interval", type=float, default=2.0)
    parser.add_argument("--duration", type=int, default=0, help="0 runs forever")
    parser.add_argument("--seed", type=int, default=2026)
    parser.add_argument(
        "--recharge-demo",
        action="store_true",
        help="Add demo recharge receipts before streaming readings.",
    )
    parser.add_argument(
        "--test-alerts",
        action="store_true",
        help="Create one gas, voltage, and temperature test alert before streaming.",
    )
    args = parser.parse_args()

    api_url = args.api_url.rstrip("/")
    device_key = os.environ.get("DEVICE_API_KEY")
    admin_key = os.environ.get("TARIFF_ADMIN_KEY")
    rng = random.Random(args.seed)
    energy = 0.06
    sequence = 0
    started = time.monotonic()
    last_phase = ""

    print(f"Wattly presentation demo sending readings to {api_url}")
    print("Open the dashboard, AI Insights, Recharge, and Alerts pages.")
    print("Press Control+C to stop.\n")

    if args.recharge_demo:
        try:
            _post_recharge(api_url, 500)
            time.sleep(0.3)
            _post_recharge(api_url, 100)
        except (HTTPError, URLError, TimeoutError) as error:
            print(f"Recharge demo skipped: {error}")

    if args.test_alerts:
        if not admin_key:
            print("Test alerts skipped: TARIFF_ADMIN_KEY is not loaded in this terminal.")
        else:
            for alert_type, severity in (
                ("gas", "Warning"),
                ("voltage", "Warning"),
                ("temperature", "Critical"),
            ):
                try:
                    _post_test_alert(api_url, admin_key, alert_type, severity)
                    time.sleep(0.3)
                except (HTTPError, URLError, TimeoutError) as error:
                    print(f"{alert_type} test alert skipped: {error}")

    try:
        while args.duration == 0 or time.monotonic() - started < args.duration:
            elapsed = time.monotonic() - started
            phase = _phase_for_elapsed(elapsed)
            if phase != last_phase:
                print(f"\nPhase: {phase}")
                last_phase = phase

            reading = _reading(sequence, energy, phase, rng)
            energy += reading["power"] * args.interval / 3_600_000
            try:
                result = _post_reading(api_url, device_key, reading)
                print(
                    f"#{sequence + 1:03d} synced | "
                    f"{reading['voltage']:.1f} V | "
                    f"{reading['power']:.0f} W | "
                    f"{reading['temperature']:.1f} C | "
                    f"gas {reading['gas']} | "
                    f"{result.get('persistence_backend', 'memory')}"
                )
            except (HTTPError, URLError, TimeoutError) as error:
                print(f"Reading failed: {error}. Is FastAPI running?")
            sequence += 1
            time.sleep(max(args.interval, 0.2))
    except KeyboardInterrupt:
        print("\nPresentation demo stopped.")


if __name__ == "__main__":
    main()
