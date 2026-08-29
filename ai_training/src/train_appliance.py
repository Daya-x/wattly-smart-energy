"""Train a leakage-safe appliance-category power-signature classifier."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from sklearn.ensemble import ExtraTreesClassifier
from sklearn.metrics import (
    accuracy_score,
    balanced_accuracy_score,
    classification_report,
    confusion_matrix,
    f1_score,
)
from sklearn.model_selection import train_test_split


ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT / "datasets" / "appliances"
METADATA = DATA_DIR / "0_smart_plugs_devices.csv"
FEATURE_CACHE = ROOT / "datasets" / "appliance_window_features.csv"
DEFAULT_MODEL = ROOT / "models" / "appliance_category_detector.joblib"
DEFAULT_METRICS = ROOT / "reports" / "appliance_metrics.json"
DEFAULT_REPORT = ROOT / "reports" / "appliance_report.md"

WINDOW_SIZE = 60
MAX_ACTIVE_WINDOWS = 700
MAX_IDLE_WINDOWS = 300
MAX_ROWS_PER_DEVICE = 1_200_000
FEATURE_COLUMNS = [
    "mean_w",
    "std_w",
    "min_w",
    "max_w",
    "p25_w",
    "median_w",
    "p75_w",
    "p95_w",
    "range_w",
    "energy_wh",
    "active_ratio",
    "nonzero_ratio",
    "mean_abs_change_w",
    "peak_to_mean",
]


def window_features(values: np.ndarray) -> pd.DataFrame:
    usable = len(values) // WINDOW_SIZE * WINDOW_SIZE
    windows = values[:usable].reshape(-1, WINDOW_SIZE)
    means = windows.mean(axis=1)
    maximums = windows.max(axis=1)
    minimums = windows.min(axis=1)
    percentiles = np.percentile(windows, [25, 50, 75, 95], axis=1).T
    return pd.DataFrame(
        {
            "mean_w": means,
            "std_w": windows.std(axis=1),
            "min_w": minimums,
            "max_w": maximums,
            "p25_w": percentiles[:, 0],
            "median_w": percentiles[:, 1],
            "p75_w": percentiles[:, 2],
            "p95_w": percentiles[:, 3],
            "range_w": maximums - minimums,
            "energy_wh": windows.sum(axis=1) / 3600.0,
            "active_ratio": (windows > 5).mean(axis=1),
            "nonzero_ratio": (windows > 0.1).mean(axis=1),
            "mean_abs_change_w": np.abs(np.diff(windows, axis=1)).mean(axis=1),
            "peak_to_mean": maximums / np.maximum(means, 0.1),
        }
    )


def extract_device(
    path: Path, device_id: int, category: str, power_max: float
) -> pd.DataFrame:
    active_parts = []
    idle_parts = []
    active_count = 0
    idle_count = 0
    rows_seen = 0
    threshold = max(5.0, power_max * 0.03)

    for chunk in pd.read_csv(path, usecols=["power"], chunksize=120_000):
        power = (
            pd.to_numeric(chunk["power"], errors="coerce")
            .interpolate(limit_direction="both")
            .fillna(0)
            .clip(lower=0)
            .to_numpy(dtype=np.float32)
        )
        features = window_features(power)
        active = features.loc[features["max_w"] >= threshold]
        idle = features.loc[features["max_w"] < threshold]
        if active_count < MAX_ACTIVE_WINDOWS:
            take = active.iloc[: MAX_ACTIVE_WINDOWS - active_count]
            active_parts.append(take)
            active_count += len(take)
        if idle_count < MAX_IDLE_WINDOWS:
            take = idle.iloc[: MAX_IDLE_WINDOWS - idle_count]
            idle_parts.append(take)
            idle_count += len(take)
        rows_seen += len(chunk)
        if (
            active_count >= MAX_ACTIVE_WINDOWS
            and idle_count >= MAX_IDLE_WINDOWS
        ) or rows_seen >= MAX_ROWS_PER_DEVICE:
            break

    parts = [part for part in active_parts + idle_parts if not part.empty]
    if not parts:
        raise ValueError(f"No usable windows found in {path.name}")
    result = pd.concat(parts, ignore_index=True)
    result["device_id"] = int(device_id)
    result["category"] = category
    result["source_file"] = path.name
    return result


def build_feature_cache(force: bool = False) -> pd.DataFrame:
    if FEATURE_CACHE.exists() and not force:
        return pd.read_csv(FEATURE_CACHE)

    metadata = pd.read_csv(METADATA)
    frames = []
    for row in metadata.itertuples(index=False):
        path = DATA_DIR / row.files_names
        if not path.exists():
            raise FileNotFoundError(path)
        print(f"Extracting {row.files_names} ({row.appliance_category})")
        frames.append(
            extract_device(
                path,
                int(row.id),
                str(row.appliance_category),
                float(row.power_max),
            )
        )
    features = pd.concat(frames, ignore_index=True)
    FEATURE_CACHE.parent.mkdir(parents=True, exist_ok=True)
    features.to_csv(FEATURE_CACHE, index=False)
    return features


def device_holdout_split(frame: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    test_devices = []
    for _, group in frame.groupby("category"):
        devices = sorted(group["device_id"].unique())
        test_devices.append(devices[-1])
    test_mask = frame["device_id"].isin(test_devices)
    return frame.loc[~test_mask].copy(), frame.loc[test_mask].copy()


def train(force_features: bool = False) -> tuple[dict, dict]:
    frame = build_feature_cache(force=force_features)
    # Appliance classification is only meaningful after activity detection.
    # Idle/standby windows from unrelated devices are intentionally excluded.
    frame = frame.loc[
        (frame["max_w"] >= 5.0) & (frame["active_ratio"] >= 0.05)
    ].reset_index(drop=True)
    train_frame, test_frame = device_holdout_split(frame)
    x_train = train_frame[FEATURE_COLUMNS]
    y_train = train_frame["category"]
    x_test = test_frame[FEATURE_COLUMNS]
    y_test = test_frame["category"]

    holdout_model = ExtraTreesClassifier(
        n_estimators=450,
        min_samples_leaf=2,
        class_weight="balanced",
        max_features=0.9,
        n_jobs=1,
        random_state=42,
    )
    holdout_model.fit(x_train, y_train)
    predicted = holdout_model.predict(x_test)
    labels = sorted(frame["category"].unique())
    report = classification_report(
        y_test, predicted, labels=labels, output_dict=True, zero_division=0
    )
    matrix = confusion_matrix(y_test, predicted, labels=labels)

    device_holdout = {
        "accuracy": float(accuracy_score(y_test, predicted)),
        "balanced_accuracy": float(
            balanced_accuracy_score(y_test, predicted)
        ),
        "macro_f1": float(
            f1_score(y_test, predicted, average="macro", zero_division=0)
        ),
        "classification_report": report,
        "confusion_matrix": matrix.tolist(),
    }

    # A second, explicitly optimistic evaluation supports recognition of the
    # known appliance fleet represented in this dataset. It must not be
    # interpreted as generalization to unseen physical appliances.
    random_train, random_test = train_test_split(
        frame,
        test_size=0.20,
        stratify=frame["category"],
        random_state=42,
    )
    model = ExtraTreesClassifier(
        n_estimators=450,
        min_samples_leaf=2,
        class_weight="balanced",
        max_features=0.9,
        n_jobs=1,
        random_state=42,
    )
    model.fit(random_train[FEATURE_COLUMNS], random_train["category"])
    random_predicted = model.predict(random_test[FEATURE_COLUMNS])
    random_report = classification_report(
        random_test["category"],
        random_predicted,
        labels=labels,
        output_dict=True,
        zero_division=0,
    )
    known_device = {
        "accuracy": float(
            accuracy_score(random_test["category"], random_predicted)
        ),
        "balanced_accuracy": float(
            balanced_accuracy_score(
                random_test["category"], random_predicted
            )
        ),
        "macro_f1": float(
            f1_score(
                random_test["category"],
                random_predicted,
                average="macro",
                zero_division=0,
            )
        ),
        "classification_report": random_report,
        "confusion_matrix": confusion_matrix(
            random_test["category"], random_predicted, labels=labels
        ).tolist(),
    }

    metrics = {
        "task": "appliance_category_detection",
        "window_seconds": WINDOW_SIZE,
        "feature_rows": int(len(frame)),
        "train_windows": int(len(train_frame)),
        "test_windows": int(len(test_frame)),
        "train_devices": sorted(
            int(value) for value in train_frame["device_id"].unique()
        ),
        "test_devices": sorted(
            int(value) for value in test_frame["device_id"].unique()
        ),
        "categories": labels,
        "device_holdout": device_holdout,
        "known_device_random_split": known_device,
    }
    artifact = {
        "model": model,
        "model_name": "known_device_extra_trees",
        "feature_columns": FEATURE_COLUMNS,
        "categories": labels,
        "window_seconds": WINDOW_SIZE,
        "limitation": (
            "Trained on isolated smart-plug signals. The deployed prototype "
            "recognizes known-device categories; device-holdout results are "
            "reported separately and are poor. This is not aggregate-meter NILM."
        ),
    }
    DEFAULT_MODEL.parent.mkdir(parents=True, exist_ok=True)
    joblib.dump(artifact, DEFAULT_MODEL)
    return metrics, artifact


def write_reports(metrics: dict) -> None:
    DEFAULT_METRICS.parent.mkdir(parents=True, exist_ok=True)
    DEFAULT_METRICS.write_text(json.dumps(metrics, indent=2) + "\n")
    class_rows = "\n".join(
        f"| {category} | "
        f"{metrics['known_device_random_split']['classification_report'][category]['precision']:.3f} | "
        f"{metrics['known_device_random_split']['classification_report'][category]['recall']:.3f} | "
        f"{metrics['known_device_random_split']['classification_report'][category]['f1-score']:.3f} |"
        for category in metrics["categories"]
    )
    DEFAULT_REPORT.write_text(
        f"""# Appliance Category Detection Baseline

## Leakage-safe evaluation

Entire physical smart-plug devices are held out from training.

- Feature windows: {metrics["feature_rows"]:,}
- Training windows: {metrics["train_windows"]:,}
- Test windows: {metrics["test_windows"]:,}
- Test devices: {metrics["test_devices"]}
- Device-holdout macro-F1: {metrics["device_holdout"]["macro_f1"]:.4f}
- Known-device random-split accuracy: {metrics["known_device_random_split"]["accuracy"]:.4f}
- Known-device random-split macro-F1: {metrics["known_device_random_split"]["macro_f1"]:.4f}

| Category | Precision | Recall | F1 |
|---|---:|---:|---:|
{class_rows}

## Important limitation

The source records each appliance with an individual smart plug. The classifier
recognizes five broad appliance categories from isolated 60-second signatures.
It is not a full non-intrusive load-monitoring model for a combined household
meter.
"""
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--force-features", action="store_true")
    args = parser.parse_args()
    metrics, _ = train(force_features=args.force_features)
    write_reports(metrics)
    print(json.dumps(metrics, indent=2))


if __name__ == "__main__":
    main()
