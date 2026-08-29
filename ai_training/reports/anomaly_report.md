# Abnormal Usage Detection Baseline

## Dataset

- Rows: 5,000
- Normal: 4,750
- Abnormal: 250
- Imputed values: 0
- Selected model: **balanced_extra_trees**

## Chronological test results

| Metric | Score |
|---|---:|
| Abnormal precision | 0.8919 |
| Abnormal recall | 0.8250 |
| Abnormal F1 | 0.8571 |
| Balanced accuracy | 0.9097 |
| ROC-AUC | 0.9967 |

Confusion matrix: TN=706, FP=4, FN=7, TP=33.

## Important limitation

The dataset features are already normalized to 0–1, but its original scaling
ranges are not provided. The saved model is valid for dataset-compatible
normalized values. Real ESP32 readings require a calibration layer before this
classifier can be used operationally.
