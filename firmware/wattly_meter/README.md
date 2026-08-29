# Wattly ESP32 firmware

This sketch matches the tested hardware:

- TFT_eSPI ILI9341 using the existing TFT_eSPI `User_Setup`
- PZEM-004T V3 on UART2, ESP32 RX GPIO16 and TX GPIO17
- DHT22 GPIO27
- MQ-2 analog GPIO34
- PIR GPIO26
- relay GPIO25, active HIGH on the tested Wattly module
- blue Wi-Fi LED GPIO13, green load LED GPIO32, red alert LED GPIO33
- MQ-2 clean-air calibration stored in ESP32 non-volatile memory

## Arduino libraries

Install through Arduino Library Manager:

- `TFT_eSPI`
- `PZEM004Tv30`
- `DHT sensor library` by Adafruit
- `Adafruit Unified Sensor`

`WiFi` and `HTTPClient` are included with the ESP32 Arduino core.

## Configure and upload

1. Copy `config.example.h` to `config.h`.
2. Add Wi-Fi, Mac API URL, and the same `DEVICE_API_KEY` used by Uvicorn.
3. Keep `ENABLE_LOAD_RELAY` false for communication testing.
4. Start the API on the Mac with `--host 0.0.0.0`.
5. Upload `wattly_meter.ino`.
6. Confirm Serial Monitor reports HTTP `202` and the TFT says `SYNCED`.

The API URL must use the Mac's LAN IP, not `127.0.0.1`.

## Sensor calibration

### 1. MQ-2 clean-air baseline

The MQ-2 needs an initial burn-in of at least 48 hours with its heater powered.
Do this once for a new sensor. For later checks, allow the sensor to warm and
stabilize before calibration.

1. Put the meter in clean, ventilated air. Keep smoke, LPG, alcohol, perfume,
   and cleaning sprays away from it.
2. Power the meter and wait until the MQ-2 raw reading is reasonably stable.
3. Hold the TFT **LEFT and RIGHT buttons together for 3 seconds**.
4. Keep the air clean while the display samples for about 5 seconds.
5. Confirm the TFT reports `SAVED`. The result is retained after restart.

The firmware uses the median reading to reject ADC spikes. It derives
sensor-specific warning/danger levels while retaining the existing absolute
warning floor of 1600 and danger floor of 2600. A disconnected, saturated, or
already-contaminated sensor is rejected instead of being saved.

### 2. DHT22 temperature and humidity

Automatic self-calibration is not possible because the DHT22 needs an external
reference. Use a reliable temperature/humidity reference placed beside the
DHT22, away from the ESP32, TFT, MQ-2 heater, sunlight, and airflow.

1. Leave both sensors together for 15–20 minutes.
2. Record at least 10 paired readings and calculate both averages.
3. Calculate `offset = reference average - DHT22 average`.
4. Put the results in `config.h`:

```cpp
constexpr float DHT_TEMPERATURE_OFFSET_C = 0.0f;
constexpr float DHT_HUMIDITY_OFFSET_PERCENT = 0.0f;
```

Example: reference 28.0 C and Wattly 28.6 C gives a temperature offset of
`-0.6f`. Reference 70% and Wattly 68% gives a humidity offset of `2.0f`.

### 3. PZEM-004T V3

The PZEM is factory calibrated. Validate it against a trustworthy, enclosed
plug-in energy meter or a calibrated instrument using a steady, known load.
Mains-side measurements and wiring must be performed by a qualified person.

1. Run the same steady load through both meters.
2. Record several stable voltage, current, power, and accumulated-energy pairs.
3. For each channel calculate `multiplier = reference / PZEM reading`.
4. Put the averaged results in `config.h`:

```cpp
constexpr float PZEM_VOLTAGE_MULTIPLIER = 1.0f;
constexpr float PZEM_CURRENT_MULTIPLIER = 1.0f;
constexpr float PZEM_POWER_MULTIPLIER = 1.0f;
constexpr float PZEM_ENERGY_MULTIPLIER = 1.0f;
```

Example: reference voltage 230.0 V and PZEM voltage 228.5 V gives
`230.0 / 228.5 = 1.0066f`. Do not change a multiplier from `1.0f` without a
reference measurement.

After changing DHT22 or PZEM values, upload the firmware again. On startup, the
Serial Monitor prints the complete active calibration profile.

## Reliable safety behavior

- A dangerous value must appear in **3 consecutive readings** before Wattly
  opens a new incident. This prevents a single sensor spike from creating a
  false alarm.
- The relay opens immediately after a danger is confirmed. It cannot be turned
  on from the button or dashboard until the hazard has recovered and the alert
  has been acknowledged.
- Recovery requires **5 consecutive safe readings** and uses a safety margin,
  so an alert does not repeatedly switch on and off near its threshold.
- Repeated dangerous readings remain one alert incident instead of filling the
  dashboard with duplicates.
- During a short network outage, the ESP32 keeps up to 12 readings in RAM and
  uploads them after the API reconnects. The queue is cleared if the ESP32
  loses power or restarts.

## Electrical safety

Do not test mains wiring on a breadboard. Confirm that signals entering ESP32
pins stay within the ESP32 input limits. Never release combustible gas indoors
for calibration; the built-in MQ-2 routine is a clean-air baseline only. Keep
relay energizing disabled until it has been tested using an isolated
low-voltage load.
