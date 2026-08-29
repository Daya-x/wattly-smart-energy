# Wattly no-hardware presentation demo

Use this when the ESP32 is not connected, Wi-Fi is unstable, or you want a safe
backup demo.

## 1. Start FastAPI

Open Terminal 1:

```bash
cd ~/Desktop/smart_energy_dashboard
set -a
source .env
set +a
python3 -m uvicorn api:app --app-dir ai_training/src --host 0.0.0.0 --port 8000
```

Leave this terminal running.

## 2. Start Flutter dashboard

Open Terminal 2:

```bash
cd ~/Desktop/smart_energy_dashboard
flutter run -d chrome
```

Log in, then keep the dashboard open.

## 3. Run no-hardware demo readings

Open Terminal 3:

```bash
cd ~/Desktop/smart_energy_dashboard
set -a
source .env
set +a
python3 ai_training/src/presentation_demo.py --recharge-demo --test-alerts
```

This sends realistic fake readings every 2 seconds. Firestore/SQLite persistence
still follows the backend sampling rules, so it does not store every single
reading.

## What to show

1. Dashboard
   - Meter online
   - Voltage/current/power/temperature changing
   - Today/month usage values

2. Recharge
   - Demo transaction history
   - Available balance
   - Explain: no real payment is made

3. Alerts
   - Test gas/voltage/temperature alerts
   - Acknowledge alert
   - Badge count changes

4. AI Insights
   - Tomorrow forecast
   - Monthly bill prediction
   - Abnormal usage detection
   - Safety risk prediction
   - Appliance detection
   - AI model performance report

## Stop demo

Press `Control + C` in Terminal 3.

