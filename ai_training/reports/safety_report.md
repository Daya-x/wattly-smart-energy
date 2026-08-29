# Safety Model Baselines

## Smoke/fire detection

- Fire precision: 0.9997
- Fire recall: 1.0000
- Fire F1: 0.9998
- ROC-AUC: 1.0000

## Electrical power-quality classification

- Accuracy: 0.9979
- Macro-F1: 0.9979

## Gas identity under sensor drift

- Test batch: 10
- Accuracy: 0.6286
- Macro-F1: 0.6298

## Safety boundary

These public datasets use sensors and electrical systems different from the
project hardware. The smoke model predicts its dataset's fire-alarm label, the
electrical model classifies power-quality conditions, and the gas model
identifies one of six gases. The gas data has no clean-air class and therefore
cannot produce a calibrated leak probability.
