# Wattly Presentation Slide Outline

## Slide 1 — Title

**Wattly: AI Smart Prepaid Energy Meter**

Subtitle:

IoT-based prepaid electricity monitoring with AI insights, safety alerts, and
Sri Lankan tariff calculation.

Include:

- Your name
- Course/module
- Lecturer name
- Date

## Slide 2 — Problem

**Problem**

- Users often do not know real-time electricity usage.
- Prepaid balance can finish unexpectedly.
- Monthly cost is hard to estimate.
- Abnormal usage and safety risks are not visible early.
- Existing meters usually do not give AI-based recommendations.

## Slide 3 — Proposed solution

**Proposed solution**

Wattly provides:

- Live voltage/current/power/energy monitoring
- Prepaid recharge and balance tracking
- Sri Lankan tariff-based cost calculation
- Safety alerts
- Usage history
- AI predictions and recommendations

## Slide 4 — System architecture

**Architecture**

Flow:

ESP32 hardware → FastAPI backend → Firestore/SQLite → Flutter dashboard → User

Mention:

- ESP32 sends readings.
- Backend processes usage, alerts, tariff, and AI predictions.
- Dashboard displays customer-friendly results.

## Slide 5 — IoT hardware

**Hardware components**

- ESP32 DevKit V1
- PZEM-004T energy meter
- DHT22 temperature/humidity sensor
- MQ-2 gas sensor
- PIR motion sensor
- ILI9341 TFT display
- Relay module
- Green/red status LEDs

Add photo of your hardware.

## Slide 6 — Dashboard overview

**Dashboard**

Show screenshot:

- Meter online status
- Voltage
- Current
- Power
- Monthly usage
- Today usage
- Temperature

Key point:

The dashboard updates from live ESP32 or simulator readings.

## Slide 7 — Prepaid recharge system

**Recharge and balance**

Features:

- First activation minimum Rs. 500
- Later recharge minimum Rs. 100
- Manual recharge amount
- Demo payment flow
- Balance reduces with measured usage

Mention:

No real payment is made in the prototype.

## Slide 8 — Sri Lankan tariff calculation

**Sri Lankan electricity tariff support**

Explain:

- Users understand electricity as “units”.
- 1 unit = 1 kWh.
- Dashboard shows both units and LKR cost.
- Cost uses Sri Lankan domestic tariff blocks.

Mention:

PUCSL tariff monitoring/approval workflow is included for safe tariff updates.

## Slide 9 — Usage history

**Usage history**

Views:

- Day: 24-hour usage
- Week: Monday to Sunday
- Month: calendar dates

Shows:

- Units used
- Estimated cost
- Usage trend

## Slide 10 — Alerts

**Safety alerts**

Alert examples:

- Gas level elevated
- High temperature
- High power usage
- Voltage outside safe range

Features:

- Active alert badge
- Acknowledge alert
- Resolved alert history

## Slide 11 — AI Insights

**AI Insights**

AI features:

- Tomorrow usage forecast
- Balance depletion prediction
- End-of-month bill prediction
- Abnormal usage detection
- Safety risk prediction
- Appliance pattern detection
- Energy-saving recommendations

## Slide 12 — AI system status

**Customer-friendly AI status**

The dashboard shows simple AI checks:

- Usage forecast
- Unusual usage check
- Appliance pattern check
- Smoke/fire safety check
- Electrical condition check
- Gas sensor support

Key point:

Technical ML details are hidden from customers to keep the dashboard easy to
understand.

## Slide 13 — Datasets used

**Public datasets used**

| Feature | Dataset |
|---|---|
| Energy forecasting | Household Power Consumption |
| Abnormal detection | Smart Meter Electricity Consumption Dataset |
| Appliance detection | Real Appliance Power Signatures |
| Appliance support | Household Appliances Power Consumption |
| Smoke/fire safety | Smoke Detection Dataset |
| Gas support | Gas Sensor Array Drift Dataset |
| Electrical fault risk | Power Quality Fault Detection Dataset |

## Slide 14 — AI model results

**Model results**

Examples:

- Abnormal usage F1: 85.7%
- Appliance known-device accuracy: 94.0%
- Smoke/fire F1: 100.0%
- Electrical fault macro-F1: 99.8%
- Gas identity macro-F1: 63.0%
- Energy forecast MAE: 6.01 units/kWh

Mention:

Energy forecasting needs tuning and is the main AI improvement area.

## Slide 15 — TensorFlow/Keras future work

**TensorFlow/Keras plan**

Current status:

- Classical ML prototype is working.
- TensorFlow/Keras is planned later due storage limitation.

Future TensorFlow benefits:

- LSTM/GRU for time-series forecasting
- CNN/LSTM for appliance power signatures
- TensorFlow Lite deployment possibility
- Stronger academic deep-learning component

## Slide 16 — Demo plan

**Live demo**

Demo order:

1. Dashboard live readings
2. Recharge
3. Usage history
4. Alerts
5. AI Insights
6. AI system status

Backup:

No-hardware simulator can send fake ESP32 readings.

## Slide 17 — Limitations

**Current limitations**

- TensorFlow/Keras not completed yet.
- AI uses public datasets, not long-term real household data.
- Forecast accuracy needs improvement.
- Appliance detection is prototype-level.
- Gas identity is not direct leak probability.
- Automatic relay control is disabled for safety.

## Slide 18 — Future improvements

**Future work**

- Add TensorFlow/Keras model
- Collect long-term ESP32 data
- Improve appliance detection
- Improve push notifications
- Add safer relay-control workflow
- Deploy backend/cloud version

## Slide 19 — Conclusion

**Conclusion**

Wattly demonstrates a working AI smart prepaid energy meter prototype.

It combines:

- IoT metering
- Prepaid balance tracking
- Sri Lankan tariff calculation
- Safety alerts
- AI insights
- Customer-friendly dashboard

Final statement:

The prototype is ready for demonstration, and the next major improvement is
TensorFlow/Keras-based model enhancement using long-term real meter data.

