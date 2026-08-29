# Wattly handover and demonstration guide

## 1. Start the backend

Open Terminal 1:

```bash
cd ~/Desktop/smart_energy_dashboard
set -a
source .env
set +a
python3 -m uvicorn api:app --app-dir ai_training/src --host 0.0.0.0 --port 8000
```

Keep this terminal open. A successful ESP32 upload appears as `POST ... 202 Accepted`.

## 2. Start the dashboard on the Mac

Open Terminal 2:

```bash
cd ~/Desktop/smart_energy_dashboard
flutter run -d chrome --dart-define=AI_API_BASE_URL=http://127.0.0.1:8000
```

Sign in with the Firebase test account.

## 3. Connect the ESP32

- Connect the ESP32 and laptop to the same Wi-Fi network.
- Confirm the Mac Wi-Fi address with `ipconfig getifaddr en0`.
- If the address changed, update all three URLs in `firmware/wattly_meter/config.h`, then upload the firmware again.
- The TFT/Serial Monitor should show `Wi-Fi: Connected` and `API: Synced`.

## 4. Demonstrate alert simulations

1. Open **Simulations** in the sidebar.
2. Press Gas warning, Overheating, Power overload, Voltage fault, PZEM failure, DHT22 failure, or Possible intrusion.
3. Within the next ESP32 command poll, the red LED and buzzer operate for about 8 seconds.
4. Open **Alerts** to show the clearly labelled simulation event.
5. Press **Clear simulations** when finished.

Simulation buttons never change the actual sensor calibration and never switch the mains load.

## 5. Demonstrate theft protection

- Automatic mode is active every day from **12:00 AM until 6:00 AM** using Sri Lanka time.
- For a daytime presentation, enable the **Manual protection** switch on the Simulations page.
- Move in front of the PIR sensor.
- Wattly creates a critical possible-intrusion alert, turns on the red LED, and sounds the buzzer.
- Browser and Android notifications appear when notifications are enabled and the dashboard/app is running.
- After three consecutive readings without motion, the alert resolves automatically.

## 6. Android demo APK

The installable presentation APK is `Wattly-demo.apk` in the project root. It was built for API address `http://192.168.8.102:8000`.

- Copy it to an Android phone and allow installation from that source.
- Keep the phone on the same Wi-Fi as the Mac and ESP32.
- Keep FastAPI running on the Mac.
- If the Mac IP changes, rebuild the APK using the new address.

## 7. Hosting status

The web bundle and Firebase Hosting configuration are ready. Static hosting can publish the dashboard UI. Full remote live-hardware operation additionally requires the FastAPI backend to be hosted at a public HTTPS address; a Firebase-hosted HTTPS page cannot safely call a private laptop HTTP address.

