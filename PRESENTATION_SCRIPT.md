# Wattly Presentation Script

## 1. Opening introduction

Good morning/afternoon. My project is called **Wattly — AI Smart Prepaid Energy
Meter**.

The main idea is to create a smart prepaid electricity meter that can monitor
home electricity usage, calculate prepaid balance, detect safety risks, and give
AI-based insights to the user through a web dashboard.

This project is designed for Sri Lankan domestic electricity users, so the
dashboard uses units/kWh and Sri Lankan rupee cost based on tariff blocks.

## 2. Problem statement

In many homes, users only understand their electricity usage after receiving a
bill or after prepaid credit is almost finished. There is also limited awareness
of abnormal usage, appliance behaviour, and safety risks such as high gas level,
overheating, voltage issues, or high power demand.

This project tries to solve that by giving the user:

- Live meter readings
- Prepaid balance tracking
- Usage history
- Safety alerts
- AI predictions and recommendations

## 3. System overview

The system has four main parts:

1. **IoT hardware**
   - ESP32 DevKit V1
   - PZEM-004T energy meter
   - DHT22 temperature/humidity sensor
   - MQ-2 gas sensor
   - PIR motion sensor
   - Relay module
   - ILI9341 TFT display

2. **Backend**
   - Python FastAPI server
   - Receives meter readings
   - Calculates usage, cost, balance, alerts, and AI predictions

3. **Database**
   - Firebase Authentication
   - Firestore persistence
   - SQLite fallback for local testing

4. **Dashboard**
   - Flutter web dashboard
   - Shows live energy, recharge, alerts, usage history, settings, and AI insights

## 4. Hardware explanation

The ESP32 works as the main controller.

The PZEM-004T measures voltage, current, power, and energy. The DHT22 measures
temperature and humidity. The MQ-2 sensor gives gas-level readings. The PIR
sensor detects motion. The relay is used for load-control testing, and the TFT
display shows meter status directly on the hardware.

For safety, automatic mains relay cut-off is currently disabled. The relay has
been tested, but in the dashboard it remains controlled carefully because mains
electricity must be handled safely.

## 5. Dashboard demo — live overview

Show: **Dashboard page**

Explain:

This is the live energy overview. It shows voltage, current, power, monthly
usage, today’s usage, and temperature. The top-right status shows whether the
meter is online.

When the ESP32 or simulator sends readings to the FastAPI backend, the dashboard
updates automatically.

If using simulator:

For the presentation, I can also use a simulator that sends fake ESP32 readings.
This is useful as a backup if hardware or Wi-Fi is unstable.

## 6. Recharge / prepaid demo

Show: **Recharge page**

Explain:

This page simulates prepaid meter recharge. For a new account, the first
activation requires a minimum Rs. 500 demo payment. After activation, the user
can recharge a minimum of Rs. 100 or enter a manual amount.

This is demo-only, so no real payment is charged.

The balance reduces according to measured energy usage and Sri Lankan tariff
calculation.

## 7. Usage history demo

Show: **Usage history page**

Explain:

The usage history page helps the user understand energy consumption by:

- Day view: 24-hour usage
- Week view: Monday to Sunday usage
- Month view: calendar date usage

It also shows usage units and cost, making it easier for normal users to
understand electricity consumption.

## 8. Alerts demo

Show: **Alerts page**

Explain:

The alert system monitors live meter readings and creates alerts when the system
detects unsafe or unusual readings.

Alert examples:

- Gas level elevated
- Temperature high
- High power usage
- Voltage outside safe range

The user can acknowledge alerts. The red badge count updates when active alerts
are acknowledged or resolved.

If running no-hardware demo, mention:

Here I am using test alerts or simulated sensor phases to demonstrate how the
alert system behaves.

## 9. AI Insights demo

Show: **AI Insights page**

Explain:

This page contains the AI-based features of the system. The AI layer helps the
user understand future usage, abnormal behaviour, appliance patterns, and safety
risks.

The main AI features are:

1. **Energy consumption prediction**
   - Predicts tomorrow’s electricity usage.

2. **Balance depletion prediction**
   - Estimates how many days the current prepaid balance will last.

3. **End-of-month bill prediction**
   - Estimates monthly units and monthly cost using Sri Lankan tariff blocks.

4. **Abnormal usage detection**
   - Checks whether the current usage pattern looks normal or unusual.

5. **Smart safety risk prediction**
   - Shows gas, overheating, and electrical risk signals.

6. **Appliance usage detection**
   - Estimates possible appliance categories from power-pattern samples.

7. **AI recommendations**
   - Gives practical suggestions, such as recharge soon, watch bill projection,
     schedule high-load appliances, or review safety signals.

## 10. AI system status explanation

Show: **AI system status card**

Explain:

This section is written for normal customers. Instead of showing complex model
metrics, it explains each AI check in simple words.

For example:

- Usage forecast
- Unusual usage check
- Appliance pattern check
- Smoke and fire safety check
- Electrical condition check
- Gas sensor support

It also shows simple confidence/status labels so customers can understand the
system without machine-learning knowledge.

## 11. Technical AI explanation for lecturer

Use: [AI_PRESENTATION_REPORT.md](./AI_PRESENTATION_REPORT.md)

Explain:

The technical AI details are kept in a separate report so the customer dashboard
does not become confusing.

The AI models currently use public datasets:

- Household Power Consumption
- Smart Meter Electricity Consumption Dataset
- Real Appliance Power Signatures
- Household Appliances Power Consumption
- Smoke Detection Dataset
- Gas Sensor Array Drift Dataset
- Power Quality Fault Detection Dataset

The current implementation uses classical machine-learning models such as Extra
Trees and Balanced Extra Trees. TensorFlow/Keras is planned as future work,
mainly for stronger time-series forecasting and appliance power-signature
detection.

## 12. TensorFlow/Keras explanation

If asked why TensorFlow is not completed:

TensorFlow/Keras is planned as the next improvement. The current prototype uses
public datasets and classical ML models to prove the complete AI workflow first.
TensorFlow will be useful later for LSTM/GRU forecasting and CNN/LSTM appliance
signature detection. It was postponed because of storage limitations and because
the project first needed a stable end-to-end IoT and dashboard flow.

If asked what TensorFlow will improve:

It can improve:

- Time-series energy forecasting
- Appliance signature detection
- Future TensorFlow Lite deployment
- Academic deep-learning value

## 13. Demo commands

FastAPI:

```bash
cd ~/Desktop/smart_energy_dashboard
set -a
source .env
set +a
python3 -m uvicorn api:app --app-dir ai_training/src --host 0.0.0.0 --port 8000
```

Flutter:

```bash
cd ~/Desktop/smart_energy_dashboard
flutter run -d chrome
```

No-hardware simulator:

```bash
cd ~/Desktop/smart_energy_dashboard
set -a
source .env
set +a
python3 ai_training/src/presentation_demo.py --recharge-demo --test-alerts
```

## 14. If something goes wrong during demo

If meter shows offline:

Start the no-hardware simulator and wait 5–10 seconds.

If AI report shows offline:

Check:

```bash
curl -i http://127.0.0.1:8000/predict/model-report
```

Expected:

```text
HTTP/1.1 200 OK
```

If alerts are empty:

Run:

```bash
curl -X POST http://127.0.0.1:8000/devices/EM-2048/alerts/test \
  -H "X-Admin-Key: $TARIFF_ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{"alert_type":"gas","severity":"Warning"}'
```

## 15. Limitations

Current limitations:

- TensorFlow/Keras integration is planned but not completed yet.
- AI models use public datasets, not long-term real household data.
- Appliance detection is prototype-level.
- Forecast accuracy needs tuning.
- Gas identity dataset does not directly provide gas-leak probability.
- Automatic relay control is disabled until safe hardware validation is complete.

## 16. Future work

Future improvements:

- Add TensorFlow/Keras forecasting model.
- Collect long-term ESP32 readings and calibrate models.
- Improve appliance detection with more local appliance signatures.
- Add safer relay-control workflow.
- Improve notification reliability.
- Deploy backend/cloud version for remote access.

## 17. Closing statement

In conclusion, Wattly demonstrates a working AI smart prepaid energy meter
prototype. It combines IoT metering, prepaid balance tracking, Sri Lankan tariff
calculation, safety alerts, AI insights, and a customer-friendly dashboard.

The current version is ready as a prototype, and the next major improvement is
TensorFlow/Keras model enhancement using real long-term meter data.

