#pragma once

// Copy this file to config.h and fill in your private values.
// Never commit config.h.
const char* WIFI_SSID = "YOUR_WIFI_NAME";
const char* WIFI_PASSWORD = "YOUR_WIFI_PASSWORD";

// Use your Mac's Wi-Fi address, not 127.0.0.1.
// Example: http://192.168.1.20:8000/devices/EM-2048/readings
const char* API_READING_URL =
    "http://YOUR_MAC_IP:8000/devices/EM-2048/readings";
const char* API_COMMAND_URL =
    "http://YOUR_MAC_IP:8000/devices/EM-2048/relay-command";
const char* API_DISPLAY_URL =
    "http://YOUR_MAC_IP:8000/devices/EM-2048/display-summary";
const char* DEVICE_API_KEY = "YOUR_DEVICE_API_KEY";

// Keep false until the relay has been tested with a safe low-voltage load.
constexpr bool ENABLE_LOAD_RELAY = false;

// Sensor calibration profile. Leave these defaults until you compare the
// sensor with a trustworthy reference, then use the formulas in README.md.
constexpr float DHT_TEMPERATURE_OFFSET_C = 0.0f;
constexpr float DHT_HUMIDITY_OFFSET_PERCENT = 0.0f;
constexpr float PZEM_VOLTAGE_MULTIPLIER = 1.0f;
constexpr float PZEM_CURRENT_MULTIPLIER = 1.0f;
constexpr float PZEM_POWER_MULTIPLIER = 1.0f;
constexpr float PZEM_ENERGY_MULTIPLIER = 1.0f;

// MQ-2 thresholds adapt from the saved clean-air baseline, but the firmware
// retains its existing absolute safety floors.
constexpr float MQ2_WARNING_BASELINE_FACTOR = 2.0f;
constexpr float MQ2_DANGER_BASELINE_FACTOR = 3.25f;
