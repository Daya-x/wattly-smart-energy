"""Train smoke/fire, electrical-fault, and gas-identity safety models."""

from __future__ import annotations

import json
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from sklearn.datasets import load_svmlight_file
from sklearn.ensemble import ExtraTreesClassifier
from sklearn.metrics import (
    accuracy_score,
    balanced_accuracy_score,
    classification_report,
    confusion_matrix,
    f1_score,
    precision_score,
    recall_score,
    roc_auc_score,
)
from sklearn.model_selection import StratifiedGroupKFold, train_test_split


ROOT = Path(__file__).resolve().parents[1]
SAFETY_DIR = ROOT / "datasets" / "safety"
MODELS_DIR = ROOT / "models"
REPORTS_DIR = ROOT / "reports"

SMOKE_DATA = SAFETY_DIR / "smoke_detection_iot.csv"
ELECTRICAL_DATA = SAFETY_DIR / "power_quality_fault_dataset.csv"
SMOKE_MODEL = MODELS_DIR / "smoke_fire_detector.joblib"
ELECTRICAL_MODEL = MODELS_DIR / "electrical_fault_detector.joblib"
GAS_MODEL = MODELS_DIR / "gas_identity_detector.joblib"
METRICS_PATH = REPORTS_DIR / "safety_metrics.json"
REPORT_PATH = REPORTS_DIR / "safety_report.md"

SMOKE_FEATURES = [
    "Temperature[C]",
    "Humidity[%]",
    "TVOC[ppb]",
    "eCO2[ppm]",
    "Raw H2",
    "Raw Ethanol",
    "Pressure[hPa]",
    "PM1.0",
    "PM2.5",
    "NC0.5",
    "NC1.0",
    "NC2.5",
]
ELECTRICAL_NUMERIC = [
    "RMS_Voltage",
    "Peak_Voltage",
    "THD",
    "Duration_ms",
    "DWT_Energy_Level1",
    "DWT_Energy_Level2",
    "DWT_Entropy",
    "Signal_Noise_Ratio_dB",
]
GAS_NAMES = {
    1: "Ethanol",
    2: "Ethylene",
    3: "Ammonia",
    4: "Acetaldehyde",
    5: "Acetone",
    6: "Toluene",
}


def classifier() -> ExtraTreesClassifier:
    return ExtraTreesClassifier(
        n_estimators=350,
        min_samples_leaf=2,
        class_weight="balanced",
        max_features=0.8,
        n_jobs=1,
        random_state=42,
    )


def train_smoke() -> tuple[dict, dict, pd.DataFrame]:
    frame = pd.read_csv(SMOKE_DATA)
    x = frame[SMOKE_FEATURES].apply(pd.to_numeric, errors="coerce")
    x = x.interpolate(limit_direction="both")
    y = frame["Fire Alarm"].astype(int)
    groups = np.arange(len(frame)) // 60

    splitter = StratifiedGroupKFold(
        n_splits=5, shuffle=True, random_state=42
    )
    train_index, test_index = next(splitter.split(x, y, groups))
    model = classifier()
    model.fit(x.iloc[train_index], y.iloc[train_index])
    predicted = model.predict(x.iloc[test_index])
    probabilities = model.predict_proba(x.iloc[test_index])[:, 1]

    metrics = {
        "rows": int(len(frame)),
        "train_rows": int(len(train_index)),
        "test_rows": int(len(test_index)),
        "precision_fire": float(
            precision_score(y.iloc[test_index], predicted)
        ),
        "recall_fire": float(recall_score(y.iloc[test_index], predicted)),
        "f1_fire": float(f1_score(y.iloc[test_index], predicted)),
        "balanced_accuracy": float(
            balanced_accuracy_score(y.iloc[test_index], predicted)
        ),
        "roc_auc": float(roc_auc_score(y.iloc[test_index], probabilities)),
        "confusion_matrix": confusion_matrix(
            y.iloc[test_index], predicted
        ).tolist(),
    }
    artifact = {
        "model": model,
        "model_name": "block_holdout_extra_trees",
        "feature_columns": SMOKE_FEATURES,
        "positive_label": "Fire",
        "limitation": (
            "Trained on a public IoT smoke-sensor fusion dataset. Sensor "
            "calibration differs from the project hardware."
        ),
    }
    joblib.dump(artifact, SMOKE_MODEL)
    return metrics, artifact, x.tail(1)


def electrical_features(frame: pd.DataFrame) -> pd.DataFrame:
    numeric = frame[ELECTRICAL_NUMERIC].apply(pd.to_numeric, errors="coerce")
    phase = pd.get_dummies(frame["Phase"], prefix="phase", dtype=float)
    return pd.concat([numeric, phase], axis=1)


def train_electrical() -> tuple[dict, dict, pd.DataFrame]:
    frame = pd.read_csv(ELECTRICAL_DATA)
    x = electrical_features(frame)
    y = frame["Fault_Type"].astype(str)
    x_train, x_test, y_train, y_test = train_test_split(
        x, y, test_size=0.20, stratify=y, random_state=42
    )
    model = classifier()
    model.fit(x_train, y_train)
    predicted = model.predict(x_test)
    labels = sorted(y.unique())
    report = classification_report(
        y_test, predicted, labels=labels, output_dict=True, zero_division=0
    )
    metrics = {
        "rows": int(len(frame)),
        "accuracy": float(accuracy_score(y_test, predicted)),
        "balanced_accuracy": float(
            balanced_accuracy_score(y_test, predicted)
        ),
        "macro_f1": float(
            f1_score(y_test, predicted, average="macro")
        ),
        "classification_report": report,
        "confusion_matrix": confusion_matrix(
            y_test, predicted, labels=labels
        ).tolist(),
    }
    artifact = {
        "model": model,
        "model_name": "stratified_extra_trees",
        "feature_columns": list(x.columns),
        "classes": labels,
        "limitation": (
            "This dataset represents distribution-system power-quality "
            "signals, not a domestic prepaid meter."
        ),
    }
    joblib.dump(artifact, ELECTRICAL_MODEL)
    return metrics, artifact, x.tail(1)


def load_gas_batches(numbers: list[int]) -> tuple[np.ndarray, np.ndarray]:
    matrices = []
    labels = []
    for number in numbers:
        matrix, target = load_svmlight_file(
            SAFETY_DIR / f"batch{number}.dat", n_features=128
        )
        matrices.append(matrix.toarray())
        labels.append(target.astype(int))
    return np.vstack(matrices), np.concatenate(labels)


def train_gas() -> tuple[dict, dict, np.ndarray]:
    x_train, y_train = load_gas_batches(list(range(1, 10)))
    x_test, y_test = load_gas_batches([10])
    model = classifier()
    model.fit(x_train, y_train)
    predicted = model.predict(x_test)
    labels = sorted(GAS_NAMES)
    report = classification_report(
        y_test, predicted, labels=labels, output_dict=True, zero_division=0
    )
    metrics = {
        "train_rows": int(len(x_train)),
        "test_rows": int(len(x_test)),
        "test_batch": 10,
        "accuracy": float(accuracy_score(y_test, predicted)),
        "balanced_accuracy": float(
            balanced_accuracy_score(y_test, predicted)
        ),
        "macro_f1": float(
            f1_score(y_test, predicted, average="macro")
        ),
        "classification_report": report,
        "confusion_matrix": confusion_matrix(
            y_test, predicted, labels=labels
        ).tolist(),
    }
    artifact = {
        "model": model,
        "model_name": "batch_drift_extra_trees",
        "feature_count": 128,
        "gas_names": GAS_NAMES,
        "limitation": (
            "All samples contain one of six gases. There is no clean-air "
            "class or leak-risk target, so this model identifies gas only."
        ),
    }
    joblib.dump(artifact, GAS_MODEL)
    return metrics, artifact, x_test[-1:]


def main() -> None:
    MODELS_DIR.mkdir(parents=True, exist_ok=True)
    REPORTS_DIR.mkdir(parents=True, exist_ok=True)
    smoke, _, _ = train_smoke()
    electrical, _, _ = train_electrical()
    gas, _, _ = train_gas()
    metrics = {
        "smoke_fire": smoke,
        "electrical_fault": electrical,
        "gas_identity": gas,
    }
    METRICS_PATH.write_text(json.dumps(metrics, indent=2) + "\n")
    REPORT_PATH.write_text(
        f"""# Safety Model Baselines

## Smoke/fire detection

- Fire precision: {smoke["precision_fire"]:.4f}
- Fire recall: {smoke["recall_fire"]:.4f}
- Fire F1: {smoke["f1_fire"]:.4f}
- ROC-AUC: {smoke["roc_auc"]:.4f}

## Electrical power-quality classification

- Accuracy: {electrical["accuracy"]:.4f}
- Macro-F1: {electrical["macro_f1"]:.4f}

## Gas identity under sensor drift

- Test batch: 10
- Accuracy: {gas["accuracy"]:.4f}
- Macro-F1: {gas["macro_f1"]:.4f}

## Safety boundary

These public datasets use sensors and electrical systems different from the
project hardware. The smoke model predicts its dataset's fire-alarm label, the
electrical model classifies power-quality conditions, and the gas model
identifies one of six gases. The gas data has no clean-air class and therefore
cannot produce a calibrated leak probability.
"""
    )
    print(json.dumps(metrics, indent=2))


if __name__ == "__main__":
    main()

