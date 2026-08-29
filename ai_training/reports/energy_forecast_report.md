# 24-Hour Energy Forecast Baseline

## Dataset

- Raw minute readings: 260,640
- Complete hourly periods: 4,344
- Imputed numeric values: 26,397
- Training samples: 2,906
- Validation samples: 623
- Test samples: 623

## Test results

Selected model: **extra_trees**

| Model | MAE (kWh) | RMSE (kWh) | R² |
|---|---:|---:|---:|
| Selected model | 6.0121 | 7.3986 | -0.1397 |
| Previous-24-hour baseline | 6.6296 | 8.6844 | -0.5702 |

Model MAE improvement over the naive baseline: **9.31%**.

## Important limitation

The supplied forecasting CSV contains time-of-day but no calendar date. The
pipeline therefore preserves sequential order but deliberately excludes
weekday, holiday, and seasonal features. This model is suitable for a project
prototype, not billing or safety-critical decisions.
