#include <WiFi.h>
#include <HTTPClient.h>
#include <TFT_eSPI.h>
#include <PZEM004Tv30.h>
#include <DHT.h>
#include <Preferences.h>
#include <time.h>

#include "config.h"

// ================= FIRMWARE =================
#define FIRMWARE_VERSION "Wattly reliable safety 2026-08-01"

// ================= PINS =================
#define PZEM_RX_PIN 16
#define PZEM_TX_PIN 17
#define DHT_PIN 27
#define MQ2_PIN 34
#define PIR_PIN 26
#define BUTTON_PIN 14
#define LEFT_BUTTON_PIN 19
#define RIGHT_BUTTON_PIN 15
#define RELAY_PIN 25
#define BLUE_LED 13
#define GREEN_LED 32
#define RED_LED 33
#define BUZZER_PIN 22

#define DHT_TYPE DHT22
// Dayalan's relay module tested as active HIGH:
// HIGH = relay ON, LOW = relay OFF.
#define RELAY_ON HIGH
#define RELAY_OFF LOW
// This setting is for a common active-HIGH buzzer module.
#define BUZZER_ON HIGH
#define BUZZER_OFF LOW

// ================= SAFETY THRESHOLDS =================
// MQ-2 is a raw ADC threshold and must be calibrated for your sensor.
constexpr int GAS_WARNING_RAW = 1600;
constexpr int GAS_DANGER_RAW = 2600;
constexpr float TEMPERATURE_DANGER_C = 55.0;
constexpr float POWER_WARNING_W = 2000.0;
constexpr float VOLTAGE_LOW_WARNING_V = 200.0;
constexpr float VOLTAGE_HIGH_WARNING_V = 250.0;
constexpr int GAS_RECOVERY_MARGIN_RAW = 150;
constexpr float TEMPERATURE_RECOVERY_C = 52.0;
constexpr float POWER_RECOVERY_W = 1800.0;
constexpr float VOLTAGE_LOW_RECOVERY_V = 205.0;
constexpr float VOLTAGE_HIGH_RECOVERY_V = 245.0;
constexpr uint8_t HAZARD_CONFIRM_READINGS = 3;
constexpr uint8_t HAZARD_CLEAR_READINGS = 5;
constexpr uint8_t OFFLINE_QUEUE_CAPACITY = 12;
constexpr uint8_t OFFLINE_FLUSH_PER_CYCLE = 3;
constexpr unsigned long SAMPLE_INTERVAL_MS = 2000;
constexpr unsigned long API_INTERVAL_MS = 5000;
constexpr unsigned long COMMAND_INTERVAL_MS = 2000;
constexpr unsigned long DISPLAY_API_INTERVAL_MS = 60000;
constexpr unsigned long DISPLAY_API_RETRY_MS = 10000;
constexpr unsigned long WIFI_RETRY_INTERVAL_MS = 10000;
constexpr unsigned long BUTTON_DEBOUNCE_MS = 60;
// Hold a navigation button for 0.4 seconds to change one screen.
constexpr unsigned long NAV_PRESS_CONFIRM_MS = 400;
// A short, stable release rearms the button for the next click.
constexpr unsigned long NAV_RELEASE_ARM_MS = 80;
constexpr unsigned long NAV_CHANGE_COOLDOWN_MS = 400;
constexpr unsigned long CALIBRATION_HOLD_MS = 3000;
constexpr int MQ2_CALIBRATION_SAMPLES = 101;
constexpr unsigned long BUZZER_STEP_MS = 180;
constexpr unsigned long STARTUP_TEST_STEP_MS = 450;
constexpr int SCREEN_COUNT = 8;

// ================= TFT DESIGN SYSTEM =================
// The interface uses true black so it remains neutral even on ILI9341
// modules whose RGB/BGR order differs. The lime accent matches the dashboard.
#define NAVY TFT_BLACK
#define CARD 0x10A2
#define CARD_ALT 0x18E3
#define BORDER 0x4228
#define GREEN 0xAFE5
#define SOFT_GREEN 0x1B64
#define WHITE 0xF7DE
#define GREY 0xC618
#define RED 0xF2CB
#define ORANGE 0xFD69
#define CYAN 0x5E9F

// ================= DEVICES =================
TFT_eSPI tft = TFT_eSPI();
HardwareSerial pzemSerial(2);
PZEM004Tv30 pzem(pzemSerial, PZEM_RX_PIN, PZEM_TX_PIN);
DHT dht(DHT_PIN, DHT_TYPE);
Preferences calibrationPreferences;

// ================= RUNTIME STATE =================
float voltage = 0;
float current = 0;
float power = 0;
float energy = 0;
float temperature = 0;
float humidity = 0;
int gasValue = 0;
bool motionDetected = false;
bool manualRelayRequested = false;
bool relayState = false;
bool pzemValid = false;
bool dhtValid = false;
bool systemSafe = false;
bool alertActive = false;
bool apiConnected = false;
bool creditAllowed = true;
bool displayApiValid = false;
bool displayRemainingDaysReady = false;
bool remoteSafetyLocked = false;
bool safetyLockLatched = false;
bool safetyLockSeenByServer = false;
bool theftMonitoringActive = false;
bool theftMotionAlert = false;
bool remoteDemoAlertActive = false;
unsigned long remoteDemoAlertUntil = 0;
int lastHttpCode = 0;
String lastApiDetail = "Not attempted yet";
String lastRelayCommandId = "";
float displayForecastKwh = 0.0;
float displayRemainingDays = 0.0;
float displayBalanceLkr = 0.0;
float displayEstimatedCostLkr = 0.0;
int displaySavingPercent = 0;
String displayAccountStatus = "Waiting";
String displayRecommendation1 = "Waiting for AI data";
String displayRecommendation2 = "";
String displayRecommendationImpact = "Waiting";

unsigned long lastSampleAt = 0;
unsigned long lastApiAt = 0;
unsigned long lastCommandAt = 0;
unsigned long lastDisplayApiAt = 0;
unsigned long lastWiFiRetryAt = 0;
int lastButtonReading = HIGH;
int stableButtonState = HIGH;
unsigned long lastButtonChangeAt = 0;
bool previousAlertActive = false;
bool buzzerState = false;
int buzzerEdgesRemaining = 0;
unsigned long lastBuzzerChangeAt = 0;
int currentScreen = 0;
unsigned long lastNavigationAt = 0;
unsigned long calibrationButtonsHeldAt = 0;
bool calibrationComboHandled = false;
int mq2CleanAirBaselineRaw = 0;
int gasWarningThresholdRaw = GAS_WARNING_RAW;
int gasDangerThresholdRaw = GAS_DANGER_RAW;

struct HazardFilter {
  uint8_t badStreak = 0;
  uint8_t goodStreak = 0;
  bool active = false;
};

HazardFilter sensorFailureFilter;
HazardFilter gasHazardFilter;
HazardFilter temperatureHazardFilter;
HazardFilter powerHazardFilter;
HazardFilter voltageHazardFilter;

enum ConfirmedHazardBit : uint8_t {
  HAZARD_PZEM = 1 << 0,
  HAZARD_DHT = 1 << 1,
  HAZARD_GAS = 1 << 2,
  HAZARD_TEMPERATURE = 1 << 3,
  HAZARD_POWER = 1 << 4,
  HAZARD_VOLTAGE = 1 << 5,
};

struct SensorSnapshot {
  float voltage;
  float current;
  float power;
  float energy;
  float temperature;
  float humidity;
  int gas;
  bool motion;
  bool relay;
  bool pzemValid;
  bool dhtValid;
  bool safetyConfirmed;
  uint8_t confirmedHazardMask;
};

SensorSnapshot offlineQueue[OFFLINE_QUEUE_CAPACITY];
uint8_t offlineQueueHead = 0;
uint8_t offlineQueueCount = 0;

struct NavigationButtonState {
  int pin;
  int lastReading;
  unsigned long changedAt;
  bool armed;
  bool pressHandled;
};

NavigationButtonState leftNavigation = {
    LEFT_BUTTON_PIN, HIGH, 0, false, false};
NavigationButtonState rightNavigation = {
    RIGHT_BUTTON_PIN, HIGH, 0, false, false};

// ================= SENSOR CALIBRATION =================
void updateMq2Thresholds() {
  // A stored baseline adapts the warning levels to this particular MQ-2.
  // The original absolute limits remain floors, so a bad calibration can
  // never make the firmware less sensitive than the tested safe defaults.
  if (mq2CleanAirBaselineRaw >= 50 && mq2CleanAirBaselineRaw < GAS_WARNING_RAW) {
    const int baselineWarning =
        static_cast<int>(mq2CleanAirBaselineRaw * MQ2_WARNING_BASELINE_FACTOR);
    const int baselineDanger =
        static_cast<int>(mq2CleanAirBaselineRaw * MQ2_DANGER_BASELINE_FACTOR);
    gasWarningThresholdRaw =
        constrain(max(GAS_WARNING_RAW, baselineWarning), 0, 3895);
    gasDangerThresholdRaw = constrain(
        max(GAS_DANGER_RAW, baselineDanger),
        gasWarningThresholdRaw + 200,
        4095);
    return;
  }

  mq2CleanAirBaselineRaw = 0;
  gasWarningThresholdRaw = GAS_WARNING_RAW;
  gasDangerThresholdRaw = GAS_DANGER_RAW;
}

void loadStoredCalibration() {
  calibrationPreferences.begin("wattly-cal", false);
  mq2CleanAirBaselineRaw = calibrationPreferences.getInt("mq2base", 0);
  updateMq2Thresholds();

  Serial.printf(
      "CALIBRATION: MQ-2 baseline %d | warning %d | danger %d\n",
      mq2CleanAirBaselineRaw,
      gasWarningThresholdRaw,
      gasDangerThresholdRaw);
  Serial.printf(
      "CALIBRATION: DHT temp offset %.2f C | humidity offset %.2f %%\n",
      DHT_TEMPERATURE_OFFSET_C,
      DHT_HUMIDITY_OFFSET_PERCENT);
  Serial.printf(
      "CALIBRATION: PZEM factors V %.5f | A %.5f | W %.5f | kWh %.5f\n",
      PZEM_VOLTAGE_MULTIPLIER,
      PZEM_CURRENT_MULTIPLIER,
      PZEM_POWER_MULTIPLIER,
      PZEM_ENERGY_MULTIPLIER);
}

// ================= OUTPUT CONTROL =================
void applyRelayOutput() {
  relayState =
      ENABLE_LOAD_RELAY &&
      manualRelayRequested &&
      creditAllowed &&
      systemSafe &&
      !safetyLockLatched &&
      !remoteSafetyLocked;
  digitalWrite(RELAY_PIN, relayState ? RELAY_ON : RELAY_OFF);
}

void updateIndicators() {
  // Blue: ESP32 has joined Wi-Fi. This intentionally does not depend on
  // the API, so a server problem does not look like a Wi-Fi problem.
  digitalWrite(
      BLUE_LED,
      WiFi.status() == WL_CONNECTED ? HIGH : LOW);

  // Green: the physical relay output/load is actually enabled.
  digitalWrite(GREEN_LED, relayState ? HIGH : LOW);

  // Red: a sensor failure or safety/warning condition is active.
  digitalWrite(RED_LED, alertActive ? HIGH : LOW);
}

void startAlertBuzzer() {
  // Three short beeps. The pattern starts once when an alert appears.
  buzzerState = true;
  buzzerEdgesRemaining = 5;
  lastBuzzerChangeAt = millis();
  digitalWrite(BUZZER_PIN, BUZZER_ON);
}

void updateAlertBuzzer() {
  if (alertActive && !previousAlertActive) {
    startAlertBuzzer();
  } else if (!alertActive) {
    buzzerState = false;
    buzzerEdgesRemaining = 0;
    digitalWrite(BUZZER_PIN, BUZZER_OFF);
  }
  previousAlertActive = alertActive;

  if (buzzerEdgesRemaining <= 0) return;
  if (millis() - lastBuzzerChangeAt < BUZZER_STEP_MS) return;

  lastBuzzerChangeAt = millis();
  buzzerState = !buzzerState;
  buzzerEdgesRemaining--;
  digitalWrite(BUZZER_PIN, buzzerState ? BUZZER_ON : BUZZER_OFF);

  if (buzzerEdgesRemaining == 0) {
    buzzerState = false;
    digitalWrite(BUZZER_PIN, BUZZER_OFF);
  }
}

void runOutputSelfTest() {
  Serial.println("OUTPUT TEST: blue WiFi LED");
  digitalWrite(BLUE_LED, HIGH);
  delay(STARTUP_TEST_STEP_MS);
  digitalWrite(BLUE_LED, LOW);

  Serial.println("OUTPUT TEST: green load LED");
  digitalWrite(GREEN_LED, HIGH);
  delay(STARTUP_TEST_STEP_MS);
  digitalWrite(GREEN_LED, LOW);

  Serial.println("OUTPUT TEST: red alert LED + buzzer");
  digitalWrite(RED_LED, HIGH);
  digitalWrite(BUZZER_PIN, BUZZER_ON);
  delay(STARTUP_TEST_STEP_MS);
  digitalWrite(BUZZER_PIN, BUZZER_OFF);
  digitalWrite(RED_LED, LOW);

  Serial.println("OUTPUT TEST: complete");
}

// ================= SENSOR READING =================
void readSensors() {
  const float newVoltage = pzem.voltage();
  const float newCurrent = pzem.current();
  const float newPower = pzem.power();
  const float newEnergy = pzem.energy();

  pzemValid =
      !isnan(newVoltage) && !isnan(newCurrent) &&
      !isnan(newPower) && !isnan(newEnergy);
  if (pzemValid) {
    voltage = max(0.0f, newVoltage * PZEM_VOLTAGE_MULTIPLIER);
    current = max(0.0f, newCurrent * PZEM_CURRENT_MULTIPLIER);
    power = max(0.0f, newPower * PZEM_POWER_MULTIPLIER);
    energy = max(0.0f, newEnergy * PZEM_ENERGY_MULTIPLIER);
  }

  const float newTemperature = dht.readTemperature();
  const float newHumidity = dht.readHumidity();
  dhtValid = !isnan(newTemperature) && !isnan(newHumidity);
  if (dhtValid) {
    temperature = newTemperature + DHT_TEMPERATURE_OFFSET_C;
    humidity = constrain(
        newHumidity + DHT_HUMIDITY_OFFSET_PERCENT,
        0.0f,
        100.0f);
  }

  gasValue = analogRead(MQ2_PIN);
  motionDetected = digitalRead(PIR_PIN) == HIGH;
}

void updateHazardFilter(
    HazardFilter& filter,
    bool dangerousNow,
    bool safelyRecoveredNow) {
  if (!filter.active) {
    filter.goodStreak = 0;
    if (dangerousNow) {
      if (filter.badStreak < 255) filter.badStreak++;
      if (filter.badStreak >= HAZARD_CONFIRM_READINGS) {
        filter.active = true;
        filter.badStreak = 0;
        Serial.println("SAFETY: hazard confirmed after stable readings");
      }
    } else {
      filter.badStreak = 0;
    }
    return;
  }

  filter.badStreak = 0;
  if (safelyRecoveredNow) {
    if (filter.goodStreak < 255) filter.goodStreak++;
    if (filter.goodStreak >= HAZARD_CLEAR_READINGS) {
      filter.active = false;
      filter.goodStreak = 0;
      Serial.println("SAFETY: hazard recovered after stable safe readings");
    }
  } else {
    filter.goodStreak = 0;
  }
}

bool confirmedSafetyHazardActive() {
  return
      sensorFailureFilter.active ||
      gasHazardFilter.active ||
      temperatureHazardFilter.active ||
      powerHazardFilter.active ||
      voltageHazardFilter.active;
}

uint8_t confirmedHazardMask() {
  uint8_t result = 0;
  if (sensorFailureFilter.active && !pzemValid) result |= HAZARD_PZEM;
  if (sensorFailureFilter.active && !dhtValid) result |= HAZARD_DHT;
  if (gasHazardFilter.active) result |= HAZARD_GAS;
  if (temperatureHazardFilter.active) result |= HAZARD_TEMPERATURE;
  if (powerHazardFilter.active) result |= HAZARD_POWER;
  if (voltageHazardFilter.active) result |= HAZARD_VOLTAGE;
  return result;
}

void updateSafetyLogic() {
  const bool sensorFailureNow = !pzemValid || !dhtValid;
  const bool gasHazardNow = gasValue >= gasWarningThresholdRaw;
  const bool gasRecoveredNow =
      gasValue < max(0, gasWarningThresholdRaw - GAS_RECOVERY_MARGIN_RAW);
  const bool temperatureHazardNow =
      dhtValid && temperature >= TEMPERATURE_DANGER_C;
  const bool temperatureRecoveredNow =
      dhtValid && temperature < TEMPERATURE_RECOVERY_C;
  const bool powerHazardNow = pzemValid && power >= POWER_WARNING_W;
  const bool powerRecoveredNow = pzemValid && power < POWER_RECOVERY_W;
  const bool voltageHazardNow =
      pzemValid &&
      (voltage < VOLTAGE_LOW_WARNING_V || voltage > VOLTAGE_HIGH_WARNING_V);
  const bool voltageRecoveredNow =
      pzemValid &&
      voltage >= VOLTAGE_LOW_RECOVERY_V &&
      voltage <= VOLTAGE_HIGH_RECOVERY_V;

  updateHazardFilter(
      sensorFailureFilter, sensorFailureNow, !sensorFailureNow);
  updateHazardFilter(
      gasHazardFilter, gasHazardNow, gasRecoveredNow);
  updateHazardFilter(
      temperatureHazardFilter,
      temperatureHazardNow,
      temperatureRecoveredNow);
  updateHazardFilter(
      powerHazardFilter, powerHazardNow, powerRecoveredNow);
  updateHazardFilter(
      voltageHazardFilter, voltageHazardNow, voltageRecoveredNow);

  const bool confirmedHazard = confirmedSafetyHazardActive();
  if (confirmedHazard) {
    safetyLockLatched = true;
  }
  systemSafe = !confirmedHazard;
  if (remoteDemoAlertActive &&
      static_cast<long>(millis() - remoteDemoAlertUntil) >= 0) {
    remoteDemoAlertActive = false;
  }
  theftMotionAlert = theftMonitoringActive && motionDetected;
  // Presentation alerts and theft monitoring exercise the red LED/buzzer,
  // but only a confirmed electrical/sensor hazard locks the load relay.
  alertActive = confirmedHazard || remoteDemoAlertActive || theftMotionAlert;

  // A confirmed hazard opens the relay immediately. Restoration stays
  // locked until the reading is safely recovered and the dashboard alert
  // has been acknowledged (reported through the command endpoint).
  if (!systemSafe || safetyLockLatched || remoteSafetyLocked) {
    manualRelayRequested = false;
  }
  applyRelayOutput();
  updateIndicators();
  updateAlertBuzzer();
}

void handleRelayButton() {
  const int reading = digitalRead(BUTTON_PIN);
  const unsigned long now = millis();

  if (reading != lastButtonReading) {
    lastButtonChangeAt = now;
    lastButtonReading = reading;
  }

  if (now - lastButtonChangeAt < BUTTON_DEBOUNCE_MS) return;
  if (reading == stableButtonState) return;

  stableButtonState = reading;
  if (stableButtonState != LOW) return;

  if (!ENABLE_LOAD_RELAY) {
    manualRelayRequested = false;
    applyRelayOutput();
    Serial.println("BUTTON: Relay locked by config");
    return;
  }

  if (!systemSafe) {
    manualRelayRequested = false;
    applyRelayOutput();
    Serial.println("BUTTON: Relay blocked by safety condition");
    return;
  }

  if (safetyLockLatched || remoteSafetyLocked) {
    manualRelayRequested = false;
    applyRelayOutput();
    Serial.println("BUTTON: Relay blocked - acknowledge safety alert");
    return;
  }

  if (!creditAllowed) {
    manualRelayRequested = false;
    applyRelayOutput();
    Serial.println("BUTTON: Relay blocked - recharge required");
    return;
  }

  manualRelayRequested = !manualRelayRequested;
  applyRelayOutput();
  updateIndicators();
  Serial.print("BUTTON: Relay toggled ");
  Serial.println(relayState ? "ON" : "OFF");
}

// ================= WIFI AND API =================
void beginWiFi() {
  WiFi.mode(WIFI_STA);
  WiFi.setAutoReconnect(true);
  WiFi.persistent(false);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  lastWiFiRetryAt = millis();
}

void maintainWiFi() {
  if (WiFi.status() == WL_CONNECTED) return;
  apiConnected = false;
  if (millis() - lastWiFiRetryAt < WIFI_RETRY_INTERVAL_MS) return;
  lastWiFiRetryAt = millis();
  WiFi.disconnect();
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
}

SensorSnapshot captureSnapshot() {
  const uint8_t hazardMask = confirmedHazardMask();
  return {
      voltage,
      current,
      power,
      energy,
      temperature,
      humidity,
      gasValue,
      motionDetected,
      relayState,
      pzemValid,
      dhtValid,
      hazardMask != 0,
      hazardMask};
}

String confirmedHazardsJson(uint8_t mask) {
  String result = "[";
  bool hasValue = false;
  auto append = [&](const char* name) {
    if (hasValue) result += ',';
    result += '\"';
    result += name;
    result += '\"';
    hasValue = true;
  };
  if (mask & HAZARD_PZEM) append("sensor_pzem");
  if (mask & HAZARD_DHT) append("sensor_dht");
  if (mask & HAZARD_GAS) append("gas");
  if (mask & HAZARD_TEMPERATURE) append("temperature");
  if (mask & HAZARD_POWER) append("power");
  if (mask & HAZARD_VOLTAGE) append("voltage");
  result += ']';
  return result;
}

void queueSnapshot(const SensorSnapshot& snapshot) {
  if (offlineQueueCount == OFFLINE_QUEUE_CAPACITY) {
    // The meter values are cumulative, so discarding the oldest sample does
    // not lose the final energy total after a long outage.
    offlineQueueHead =
        (offlineQueueHead + 1) % OFFLINE_QUEUE_CAPACITY;
    offlineQueueCount--;
    Serial.println("OFFLINE QUEUE: oldest reading replaced");
  }
  const uint8_t tail =
      (offlineQueueHead + offlineQueueCount) % OFFLINE_QUEUE_CAPACITY;
  offlineQueue[tail] = snapshot;
  offlineQueueCount++;
}

bool sendSnapshot(const SensorSnapshot& snapshot, bool queued) {
  const String confirmedHazards =
      confirmedHazardsJson(snapshot.confirmedHazardMask);
  char payload[760];
  snprintf(
      payload,
      sizeof(payload),
      "{\"voltage\":%.2f,\"current\":%.3f,\"power\":%.2f,"
      "\"energy\":%.5f,\"temperature\":%.2f,\"humidity\":%.2f,"
      "\"gas\":%d,\"motion\":%s,\"relay\":%s,"
      "\"pzem_valid\":%s,\"dht_valid\":%s,"
      "\"safety_confirmed\":%s,\"confirmed_hazards\":%s,"
      "\"queued_after_outage\":%s}",
      snapshot.voltage,
      snapshot.current,
      snapshot.power,
      snapshot.energy,
      snapshot.temperature,
      snapshot.humidity,
      snapshot.gas,
      snapshot.motion ? "true" : "false",
      snapshot.relay ? "true" : "false",
      snapshot.pzemValid ? "true" : "false",
      snapshot.dhtValid ? "true" : "false",
      snapshot.safetyConfirmed ? "true" : "false",
      confirmedHazards.c_str(),
      queued ? "true" : "false");

  WiFiClient client;
  HTTPClient http;
  http.setConnectTimeout(3000);
  http.setTimeout(5000);
  if (!http.begin(client, API_READING_URL)) {
    apiConnected = false;
    lastApiDetail = "HTTP begin failed";
    return false;
  }
  http.addHeader("Content-Type", "application/json");
  http.addHeader("X-Device-Key", DEVICE_API_KEY);
  lastHttpCode = http.POST(reinterpret_cast<uint8_t*>(payload), strlen(payload));
  const String response = http.getString();
  http.end();

  apiConnected = lastHttpCode >= 200 && lastHttpCode < 300;
  lastApiDetail = "HTTP " + String(lastHttpCode);
  Serial.print("API: ");
  Serial.print(lastHttpCode);
  if (response.length() > 0) {
    Serial.print(" ");
    Serial.println(response);
  } else {
    Serial.println();
  }
  updateIndicators();
  return apiConnected;
}

bool uploadReading() {
  // Keep a small RAM queue during brief Wi-Fi/API outages. The backend still
  // samples cloud persistence every minute, so replay does not flood Firestore.
  const SensorSnapshot currentSnapshot = captureSnapshot();
  if (WiFi.status() != WL_CONNECTED) {
    apiConnected = false;
    lastApiDetail = "Queued: WiFi disconnected";
    queueSnapshot(currentSnapshot);
    return false;
  }

  uint8_t flushed = 0;
  while (
      offlineQueueCount > 0 &&
      flushed < OFFLINE_FLUSH_PER_CYCLE) {
    if (!sendSnapshot(offlineQueue[offlineQueueHead], true)) {
      queueSnapshot(currentSnapshot);
      return false;
    }
    offlineQueueHead =
        (offlineQueueHead + 1) % OFFLINE_QUEUE_CAPACITY;
    offlineQueueCount--;
    flushed++;
  }

  if (!sendSnapshot(currentSnapshot, false)) {
    queueSnapshot(currentSnapshot);
    return false;
  }
  if (flushed > 0) {
    Serial.printf(
        "OFFLINE QUEUE: uploaded %u | %u remaining\n",
        flushed,
        offlineQueueCount);
  }
  return true;
}

String jsonStringValue(const String& json, const String& key) {
  const String marker = "\"" + key + "\":\"";
  const int start = json.indexOf(marker);
  if (start < 0) return "";
  const int valueStart = start + marker.length();
  const int valueEnd = json.indexOf("\"", valueStart);
  if (valueEnd < 0) return "";
  return json.substring(valueStart, valueEnd);
}

float jsonNumberValue(
    const String& json,
    const String& key,
    float fallback) {
  const String marker = "\"" + key + "\":";
  const int start = json.indexOf(marker);
  if (start < 0) return fallback;

  int valueStart = start + marker.length();
  while (valueStart < json.length() && json[valueStart] == ' ') {
    valueStart++;
  }
  int valueEnd = valueStart;
  while (
      valueEnd < json.length() &&
      json[valueEnd] != ',' &&
      json[valueEnd] != '}') {
    valueEnd++;
  }
  if (valueEnd <= valueStart) return fallback;
  return json.substring(valueStart, valueEnd).toFloat();
}

bool fetchDisplaySummary() {
  if (WiFi.status() != WL_CONNECTED) {
    displayApiValid = false;
    return false;
  }

  WiFiClient client;
  HTTPClient http;
  http.setConnectTimeout(3000);
  http.setTimeout(5000);
  if (!http.begin(client, API_DISPLAY_URL)) {
    displayApiValid = false;
    return false;
  }
  http.addHeader("X-Device-Key", DEVICE_API_KEY);
  const int httpCode = http.GET();
  const String response = http.getString();
  http.end();

  if (httpCode < 200 || httpCode >= 300) {
    displayApiValid = false;
    Serial.print("DISPLAY API: HTTP ");
    Serial.print(httpCode);
    if (response.length() > 0) {
      Serial.print(" ");
      Serial.println(response);
    } else {
      Serial.println();
    }
    return false;
  }

  displayForecastKwh =
      jsonNumberValue(response, "tomorrow_usage_kwh", 0.0);
  displayEstimatedCostLkr =
      jsonNumberValue(response, "estimated_cost_lkr", 0.0);
  displayRemainingDays =
      jsonNumberValue(response, "remaining_days", 0.0);
  displayRemainingDaysReady =
      response.indexOf("\"remaining_days_ready\":true") >= 0;
  displayBalanceLkr =
      jsonNumberValue(response, "balance_lkr", 0.0);
  displaySavingPercent =
      static_cast<int>(
          jsonNumberValue(response, "potential_saving_percent", 0.0));
  displayAccountStatus =
      jsonStringValue(response, "account_status");
  displayRecommendation1 =
      jsonStringValue(response, "recommendation_line_1");
  displayRecommendation2 =
      jsonStringValue(response, "recommendation_line_2");
  displayRecommendationImpact =
      jsonStringValue(response, "recommendation_impact");
  displayApiValid = true;
  Serial.printf(
      "DISPLAY API: summary updated | Forecast %.2f kWh | "
      "Balance Rs. %.2f | %.1f days\n",
      displayForecastKwh,
      displayBalanceLkr,
      displayRemainingDays);
  return true;
}

bool fetchRelayCommand() {
  if (WiFi.status() != WL_CONNECTED) return false;

  WiFiClient client;
  HTTPClient http;
  http.setConnectTimeout(3000);
  http.setTimeout(5000);
  if (!http.begin(client, API_COMMAND_URL)) {
    return false;
  }
  http.addHeader("X-Device-Key", DEVICE_API_KEY);
  const int httpCode = http.GET();
  const String response = http.getString();
  http.end();

  if (httpCode < 200 || httpCode >= 300) {
    Serial.print("COMMAND: HTTP ");
    Serial.println(httpCode);
    return false;
  }

  creditAllowed = response.indexOf("\"credit_allowed\":false") < 0;
  theftMonitoringActive =
      response.indexOf("\"theft_monitoring_active\":true") >= 0;
  const bool serverSafetyLocked =
      response.indexOf("\"safety_locked\":true") >= 0;
  if (serverSafetyLocked) {
    remoteSafetyLocked = true;
    safetyLockLatched = true;
    safetyLockSeenByServer = true;
    manualRelayRequested = false;
    applyRelayOutput();
    updateIndicators();
  } else {
    if (
        safetyLockSeenByServer &&
        !confirmedSafetyHazardActive()) {
      remoteSafetyLocked = false;
      safetyLockLatched = false;
      safetyLockSeenByServer = false;
      Serial.println("SAFETY: acknowledged/recovered - relay lock cleared");
    } else if (!safetyLockLatched) {
      remoteSafetyLocked = false;
    }
  }
  if (!creditAllowed) {
    if (manualRelayRequested || relayState) {
      Serial.println("COMMAND: Relay forced OFF - recharge required");
    }
    manualRelayRequested = false;
    applyRelayOutput();
    updateIndicators();
  }

  if (response.indexOf("\"has_command\":true") < 0) {
    return false;
  }

  const String commandId = jsonStringValue(response, "command_id");
  if (commandId.length() == 0 || commandId == lastRelayCommandId) {
    return false;
  }

  lastRelayCommandId = commandId;
  if (response.indexOf("\"demo_buzzer\":true") >= 0) {
    const unsigned long durationMs = static_cast<unsigned long>(
        max(1.0f, jsonNumberValue(response, "demo_duration_seconds", 8.0f)) *
        1000.0f);
    remoteDemoAlertActive = true;
    remoteDemoAlertUntil = millis() + durationMs;
    alertActive = true;
    updateIndicators();
    updateAlertBuzzer();
    Serial.println("SIMULATION: Red LED and buzzer activated");
  } else if (response.indexOf("\"demo_buzzer\":false") >= 0) {
    remoteDemoAlertActive = false;
    updateSafetyLogic();
    Serial.println("SIMULATION: Indicators cleared");
  }
  const bool requestedOn =
      response.indexOf("\"relay_requested\":true") >= 0;

  if (requestedOn && !creditAllowed) {
    manualRelayRequested = false;
    applyRelayOutput();
    Serial.println("COMMAND: ON blocked - recharge required");
    return false;
  }

  if (requestedOn && !systemSafe) {
    manualRelayRequested = false;
    applyRelayOutput();
    Serial.println("COMMAND: ON blocked by safety condition");
    return false;
  }

  if (requestedOn && (safetyLockLatched || remoteSafetyLocked)) {
    manualRelayRequested = false;
    applyRelayOutput();
    Serial.println("COMMAND: ON blocked - acknowledge safety alert");
    return false;
  }

  manualRelayRequested = requestedOn;
  applyRelayOutput();
  updateIndicators();
  Serial.print("COMMAND: Relay requested ");
  Serial.println(requestedOn ? "ON" : "OFF");
  return true;
}

// ================= DISPLAY =================
String gasStatus() {
  if (gasValue < gasWarningThresholdRaw) return "SAFE";
  if (gasValue < gasDangerThresholdRaw) return "WARNING";
  return "DANGER";
}

uint16_t gasColor() {
  if (gasValue < gasWarningThresholdRaw) return GREEN;
  if (gasValue < gasDangerThresholdRaw) return ORANGE;
  return RED;
}

String localTimeText() {
  struct tm timeInfo;
  if (!getLocalTime(&timeInfo, 10)) return "--:--";
  char buffer[16];
  strftime(buffer, sizeof(buffer), "%I:%M %p", &timeInfo);
  return String(buffer);
}

String cloudStatusText() {
  if (WiFi.status() != WL_CONNECTED) return "OFFLINE";
  return apiConnected ? "ONLINE" : "LOCAL";
}

uint16_t cloudStatusColor() {
  if (WiFi.status() != WL_CONNECTED) return RED;
  return apiConnected ? GREEN : ORANGE;
}

void drawPillRight(const String& text, uint16_t color) {
  int width = 16 + (text.length() * 6);
  if (width < 48) width = 48;
  if (width > 92) width = 92;
  const int x = 310 - width;
  tft.fillRoundRect(x, 8, width, 20, 10, CARD_ALT);
  tft.setTextSize(1);
  tft.setTextColor(color, CARD_ALT);
  tft.setTextDatum(MC_DATUM);
  tft.drawString(text, x + (width / 2), 18);
  tft.setTextDatum(TL_DATUM);
}

void drawFittedText(
    const String& text,
    int x,
    int y,
    int maxWidth,
    int preferredSize,
    uint16_t color,
    uint16_t background,
    uint8_t datum = TL_DATUM) {
  int size = preferredSize;
  tft.setTextSize(size);
  while (size > 1 && tft.textWidth(text) > maxWidth) {
    size--;
    tft.setTextSize(size);
  }
  tft.setTextColor(color, background);
  tft.setTextDatum(datum);
  tft.drawString(text, x, y);
  tft.setTextDatum(TL_DATUM);
}

void beginScreen(
    const char* title,
    const String& badge,
    uint16_t badgeColor) {
  tft.fillScreen(NAVY);
  tft.setTextDatum(TL_DATUM);
  tft.fillRect(0, 0, 4, 36, GREEN);
  tft.setTextColor(WHITE, NAVY);
  tft.setTextSize(2);
  tft.setCursor(12, 10);
  tft.print(title);
  drawPillRight(badge, badgeColor);
  tft.drawFastHLine(10, 36, 300, BORDER);
}

void drawCard(int x, int y, int width, int height) {
  tft.fillRoundRect(x, y, width, height, 9, CARD);
  tft.drawRoundRect(x, y, width, height, 9, BORDER);
}

void drawMetricCard(
    int x,
    int y,
    int width,
    int height,
    const char* label,
    const String& value,
    const char* unit,
    uint16_t color) {
  drawCard(x, y, width, height);
  tft.setTextSize(1);
  tft.setTextColor(GREY, CARD);
  tft.setCursor(x + 10, y + 9);
  tft.print(label);
  tft.setTextSize(2);
  tft.setTextColor(color, CARD);
  drawFittedText(
      value,
      x + 10,
      y + (height < 55 ? 25 : 30),
      width - 20,
      2,
      color,
      CARD);
  if (strlen(unit) > 0) {
    tft.setTextSize(1);
    tft.setTextColor(GREY, CARD);
    tft.setCursor(x + 10, y + height - 14);
    tft.print(unit);
  }
}

void drawStatusRow(
    int y,
    const char* label,
    const String& value,
    uint16_t color) {
  tft.fillRoundRect(10, y, 300, 31, 7, CARD);
  tft.fillCircle(24, y + 15, 4, color);
  tft.setTextSize(1);
  tft.setTextColor(GREY, CARD);
  tft.setCursor(36, y + 12);
  tft.print(label);
  drawFittedText(value, 298, y + 15, 150, 1, color, CARD, MR_DATUM);
}

void drawScreenFooter() {
  tft.drawFastHLine(10, 216, 300, BORDER);
  tft.setTextSize(1);
  tft.setTextColor(GREY, NAVY);
  tft.setCursor(12, 226);
  tft.print("< BACK");

  const int firstDotX = 125;
  for (int i = 0; i < SCREEN_COUNT; i++) {
    const int dotX = firstDotX + (i * 10);
    if (i == currentScreen) {
      tft.fillCircle(dotX, 229, 3, GREEN);
    } else {
      tft.drawCircle(dotX, 229, 2, BORDER);
    }
  }

  drawFittedText("NEXT >", 308, 229, 52, 1, GREEN, NAVY, MR_DATUM);
}

void drawHomeScreen() {
  beginScreen("WATTLY", cloudStatusText(), cloudStatusColor());
  drawCard(10, 44, 300, 58);
  tft.fillRoundRect(20, 54, 38, 38, 9, GREEN);
  tft.setTextColor(NAVY, GREEN);
  tft.setTextSize(3);
  tft.setCursor(29, 62);
  tft.print("W");
  tft.setTextColor(WHITE, CARD);
  tft.setTextSize(2);
  tft.setCursor(70, 55);
  tft.print("SMART ENERGY");
  tft.setTextColor(GREY, CARD);
  tft.setTextSize(1);
  tft.setCursor(70, 79);
  tft.print("PREPAID HOME METER");

  drawMetricCard(
      10, 110, 146, 45, "WI-FI",
      WiFi.status() == WL_CONNECTED ? "Connected" : "Offline",
      "", WiFi.status() == WL_CONNECTED ? GREEN : RED);
  drawMetricCard(
      164, 110, 146, 45, "LOAD",
      relayState ? "ON" : "OFF",
      "", relayState ? GREEN : GREY);
  drawStatusRow(
      163, "SYSTEM STATUS",
      alertActive ? "ATTENTION" : "NORMAL",
      alertActive ? RED : GREEN);
  tft.setTextSize(1);
  tft.setTextColor(CYAN, NAVY);
  tft.setCursor(242, 204);
  tft.print(localTimeText());
  drawScreenFooter();
}

void drawLiveEnergyScreen() {
  beginScreen(
      "LIVE ENERGY",
      pzemValid ? "LIVE" : "SENSOR",
      pzemValid ? GREEN : RED);
  drawMetricCard(
      10, 44, 146, 76, "VOLTAGE",
      pzemValid ? String(voltage, 1) : "--", "volts", GREEN);
  drawMetricCard(
      164, 44, 146, 76, "CURRENT",
      pzemValid ? String(current, 3) : "--", "amperes", CYAN);
  drawMetricCard(
      10, 128, 146, 76, "POWER NOW",
      pzemValid ? String(power, 1) : "--", "watts", ORANGE);
  drawMetricCard(
      164, 128, 146, 76, "TOTAL ENERGY",
      pzemValid ? String(energy, 3) : "--", "units / kWh", WHITE);
  drawScreenFooter();
}

void drawEnvironmentScreen() {
  beginScreen(
      "ENVIRONMENT",
      dhtValid ? "SENSORS" : "CHECK",
      dhtValid ? GREEN : RED);
  drawMetricCard(
      10, 44, 146, 76, "TEMPERATURE",
      dhtValid ? String(temperature, 1) : "--", "degrees C",
      dhtValid ? ORANGE : RED);
  drawMetricCard(
      164, 44, 146, 76, "HUMIDITY",
      dhtValid ? String(humidity, 1) : "--", "percent",
      dhtValid ? CYAN : RED);
  drawStatusRow(
      128, "GAS SENSOR",
      gasStatus() + "  " + String(gasValue), gasColor());
  drawStatusRow(
      167, "MOTION",
      motionDetected ? "DETECTED" : "CLEAR",
      motionDetected ? ORANGE : GREEN);
  drawScreenFooter();
}

void drawAiPredictionScreen() {
  beginScreen(
      "AI FORECAST",
      displayApiValid ? "SYNCED" : "WAITING",
      displayApiValid ? GREEN : ORANGE);
  drawCard(10, 44, 300, 82);
  tft.setTextSize(1);
  tft.setTextColor(GREY, CARD);
  tft.setCursor(22, 55);
  tft.print("TOMORROW'S EXPECTED USAGE");
  tft.setTextSize(displayApiValid ? 3 : 2);
  tft.setTextColor(displayApiValid ? GREEN : ORANGE, CARD);
  tft.setCursor(22, 78);
  tft.print(
      displayApiValid
          ? String(displayForecastKwh, 2) + " kWh"
          : "Waiting for cloud");
  tft.setTextSize(1);
  tft.setTextColor(GREY, CARD);
  tft.setCursor(22, 109);
  tft.print(displayApiValid ? "Updated AI estimate" : "Local sensing continues");

  drawMetricCard(
      10, 134, 146, 66, "BALANCE LEFT",
      displayApiValid && displayRemainingDaysReady
          ? String(displayRemainingDays, 1)
          : (displayApiValid ? "Collecting" : "--"),
      displayApiValid && displayRemainingDaysReady
          ? "measured days"
          : "needs 24h history",
      CYAN);
  drawMetricCard(
      164, 134, 146, 66, "ESTIMATED COST",
      displayApiValid ? "Rs. " + String(displayEstimatedCostLkr, 0) : "--",
      "tomorrow", ORANGE);
  drawScreenFooter();
}

void drawPrepaidScreen() {
  const bool hasCredit = displayApiValid && displayBalanceLkr > 0;
  beginScreen(
      "PREPAID CREDIT",
      hasCredit ? "ACTIVE" : (displayApiValid ? "RECHARGE" : "WAITING"),
      hasCredit ? GREEN : (displayApiValid ? RED : ORANGE));
  drawCard(10, 44, 300, 92);
  tft.setTextSize(1);
  tft.setTextColor(GREY, CARD);
  tft.setCursor(22, 57);
  tft.print("AVAILABLE BALANCE");
  tft.setTextSize(displayApiValid ? 3 : 2);
  tft.setTextColor(hasCredit ? GREEN : (displayApiValid ? RED : ORANGE), CARD);
  tft.setCursor(22, 80);
  tft.print(
      displayApiValid
          ? "Rs. " + String(displayBalanceLkr, 2)
          : "Waiting for account");
  tft.setTextSize(1);
  tft.setTextColor(GREY, CARD);
  tft.setCursor(22, 117);
  tft.print(hasCredit ? "Credit available for electricity" : "Recharge from the Wattly dashboard");

  drawMetricCard(
      10, 144, 146, 58, "ACCOUNT",
      displayApiValid ? displayAccountStatus : "Not synced", "", hasCredit ? GREEN : ORANGE);
  drawMetricCard(
      164, 144, 146, 58, "LOAD PERMISSION",
      creditAllowed ? "Allowed" : "Blocked", "", creditAllowed ? GREEN : RED);
  drawScreenFooter();
}

void drawRecommendationScreen() {
  beginScreen(
      "SMART TIP",
      displayApiValid ? "PERSONAL" : "WAITING",
      displayApiValid ? GREEN : ORANGE);
  drawCard(10, 44, 300, 104);
  tft.fillRoundRect(10, 44, 6, 104, 3, GREEN);
  tft.setTextSize(1);
  tft.setTextColor(GREY, CARD);
  tft.setCursor(28, 57);
  tft.print("AI RECOMMENDATION");
  tft.setTextSize(2);
  tft.setTextColor(WHITE, CARD);
  drawFittedText(
      displayApiValid ? displayRecommendation1 : "Waiting for cloud",
      28, 78, 268, 2, WHITE, CARD);
  drawFittedText(
      displayApiValid ? displayRecommendation2 : "Keep meter online",
      28, 103, 268, 2, GREEN, CARD);
  tft.setTextSize(1);
  tft.setTextColor(GREY, CARD);
  tft.setCursor(28, 133);
  tft.print("Based on usage, balance and safety");

  drawCard(10, 156, 300, 46);
  tft.setTextSize(1);
  tft.setTextColor(GREY, CARD);
  tft.setCursor(22, 166);
  bool hasSaving = displaySavingPercent > 0;
  tft.print(hasSaving ? "POTENTIAL SAVING" : "PRIORITY");
  drawFittedText(
      displayApiValid
          ? (hasSaving
                 ? "UP TO " + String(displaySavingPercent) + "%"
                 : displayRecommendationImpact)
          : "--",
      296, 179, 126, 2, CYAN, CARD, MR_DATUM);
  drawScreenFooter();
}

void drawSafetyScreen() {
  const bool healthy = systemSafe && !alertActive;
  beginScreen(
      "SAFETY",
      healthy ? "HEALTHY" : "ATTENTION",
      healthy ? GREEN : RED);
  drawCard(10, 44, 300, 48);
  tft.fillCircle(33, 68, 12, healthy ? GREEN : RED);
  tft.setTextSize(2);
  tft.setTextColor(NAVY, healthy ? GREEN : RED);
  tft.setCursor(27, 61);
  tft.print(healthy ? "OK" : "!");
  tft.setTextColor(healthy ? GREEN : RED, CARD);
  tft.setCursor(56, 61);
  tft.print(healthy ? "SYSTEM HEALTHY" : "CHECK REQUIRED");

  drawStatusRow(
      100, "GAS",
      gasValue < gasWarningThresholdRaw ? "SAFE" : gasStatus(),
      gasValue < gasWarningThresholdRaw ? GREEN : gasColor());
  drawStatusRow(
      137, "TEMPERATURE",
      dhtValid && temperature < TEMPERATURE_DANGER_C ? "NORMAL" : "CHECK",
      dhtValid && temperature < TEMPERATURE_DANGER_C ? GREEN : RED);
  drawStatusRow(
      174, "ELECTRICAL LOAD",
      pzemValid && power < POWER_WARNING_W ? "NORMAL" : "CHECK",
      pzemValid && power < POWER_WARNING_W ? GREEN : RED);
  drawScreenFooter();
}

void drawAboutScreen() {
  beginScreen("ABOUT", "V1.0", GREEN);
  drawCard(10, 44, 300, 62);
  tft.fillRoundRect(20, 54, 42, 42, 10, GREEN);
  tft.setTextColor(NAVY, GREEN);
  tft.setTextSize(3);
  tft.setCursor(30, 62);
  tft.print("W");
  tft.setTextColor(WHITE, CARD);
  tft.setTextSize(2);
  tft.setCursor(76, 55);
  tft.print("WATTLY");
  tft.setTextSize(1);
  tft.setTextColor(GREY, CARD);
  tft.setCursor(76, 81);
  tft.print("AI SMART PREPAID METER");

  drawStatusRow(114, "CONTROLLER", "ESP32", GREEN);
  drawStatusRow(151, "ENERGY METER", "PZEM-004T", CYAN);
  drawCard(10, 188, 300, 20);
  tft.setTextSize(1);
  tft.setTextColor(GREY, CARD);
  tft.setCursor(20, 195);
  tft.print("NIBM FINAL PROJECT");
  tft.setTextColor(GREEN, CARD);
  tft.setCursor(240, 195);
  tft.print("HNDSE25.1P");
  drawScreenFooter();
}

void drawCurrentScreen() {
  // Keep the index valid even if electrical noise or a future code change
  // modifies it unexpectedly.
  currentScreen =
      ((currentScreen % SCREEN_COUNT) + SCREEN_COUNT) % SCREEN_COUNT;
  // Keep chip select active through the complete frame. This makes the
  // refresh faster and reduces visible flicker during live updates.
  tft.startWrite();
  switch (currentScreen) {
    case 0: drawHomeScreen(); break;
    case 1: drawLiveEnergyScreen(); break;
    case 2: drawEnvironmentScreen(); break;
    case 3: drawAiPredictionScreen(); break;
    case 4: drawPrepaidScreen(); break;
    case 5: drawRecommendationScreen(); break;
    case 6: drawSafetyScreen(); break;
    case 7: drawAboutScreen(); break;
    default: drawHomeScreen(); break;
  }
  tft.endWrite();
}

void drawMq2CalibrationProgress(int completed, int total) {
  const int barX = 22;
  const int barY = 144;
  const int barWidth = 276;
  const int filled = (barWidth - 4) * completed / total;
  tft.drawRoundRect(barX, barY, barWidth, 18, 7, BORDER);
  tft.fillRoundRect(barX + 2, barY + 2, barWidth - 4, 14, 5, CARD_ALT);
  if (filled > 0) {
    tft.fillRoundRect(barX + 2, barY + 2, filled, 14, 5, GREEN);
  }
}

void calibrateMq2CleanAir() {
  // Calibration must never leave the load or buzzer energized.
  manualRelayRequested = false;
  applyRelayOutput();
  digitalWrite(BUZZER_PIN, BUZZER_OFF);

  beginScreen("SENSOR CAL", "MQ-2", CYAN);
  drawCard(10, 44, 300, 112);
  tft.setTextColor(WHITE, CARD);
  tft.setTextSize(2);
  tft.setCursor(22, 58);
  tft.print("Clean-air baseline");
  tft.setTextSize(1);
  tft.setTextColor(GREY, CARD);
  tft.setCursor(22, 91);
  tft.print("Keep gas, smoke and alcohol away.");
  tft.setCursor(22, 108);
  tft.print("Sampling for about 5 seconds...");
  drawMq2CalibrationProgress(0, MQ2_CALIBRATION_SAMPLES);
  drawScreenFooter();

  int samples[MQ2_CALIBRATION_SAMPLES];
  for (int i = 0; i < MQ2_CALIBRATION_SAMPLES; i++) {
    samples[i] = analogRead(MQ2_PIN);
    if (i % 5 == 0 || i == MQ2_CALIBRATION_SAMPLES - 1) {
      drawMq2CalibrationProgress(i + 1, MQ2_CALIBRATION_SAMPLES);
    }
    delay(50);
    yield();
  }

  // Median filtering rejects occasional ADC spikes during calibration.
  for (int i = 1; i < MQ2_CALIBRATION_SAMPLES; i++) {
    const int value = samples[i];
    int j = i - 1;
    while (j >= 0 && samples[j] > value) {
      samples[j + 1] = samples[j];
      j--;
    }
    samples[j + 1] = value;
  }
  const int baseline = samples[MQ2_CALIBRATION_SAMPLES / 2];
  const bool plausible = baseline >= 50 && baseline < GAS_WARNING_RAW;

  if (plausible) {
    mq2CleanAirBaselineRaw = baseline;
    calibrationPreferences.putInt("mq2base", mq2CleanAirBaselineRaw);
    updateMq2Thresholds();
  }

  beginScreen(
      "SENSOR CAL",
      plausible ? "SAVED" : "REJECTED",
      plausible ? GREEN : RED);
  drawCard(10, 44, 300, 136);
  tft.setTextSize(1);
  tft.setTextColor(GREY, CARD);
  tft.setCursor(22, 58);
  tft.print("MQ-2 CLEAN-AIR BASELINE");
  tft.setTextSize(3);
  tft.setTextColor(plausible ? GREEN : RED, CARD);
  tft.setCursor(22, 78);
  tft.print(baseline);
  tft.setTextSize(1);
  tft.setTextColor(WHITE, CARD);
  tft.setCursor(22, 119);
  if (plausible) {
    tft.printf(
        "Warning %d   Danger %d",
        gasWarningThresholdRaw,
        gasDangerThresholdRaw);
    tft.setCursor(22, 142);
    tft.setTextColor(GREY, CARD);
    tft.print("Saved in ESP32 memory");
  } else {
    tft.print("Not saved: air is not clean or sensor fault");
    tft.setCursor(22, 142);
    tft.setTextColor(GREY, CARD);
    tft.print("Check MQ-2 wiring and try in clean air");
  }
  drawScreenFooter();

  Serial.printf(
      "MQ-2 CALIBRATION: %s | baseline %d | warning %d | danger %d\n",
      plausible ? "SAVED" : "REJECTED",
      baseline,
      gasWarningThresholdRaw,
      gasDangerThresholdRaw);
  delay(2500);
  drawCurrentScreen();
}

bool handleCalibrationShortcut() {
  const bool bothPressed =
      digitalRead(LEFT_BUTTON_PIN) == LOW &&
      digitalRead(RIGHT_BUTTON_PIN) == LOW;
  const unsigned long now = millis();

  if (!bothPressed) {
    calibrationButtonsHeldAt = 0;
    calibrationComboHandled = false;
    return false;
  }

  if (calibrationButtonsHeldAt == 0) {
    calibrationButtonsHeldAt = now;
    Serial.println(
        "CALIBRATION: keep both screen buttons held for 3 seconds");
  }

  if (
      !calibrationComboHandled &&
      now - calibrationButtonsHeldAt >= CALIBRATION_HOLD_MS) {
    calibrationComboHandled = true;
    calibrateMq2CleanAir();
  }
  return true;
}

bool navigationButtonPressed(NavigationButtonState& button) {
  const int reading = digitalRead(button.pin);
  const unsigned long now = millis();

  if (reading != button.lastReading) {
    button.lastReading = reading;
    button.changedAt = now;
    return false;
  }

  const unsigned long stableFor = now - button.changedAt;
  if (reading == HIGH) {
    button.pressHandled = false;
    if (stableFor >= NAV_RELEASE_ARM_MS) {
      button.armed = true;
    }
    return false;
  }

  if (
      !button.armed ||
      button.pressHandled ||
      stableFor < NAV_PRESS_CONFIRM_MS) {
    return false;
  }

  // One screen change per deliberate press. A stable release is required
  // before this button can become armed again.
  button.pressHandled = true;
  button.armed = false;
  return true;
}

void handleScreenButtons() {
  if (handleCalibrationShortcut()) return;

  const bool leftPressed = navigationButtonPressed(leftNavigation);
  const bool rightPressed = navigationButtonPressed(rightNavigation);
  const unsigned long now = millis();

  // Simultaneous presses usually mean supply noise or incorrect wiring.
  // Ignore them instead of changing the screen.
  if (leftPressed && rightPressed) {
    Serial.println("SCREEN BUTTONS: simultaneous input ignored");
    return;
  }

  if (
      !leftPressed &&
      !rightPressed) {
    return;
  }

  if (now - lastNavigationAt < NAV_CHANGE_COOLDOWN_MS) {
    Serial.println("SCREEN BUTTONS: rapid input ignored");
    return;
  }
  lastNavigationAt = now;

  if (leftPressed) {
    currentScreen =
        (currentScreen + SCREEN_COUNT - 1) % SCREEN_COUNT;
    drawCurrentScreen();
    Serial.print("SCREEN: ");
    Serial.println(currentScreen + 1);
  }
  if (rightPressed) {
    currentScreen = (currentScreen + 1) % SCREEN_COUNT;
    drawCurrentScreen();
    Serial.print("SCREEN: ");
    Serial.println(currentScreen + 1);
  }
}

// ================= SERIAL =================
void printSerial() {
  Serial.println("----------------");
  Serial.printf(
      "PZEM: %s | Voltage: %.2f V | Current: %.3f A | "
      "Power: %.2f W | Energy: %.5f kWh\n",
      pzemValid ? "OK" : "ERROR",
      voltage, current, power, energy);
  Serial.printf(
      "DHT: %s | Temp: %.2f C | Humidity: %.2f %%\n",
      dhtValid ? "OK" : "ERROR", temperature, humidity);
  Serial.printf(
      "Gas: %d (base %d / warn %d / danger %d) | Motion: %s | "
      "Relay: %s | WiFi: %s | API: %s\n",
      gasValue,
      mq2CleanAirBaselineRaw,
      gasWarningThresholdRaw,
      gasDangerThresholdRaw,
      motionDetected ? "Detected" : "No Motion",
      relayState ? "ON" : "OFF",
      WiFi.status() == WL_CONNECTED ? "Connected" : "Disconnected",
      apiConnected ? "Synced" : "Offline");
  Serial.print("API detail: ");
  Serial.println(lastApiDetail);
  Serial.printf(
      "Indicators: Blue/WiFi %s | Green/Load %s | "
      "Red/Alert %s | Alert buzzer %s\n",
      WiFi.status() == WL_CONNECTED ? "ON" : "OFF",
      relayState ? "ON" : "OFF",
      alertActive ? "ON" : "OFF",
      alertActive ? "TRIGGERED" : "READY");
  if (power >= POWER_WARNING_W) {
    Serial.println("WARNING: HIGH POWER");
  }
}

// ================= SETUP / LOOP =================
void setup() {
  Serial.begin(115200);
  Serial.println(FIRMWARE_VERSION);

  pinMode(MQ2_PIN, INPUT);
  pinMode(PIR_PIN, INPUT);
  pinMode(BUTTON_PIN, INPUT_PULLUP);
  // GPIO19 and GPIO15 support internal pull-ups. Each navigation button
  // connects its GPIO directly to GND when pressed.
  pinMode(LEFT_BUTTON_PIN, INPUT_PULLUP);
  pinMode(RIGHT_BUTTON_PIN, INPUT_PULLUP);
  pinMode(RELAY_PIN, OUTPUT);
  pinMode(BLUE_LED, OUTPUT);
  pinMode(GREEN_LED, OUTPUT);
  pinMode(RED_LED, OUTPUT);
  pinMode(BUZZER_PIN, OUTPUT);

  // Fail-safe state before sensors and networking initialize.
  digitalWrite(RELAY_PIN, RELAY_OFF);
  digitalWrite(BLUE_LED, LOW);
  digitalWrite(GREEN_LED, LOW);
  digitalWrite(RED_LED, LOW);
  digitalWrite(BUZZER_PIN, BUZZER_OFF);

  runOutputSelfTest();

  pzemSerial.begin(9600, SERIAL_8N1, PZEM_RX_PIN, PZEM_TX_PIN);
  dht.begin();
  analogReadResolution(12);
  loadStoredCalibration();

  tft.init();
  tft.setRotation(1);
  tft.setTextWrap(false);
  tft.fillScreen(NAVY);
  tft.fillRoundRect(38, 58, 244, 116, 14, CARD);
  tft.drawRoundRect(38, 58, 244, 116, 14, BORDER);
  tft.fillRoundRect(54, 76, 48, 48, 11, GREEN);
  tft.setTextColor(NAVY, GREEN);
  tft.setTextSize(3);
  tft.setCursor(66, 85);
  tft.print("W");
  tft.setTextColor(WHITE, CARD);
  tft.setTextSize(3);
  tft.setCursor(116, 75);
  tft.print("WATTLY");
  tft.setTextColor(GREY, CARD);
  tft.setTextSize(1);
  tft.setCursor(117, 111);
  tft.print("SMART ENERGY METER");
  tft.fillRoundRect(54, 145, 212, 5, 2, BORDER);
  tft.fillRoundRect(54, 145, 92, 5, 2, GREEN);
  tft.setTextColor(GREY, CARD);
  tft.setCursor(107, 157);
  tft.print("STARTING SYSTEM");

  beginWiFi();
  // Sri Lanka Standard Time: UTC +05:30.
  configTime(19800, 0, "pool.ntp.org", "time.nist.gov");
}

void loop() {
  maintainWiFi();
  handleRelayButton();
  handleScreenButtons();
  updateIndicators();
  updateAlertBuzzer();
  const unsigned long now = millis();

  if (now - lastSampleAt >= SAMPLE_INTERVAL_MS || lastSampleAt == 0) {
    lastSampleAt = now;
    readSensors();
    updateSafetyLogic();
    printSerial();
    drawCurrentScreen();
  }

  if (now - lastApiAt >= API_INTERVAL_MS || lastApiAt == 0) {
    lastApiAt = now;
    uploadReading();
  }

  if (now - lastCommandAt >= COMMAND_INTERVAL_MS || lastCommandAt == 0) {
    lastCommandAt = now;
    fetchRelayCommand();
  }

  if (
      now - lastDisplayApiAt >=
          (displayApiValid
               ? DISPLAY_API_INTERVAL_MS
               : DISPLAY_API_RETRY_MS) ||
      lastDisplayApiAt == 0) {
    lastDisplayApiAt = now;
    if (fetchDisplaySummary()) {
      drawCurrentScreen();
    }
  }

  delay(20);
}
