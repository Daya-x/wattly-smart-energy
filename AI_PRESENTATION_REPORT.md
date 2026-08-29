# Wattly AI Presentation Report

## Project context

Wattly is an AI Smart Prepaid Energy Meter prototype. The system combines an
ESP32-based IoT meter, a FastAPI backend, a Flutter dashboard, Sri Lankan
electricity tariff calculation, and AI-based insight features.

The AI layer is currently a public-dataset prototype. It proves that the system
can perform forecasting, anomaly checking, appliance pattern recognition, and
safety risk support before training with long-term real household data.

## AI features currently implemented

| AI feature | Dashboard purpose | Current status |
|---|---|---|
| Energy consumption prediction | Predict tomorrow's electricity usage | Working prototype, needs tuning |
| Balance depletion prediction | Estimate how many days prepaid balance will last | Working with tariff rules |
| End-of-month bill prediction | Estimate monthly units and bill using Sri Lankan tariff blocks | Working with tariff rules |
| Abnormal usage detection | Detect unusual usage patterns | Working prototype |
| Smart safety risk prediction | Show gas, overheating, and electrical risk signals | Working with live threshold rules and public safety models |
| AI energy-saving recommendations | Suggest recharge, safety, usage, and appliance actions | Working |
| Appliance usage detection | Estimate likely appliance category from power signatures | Prototype classifier |
| AI system status | Show customer-friendly AI health and confidence | Working |

## Datasets used

| AI area | Dataset used | Why it was used |
|---|---|---|
| Energy forecasting | Household Power Consumption | Contains timestamped household voltage, current, power, and energy readings |
| Appliance energy/pattern support | Appliances Energy Prediction | Supports appliance-energy and environmental usage understanding |
| Abnormal usage detection | Smart Meter Electricity Consumption Dataset | Contains smart-meter style usage data and anomaly labels |
| Appliance detection | Real Appliance Power Signatures | Contains appliance power-signature windows for category classification |
| Appliance detection alternative | Household Appliances Power Consumption | Contains smart-plug appliance readings for many device categories |
| Fire/smoke prediction | Smoke Detection Dataset | Contains IoT-style environmental readings with fire alarm labels |
| Gas support | Gas Sensor Array Drift Dataset | Contains gas identity readings across different sensor drift batches |
| Electrical fault risk | Power Quality Fault Detection Dataset | Contains normal and fault power-quality conditions |

## Model summary

| Feature | Model used | Main metric | Result |
|---|---|---:|---:|
| Energy consumption prediction | Extra Trees Regressor | MAE | 6.01 units/kWh |
| Energy consumption prediction | Extra Trees Regressor | R² | -0.14 |
| Abnormal usage detection | Balanced Extra Trees Classifier | Abnormal F1 | 85.7% |
| Abnormal usage detection | Balanced Extra Trees Classifier | Abnormal recall | 82.5% |
| Appliance usage detection | Extra Trees Classifier | Known-device accuracy | 94.0% |
| Appliance usage detection | Extra Trees Classifier | Unseen-device macro-F1 | 29.5% |
| Smoke/fire safety prediction | Extra Trees Classifier | Fire F1 | 100.0% |
| Electrical fault risk | Extra Trees Classifier | Macro-F1 | 99.8% |
| Gas identity support | Extra Trees Classifier | Macro-F1 | 63.0% |

## How each AI feature works

### 1. Energy consumption prediction

The forecasting model predicts the next 24-hour household energy usage. It uses
historical power-consumption patterns from a public household power dataset.

In the dashboard, this appears as:

- Tomorrow’s forecast
- Estimated cost
- Recharge/balance recommendation

Current limitation: the forecasting dataset has limited calendar context, so
the accuracy is enough for a prototype but should be improved later using a
stronger time-series model and real meter history.

### 2. Balance depletion prediction

This is a rule-based AI support feature. It combines:

- Current balance
- Forecasted usage
- Current month usage
- Sri Lankan electricity tariff blocks

The system estimates how many days the user’s prepaid balance can last.

### 3. End-of-month bill prediction

This predicts the possible end-of-month electricity bill by projecting current
month usage across the billing cycle. The calculation uses Sri Lankan domestic
tariff blocks, so the dashboard shows both units and Sri Lankan rupee cost.

### 4. Abnormal usage detection

The anomaly model checks whether usage looks normal, watch-level, or abnormal.
It is trained on public smart-meter anomaly data.

In the dashboard, this appears as:

- Abnormal usage probability
- Normal / Watch / Abnormal label
- Usage pattern history

Current limitation: final deployment should learn each household’s normal daily
routine, because every home has different usage behaviour.

### 5. Appliance usage detection

The appliance model uses power-signature windows to estimate broad appliance
categories such as kitchen, multimedia, cooling, washing, or other appliances.

Known-device accuracy is high, but unseen-device performance is lower. This is
expected because appliance signatures vary between brands, homes, and wiring.

Current limitation: this is not a full non-intrusive load monitoring system yet.
It is a prototype appliance category classifier.

### 6. Smart safety risk prediction

The dashboard safety card combines two ideas:

1. Public-dataset safety models for smoke/fire, gas identity, and electrical
   fault research.
2. Transparent live ESP32 threshold rules for actual dashboard alerts.

For the real ESP32 prototype, live safety signals come from:

- MQ-2 gas raw value
- DHT22 temperature
- PZEM voltage/current/power
- Configured safe thresholds

This is safer than blindly trusting a public dataset model, because public
sensor datasets do not exactly match the project hardware.

## TensorFlow/Keras future work

TensorFlow/Keras is planned as a future enhancement. It was not completed in the
current build because laptop storage was limited.

Benefits of adding TensorFlow/Keras later:

- Use LSTM/GRU models for stronger time-series energy forecasting.
- Use CNN/LSTM models for better appliance power-signature detection.
- Prepare models for TensorFlow Lite deployment in the future.
- Improve academic value because the project will include a deep-learning
  component.

Recommended TensorFlow model to add first:

- LSTM/GRU model for energy consumption prediction.

Reason: energy forecasting is the clearest AI feature and easiest to explain in
the presentation.

## Important limitations

- Current AI models are trained on public datasets, not long-term real ESP32
  household data.
- Forecast accuracy needs improvement before production use.
- Appliance detection is good for known sample patterns but weaker for unseen
  real appliances.
- Gas identity data is not the same as gas-leak probability.
- Relay control must remain manual/safe until hardware validation is complete.
- TensorFlow/Keras integration is future work.

## Final presentation statement

The AI part of Wattly is completed as a working prototype. It demonstrates
energy forecasting, prepaid balance prediction, monthly bill prediction,
abnormal usage detection, appliance pattern detection, safety risk support, and
AI recommendations. The current version uses public datasets and classical
machine-learning models. The next AI improvement is to add TensorFlow/Keras and
later retrain or calibrate the models using long-term real meter data.

