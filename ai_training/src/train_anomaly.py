"""Train the abnormal household electricity-usage classifier."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import joblib
import pandas as pd
from sklearn.ensemble import ExtraTreesClassifier, RandomForestClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import (
    balanced_accuracy_score,
    confusion_matrix,
    f1_score,
    precision_score,
    recall_score,
    roc_auc_score,
)
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DATA = ROOT / "datasets" / "anomalies" / "smart_meter_data.csv"
DEFAULT_MODEL = ROOT / "models" / "anomaly_detector.joblib"
DEFAULT_METRICS = ROOT / "reports" / "anomaly_metrics.json"
DEFAULT_REPORT = ROOT / "reports" / "anomaly_report.md"

FEATURE_COLUMNS = [
    "Electricity_Consumed",
    "Temperature",
    "Humidity",
    "Wind_Speed",
    "Avg_Past_Consumption",
]


def load_data(path: Path) -> tuple[pd.DataFrame, pd.Series, dict]:
    raw = pd.read_csv(path)
    required = set(FEATURE_COLUMNS) | {"Timestamp", "Anomaly_Label"}
    missing = required.difference(raw.columns)
    if missing:
        raise ValueError(f"Missing required columns: {sorted(missing)}")

    frame = raw.copy()
    frame["Timestamp"] = pd.to_datetime(frame["Timestamp"], errors="raise")
    frame = frame.sort_values("Timestamp").reset_index(drop=True)
    frame[FEATURE_COLUMNS] = frame[FEATURE_COLUMNS].apply(
        pd.to_numeric, errors="coerce"
    )
    missing_values = int(frame[FEATURE_COLUMNS].isna().sum().sum())
    if missing_values:
        frame[FEATURE_COLUMNS] = frame[FEATURE_COLUMNS].interpolate(
            limit_direction="both"
        )
    labels = frame["Anomaly_Label"].str.strip().map(
        {"Normal": 0, "Abnormal": 1}
    )
    if labels.isna().any():
        raise ValueError("Unexpected anomaly label found")

    quality = {
        "rows": int(len(frame)),
        "normal": int((labels == 0).sum()),
        "abnormal": int((labels == 1).sum()),
        "imputed_values": missing_values,
    }
    return frame[FEATURE_COLUMNS], labels.astype(int), quality


def split(features: pd.DataFrame, labels: pd.Series) -> tuple:
    train_end = int(len(features) * 0.70)
    validation_end = int(len(features) * 0.85)
    return (
        features.iloc[:train_end],
        labels.iloc[:train_end],
        features.iloc[train_end:validation_end],
        labels.iloc[train_end:validation_end],
        features.iloc[validation_end:],
        labels.iloc[validation_end:],
    )


def evaluate(actual: pd.Series, predicted, probabilities) -> dict:
    matrix = confusion_matrix(actual, predicted, labels=[0, 1])
    return {
        "precision_abnormal": float(
            precision_score(actual, predicted, zero_division=0)
        ),
        "recall_abnormal": float(
            recall_score(actual, predicted, zero_division=0)
        ),
        "f1_abnormal": float(f1_score(actual, predicted, zero_division=0)),
        "balanced_accuracy": float(
            balanced_accuracy_score(actual, predicted)
        ),
        "roc_auc": float(roc_auc_score(actual, probabilities)),
        "confusion_matrix": matrix.tolist(),
    }


def train(data_path: Path, model_path: Path) -> tuple[dict, dict]:
    features, labels, quality = load_data(data_path)
    x_train, y_train, x_validation, y_validation, x_test, y_test = split(
        features, labels
    )

    candidates = {
        "balanced_logistic_regression": make_pipeline(
            StandardScaler(),
            LogisticRegression(
                class_weight="balanced", max_iter=2000, random_state=42
            ),
        ),
        "balanced_random_forest": RandomForestClassifier(
            n_estimators=350,
            min_samples_leaf=2,
            class_weight="balanced",
            n_jobs=1,
            random_state=42,
        ),
        "balanced_extra_trees": ExtraTreesClassifier(
            n_estimators=350,
            min_samples_leaf=2,
            class_weight="balanced",
            n_jobs=1,
            random_state=42,
        ),
    }

    validation_metrics = {}
    trained = {}
    for name, model in candidates.items():
        model.fit(x_train, y_train)
        trained[name] = model
        validation_metrics[name] = evaluate(
            y_validation,
            model.predict(x_validation),
            model.predict_proba(x_validation)[:, 1],
        )

    selected_name = max(
        validation_metrics,
        key=lambda name: (
            validation_metrics[name]["f1_abnormal"],
            validation_metrics[name]["recall_abnormal"],
        ),
    )
    model = trained[selected_name]
    test_metrics = evaluate(
        y_test, model.predict(x_test), model.predict_proba(x_test)[:, 1]
    )

    metrics = {
        "task": "abnormal_usage_detection",
        "quality": quality,
        "samples": {
            "train": int(len(x_train)),
            "validation": int(len(x_validation)),
            "test": int(len(x_test)),
        },
        "selected_model": selected_name,
        "candidate_validation": validation_metrics,
        "test": test_metrics,
    }
    artifact = {
        "model": model,
        "model_name": selected_name,
        "feature_columns": FEATURE_COLUMNS,
        "input_scale": "dataset_normalized_0_to_1",
        "positive_label": "Abnormal",
        "negative_label": "Normal",
        "limitation": (
            "The Kaggle features are pre-normalized without original scaling "
            "metadata. Real sensor inputs require a calibrated transformer."
        ),
    }
    model_path.parent.mkdir(parents=True, exist_ok=True)
    joblib.dump(artifact, model_path)
    return metrics, artifact


def write_reports(metrics: dict, metrics_path: Path, report_path: Path) -> None:
    metrics_path.parent.mkdir(parents=True, exist_ok=True)
    metrics_path.write_text(json.dumps(metrics, indent=2) + "\n")
    test = metrics["test"]
    tn, fp = test["confusion_matrix"][0]
    fn, tp = test["confusion_matrix"][1]
    report_path.write_text(
        f"""# Abnormal Usage Detection Baseline

## Dataset

- Rows: {metrics["quality"]["rows"]:,}
- Normal: {metrics["quality"]["normal"]:,}
- Abnormal: {metrics["quality"]["abnormal"]:,}
- Imputed values: {metrics["quality"]["imputed_values"]:,}
- Selected model: **{metrics["selected_model"]}**

## Chronological test results

| Metric | Score |
|---|---:|
| Abnormal precision | {test["precision_abnormal"]:.4f} |
| Abnormal recall | {test["recall_abnormal"]:.4f} |
| Abnormal F1 | {test["f1_abnormal"]:.4f} |
| Balanced accuracy | {test["balanced_accuracy"]:.4f} |
| ROC-AUC | {test["roc_auc"]:.4f} |

Confusion matrix: TN={tn}, FP={fp}, FN={fn}, TP={tp}.

## Important limitation

The dataset features are already normalized to 0–1, but its original scaling
ranges are not provided. The saved model is valid for dataset-compatible
normalized values. Real ESP32 readings require a calibration layer before this
classifier can be used operationally.
"""
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", type=Path, default=DEFAULT_DATA)
    parser.add_argument("--model", type=Path, default=DEFAULT_MODEL)
    parser.add_argument("--metrics", type=Path, default=DEFAULT_METRICS)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    args = parser.parse_args()
    metrics, _ = train(args.data, args.model)
    write_reports(metrics, args.metrics, args.report)
    print(json.dumps(metrics, indent=2))


if __name__ == "__main__":
    main()

