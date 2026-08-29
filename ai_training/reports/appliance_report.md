# Appliance Category Detection Baseline

## Leakage-safe evaluation

Entire physical smart-plug devices are held out from training.

- Feature windows: 20,611
- Training windows: 17,693
- Test windows: 2,918
- Test devices: [222, 302, 317, 325, 343]
- Device-holdout macro-F1: 0.2952
- Known-device random-split accuracy: 0.9401
- Known-device random-split macro-F1: 0.9268

| Category | Precision | Recall | F1 |
|---|---:|---:|---:|
| cooling | 0.852 | 0.912 | 0.881 |
| kitchen | 0.962 | 0.956 | 0.959 |
| multimedia | 0.957 | 0.954 | 0.955 |
| other | 0.877 | 0.865 | 0.871 |
| washing | 0.967 | 0.969 | 0.968 |

## Important limitation

The source records each appliance with an individual smart plug. The classifier
recognizes five broad appliance categories from isolated 60-second signatures.
It is not a full non-intrusive load-monitoring model for a combined household
meter.
