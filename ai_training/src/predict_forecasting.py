"""Load the saved forecasting artifact and run a feature-row prediction."""

from __future__ import annotations

import argparse
from pathlib import Path

import joblib

from train_forecasting import (
    DEFAULT_DATA,
    DEFAULT_MODEL,
    build_features,
    load_hourly_energy,
)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", type=Path, default=DEFAULT_DATA)
    parser.add_argument("--model", type=Path, default=DEFAULT_MODEL)
    args = parser.parse_args()

    artifact = joblib.load(args.model)
    hourly, _ = load_hourly_energy(args.data)
    features, _ = build_features(hourly)
    latest = features[artifact["feature_columns"]].tail(1)
    prediction = float(artifact["model"].predict(latest)[0])
    print(f"Predicted next-24-hour consumption: {prediction:.3f} kWh")


if __name__ == "__main__":
    main()

