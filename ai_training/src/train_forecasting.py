"""Train a 24-hour household energy-consumption forecasting baseline."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from sklearn.ensemble import (
    ExtraTreesRegressor,
    HistGradientBoostingRegressor,
    RandomForestRegressor,
)
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DATA = (
    ROOT / "datasets" / "forecasting" / "household_power_consumption - Copy.csv"
)
DEFAULT_MODEL = ROOT / "models" / "energy_forecast_24h.joblib"
DEFAULT_METRICS = ROOT / "reports" / "energy_forecast_metrics.json"
DEFAULT_REPORT = ROOT / "reports" / "energy_forecast_report.md"

LAGS = (1, 2, 3, 6, 12, 24, 48, 168)
ROLLING_WINDOWS = (6, 12, 24, 168)


def load_hourly_energy(path: Path) -> tuple[pd.DataFrame, dict[str, int]]:
    raw = pd.read_csv(path)
    required = {
        "time",
        "global_active_power",
        "voltage",
        "global_intensity",
    }
    missing = required.difference(raw.columns)
    if missing:
        raise ValueError(f"Missing required columns: {sorted(missing)}")

    numeric_columns = [column for column in raw.columns if column != "time"]
    raw[numeric_columns] = raw[numeric_columns].apply(
        pd.to_numeric, errors="coerce"
    )
    missing_values = int(raw[numeric_columns].isna().sum().sum())
    raw[numeric_columns] = raw[numeric_columns].interpolate(
        limit_direction="both"
    )

    # The source file omits the date. Row order and the supplied minute clock
    # are preserved, while an artificial continuous index supports resampling.
    raw["sequence_hour"] = np.arange(len(raw)) // 60
    hourly = raw.groupby("sequence_hour", as_index=False).agg(
        energy_kwh=("global_active_power", lambda values: values.sum() / 60.0),
        mean_power_kw=("global_active_power", "mean"),
        max_power_kw=("global_active_power", "max"),
        mean_voltage=("voltage", "mean"),
        mean_current=("global_intensity", "mean"),
        samples=("global_active_power", "size"),
    )
    hourly = hourly.loc[hourly["samples"] == 60].drop(columns="samples")

    first_hour = int(str(raw["time"].iloc[0]).split(":")[0])
    clock_hour = (hourly["sequence_hour"] + first_hour) % 24
    hourly["hour_sin"] = np.sin(2 * np.pi * clock_hour / 24)
    hourly["hour_cos"] = np.cos(2 * np.pi * clock_hour / 24)

    quality = {
        "raw_rows": int(len(raw)),
        "complete_hourly_rows": int(len(hourly)),
        "imputed_numeric_values": missing_values,
    }
    return hourly, quality


def build_features(hourly: pd.DataFrame) -> tuple[pd.DataFrame, pd.Series]:
    frame = hourly.copy()
    energy = frame["energy_kwh"]

    for lag in LAGS:
        frame[f"energy_lag_{lag}h"] = energy.shift(lag)
    for window in ROLLING_WINDOWS:
        history = energy.shift(1).rolling(window)
        frame[f"energy_mean_{window}h"] = history.mean()
        frame[f"energy_std_{window}h"] = history.std()

    # Prediction target: total energy consumed during hours t+1 through t+24.
    future_hours = [energy.shift(-offset) for offset in range(1, 25)]
    frame["target_next_24h_kwh"] = pd.concat(future_hours, axis=1).sum(
        axis=1, min_count=24
    )
    frame = frame.dropna().reset_index(drop=True)

    excluded = {"target_next_24h_kwh", "sequence_hour"}
    feature_columns = [
        column for column in frame.columns if column not in excluded
    ]
    return frame[feature_columns], frame["target_next_24h_kwh"]


def chronological_split(
    features: pd.DataFrame, target: pd.Series
) -> tuple:
    train_end = int(len(features) * 0.70)
    validation_end = int(len(features) * 0.85)
    return (
        features.iloc[:train_end],
        target.iloc[:train_end],
        features.iloc[train_end:validation_end],
        target.iloc[train_end:validation_end],
        features.iloc[validation_end:],
        target.iloc[validation_end:],
    )


def evaluate(actual: pd.Series, predicted: np.ndarray) -> dict[str, float]:
    return {
        "mae_kwh": float(mean_absolute_error(actual, predicted)),
        "rmse_kwh": float(math.sqrt(mean_squared_error(actual, predicted))),
        "r2": float(r2_score(actual, predicted)),
    }


def train(data_path: Path, model_path: Path) -> tuple[dict, dict]:
    hourly, quality = load_hourly_energy(data_path)
    features, target = build_features(hourly)
    (
        x_train,
        y_train,
        x_validation,
        y_validation,
        x_test,
        y_test,
    ) = chronological_split(features, target)

    candidates = {
        "histogram_gradient_boosting": HistGradientBoostingRegressor(
            learning_rate=0.04,
            max_iter=400,
            max_leaf_nodes=20,
            l2_regularization=0.5,
            random_state=42,
        ),
        "random_forest": RandomForestRegressor(
            n_estimators=300,
            max_features=0.8,
            min_samples_leaf=3,
            n_jobs=1,
            random_state=42,
        ),
        "extra_trees": ExtraTreesRegressor(
            n_estimators=300,
            max_features=0.8,
            min_samples_leaf=3,
            n_jobs=1,
            random_state=42,
        ),
    }
    candidate_validation = {}
    trained_candidates = {}
    for name, candidate in candidates.items():
        candidate.fit(x_train, y_train)
        trained_candidates[name] = candidate
        candidate_validation[name] = evaluate(
            y_validation, candidate.predict(x_validation)
        )

    selected_name = min(
        candidate_validation,
        key=lambda name: candidate_validation[name]["mae_kwh"],
    )
    model = trained_candidates[selected_name]

    validation_predictions = model.predict(x_validation)
    test_predictions = model.predict(x_test)

    # A strong simple baseline: tomorrow resembles the previous 24 hours.
    baseline_validation = x_validation["energy_mean_24h"] * 24
    baseline_test = x_test["energy_mean_24h"] * 24

    metrics = {
        "task": "next_24_hours_total_energy",
        "units": "kWh",
        "quality": quality,
        "samples": {
            "feature_rows": int(len(features)),
            "train": int(len(x_train)),
            "validation": int(len(x_validation)),
            "test": int(len(x_test)),
        },
        "selected_model": selected_name,
        "candidate_validation": candidate_validation,
        "validation": evaluate(y_validation, validation_predictions),
        "test": evaluate(y_test, test_predictions),
        "naive_baseline_validation": evaluate(
            y_validation, baseline_validation.to_numpy()
        ),
        "naive_baseline_test": evaluate(y_test, baseline_test.to_numpy()),
    }

    artifact = {
        "model": model,
        "model_name": selected_name,
        "feature_columns": list(features.columns),
        "lags_hours": list(LAGS),
        "rolling_windows_hours": list(ROLLING_WINDOWS),
        "forecast_horizon_hours": 24,
        "input_units": {"global_active_power": "kW"},
        "output_units": "kWh",
        "data_limitation": (
            "The source contains time-of-day but no calendar date. "
            "Calendar and seasonal features are intentionally excluded."
        ),
    }
    model_path.parent.mkdir(parents=True, exist_ok=True)
    joblib.dump(artifact, model_path)
    return metrics, artifact


def write_reports(metrics: dict, metrics_path: Path, report_path: Path) -> None:
    metrics_path.parent.mkdir(parents=True, exist_ok=True)
    metrics_path.write_text(json.dumps(metrics, indent=2) + "\n")

    test = metrics["test"]
    baseline = metrics["naive_baseline_test"]
    improvement = (
        (baseline["mae_kwh"] - test["mae_kwh"])
        / baseline["mae_kwh"]
        * 100
    )
    report = f"""# 24-Hour Energy Forecast Baseline

## Dataset

- Raw minute readings: {metrics["quality"]["raw_rows"]:,}
- Complete hourly periods: {metrics["quality"]["complete_hourly_rows"]:,}
- Imputed numeric values: {metrics["quality"]["imputed_numeric_values"]:,}
- Training samples: {metrics["samples"]["train"]:,}
- Validation samples: {metrics["samples"]["validation"]:,}
- Test samples: {metrics["samples"]["test"]:,}

## Test results

Selected model: **{metrics["selected_model"]}**

| Model | MAE (kWh) | RMSE (kWh) | R² |
|---|---:|---:|---:|
| Selected model | {test["mae_kwh"]:.4f} | {test["rmse_kwh"]:.4f} | {test["r2"]:.4f} |
| Previous-24-hour baseline | {baseline["mae_kwh"]:.4f} | {baseline["rmse_kwh"]:.4f} | {baseline["r2"]:.4f} |

Model MAE improvement over the naive baseline: **{improvement:.2f}%**.

## Important limitation

The supplied forecasting CSV contains time-of-day but no calendar date. The
pipeline therefore preserves sequential order but deliberately excludes
weekday, holiday, and seasonal features. This model is suitable for a project
prototype, not billing or safety-critical decisions.
"""
    report_path.write_text(report)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", type=Path, default=DEFAULT_DATA)
    parser.add_argument("--model", type=Path, default=DEFAULT_MODEL)
    parser.add_argument("--metrics", type=Path, default=DEFAULT_METRICS)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    metrics, _ = train(args.data, args.model)
    write_reports(metrics, args.metrics, args.report)
    print(json.dumps(metrics, indent=2))


if __name__ == "__main__":
    main()
