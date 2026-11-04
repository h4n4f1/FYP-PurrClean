/*
 * PurrClean - Smart Cat Litter Box Ventilation, BLE Provisioning & Remote Management
 * ---------------------------------------------------------------------------------
 * - Power plugged in -> forgets Wi-Fi, starts BLE setup mode
 * - No saved Wi-Fi    -> advertises as "PROV_PURRCLEAN_XXXX"
 * - Saved Wi-Fi       -> connects automatically
 * - Online            -> syncs NTP time, tells app it is set up, heartbeat every minute
 * - Online            -> polls Firebase every 5 s for commands (resetWifi, hardReset, fan control)
 * - Sensors           -> measures Cat Weight, Dwell Time, Deposit (Delta Wt), NH3 ppm, Odor %
 * - Event Logging     -> pushes complete visit event to /devices/{deviceId}/events/{timestamp_id}
 * - Fan Control       -> pushes status to /devices/{deviceId}/fan (auto_mode, is_running)
 * - Hold BOOT (GPIO 0) 5 s -> hard reset.
 */

#include <Arduino.h>
#include <math.h>
#include <time.h>
#include <sys/time.h>
#include <WiFi.h>
#include <WiFiProv.h>
#include <HTTPClient.h>
#include <WiFiClientSecure.h>
#include <Preferences.h>
#include <esp_wifi.h>
#include <esp_system.h>
#include <esp_crt_bundle.h>
#include "HX711.h"

// ---- Core Compatibility (ESP-IDF / Arduino-ESP32 v3.x) ---------------------
#if ESP_ARDUINO_VERSION >= ESP_ARDUINO_VERSION_VAL(3, 2, 0)
  #define PROV_SCHEME_BLE   NETWORK_PROV_SCHEME_BLE
  #define PROV_SECURITY_1   NETWORK_PROV_SECURITY_1
  #define PROV_HANDLER_BTDM NETWORK_PROV_SCHEME_HANDLER_FREE_BTDM
  #define PROV_HANDLER_BLE  NETWORK_PROV_SCHEME_HANDLER_FREE_BLE
#else
  #define PROV_SCHEME_BLE   WIFI_PROV_SCHEME_BLE
  #define PROV_SECURITY_1   WIFI_PROV_SECURITY_1
  #define PROV_HANDLER_BTDM WIFI_PROV_SCHEME_HANDLER_FREE_BTDM
  #define PROV_HANDLER_BLE  WIFI_PROV_SCHEME_HANDLER_FREE_BLE
#endif

// Force BLE-only handler to avoid Bluetooth Classic memory panics on ESP32
#define PROV_HANDLER PROV_HANDLER_BLE

#if __has_include("network_provisioning/manager.h")
  #include "network_provisioning/manager.h"
  #define PROV_RESET_ON_FAIL() network_prov_mgr_reset_wifi_sm_state_on_failure()
#elif __has_include("wifi_provisioning/manager.h")
  #include "wifi_provisioning/manager.h"
  #define PROV_RESET_ON_FAIL() wifi_prov_mgr_reset_sm_state_on_failure()
#else
  #define PROV_RESET_ON_FAIL() ((void)0)
#endif
// --------------------------------------------------------------------------

// ---- Config --------------------------------------------------------------
static const char *POP = "purrclean-pop";
static const char *NAME_PREFIX = "PROV_PURRCLEAN";
static const char *DB_URL = "https://purrclean-124-default-rtdb.asia-southeast1.firebasedatabase.app";
static const bool FORGET_WIFI_ON_POWER_CYCLE = false; // Retain Wi-Fi credentials across power cycles!

// Pins
const uint8_t PIR_PIN           = 13;
const uint8_t MQ135_PIN         = 34;
const uint8_t MQ137_PIN         = 35;
const uint8_t RELAY_PIN         = 16;
const uint8_t GREEN_LED         = 27;
const uint8_t RED_LED           = 26;
const uint8_t LOADCELL_DOUT_PIN = 18;
const uint8_t LOADCELL_SCK_PIN  = 19;
const int     RESET_BUTTON_PIN  = 0;

// Settings & Timing
const bool RELAY_ACTIVE_LOW = false;
const unsigned long WARMUP_MS        = 60000UL;
const unsigned long CAT_HOLD_MS      = 10000UL;
const unsigned long SAMPLE_MS        = 500UL;
const unsigned long PRINT_MS         = 2000UL;
const unsigned long RELAY_SETTLE_MS  = 600UL;
const unsigned long PIR_STRETCH_MS   = 3500UL;
const unsigned long RESET_HOLD_MS    = 5000UL;
const unsigned long HEARTBEAT_MS       = 60000UL;
const unsigned long REMOTE_CHECK_MS    = 5000UL;
const unsigned long PROVISIONED_RETRY_MS = 3000UL;
const unsigned long NET_SETTLE_MS      = 2000UL;
const uint32_t      MIN_HEAP_FOR_TLS   = 45000UL;
const unsigned long SETUP_WINDOW_MS    = 300000UL;
const unsigned long CAT_EXIT_CONFIRM_MS = 2500UL; // Wait 2.5s below threshold to confirm cat left
const unsigned long MAX_PURGE_MS       = 180000UL; // Max 3 minutes fan purge

const float VCC_SENSOR   = 5.0;
const float DIVIDER_GAIN = 1.5;
const float RL_MQ135_K   = 10.0;
const float RL_MQ137_K   = 10.0;

static float calibrationFactor = 18.22f; // Matched to user's platform load sensor
const float WEIGHT_EMA_ALPHA   = 0.50f;   // Responsive 50% smoothing
const float WEIGHT_DEADBAND_G  = 20.0f;   // Display 0.0g for small empty box noise
const float CAT_MIN_WEIGHT_G   = 400.0f;  // Safe threshold for cat detection (cats weigh 2kg - 6kg)

const float NH3_REF_PPM       = 50.0;
const float NH3_SLOPE         = -1.8;
const float NH3_CLEAN_RATIO   = 3.6;
const float NH3_ON_PPM   = 10.0;
const float NH3_OFF_PPM  = 9.0;
const float ODOUR_ON     = 50.0;
const float ODOUR_OFF    = 49.0;

// State Machine for Cat Visits
enum VisitState {
  STATE_IDLE,
  STATE_CAT_IN_BOX,
  STATE_PURGING
};

// State Variables
HX711 scale;
static char serviceName[32];
static char deviceId[8];
static unsigned long buttonDownSince = 0;
static unsigned long lastHeartbeat = 0;
static unsigned long lastRemoteCheck = 0;
static unsigned long lastProvisionedTry = 0;
static volatile bool wifiReady = false;   
static volatile unsigned long wifiReadySince = 0;
static volatile unsigned long provEndedAt = 0;
static bool provisionedSent = false;

Preferences prefs;
static bool setupMode = false;
static volatile bool provisioningActive = false;
static volatile bool credsReceived = false;
static unsigned long setupStartedAt = 0;
static unsigned long wifiConnectStartedAt = 0;

float r0_137 = 1.0;
float rsClean_135 = 1.0;
float nh3Ppm = 0, odourPct = 0;
float rawWeightG = 0.0f;
float filteredWeightG = 0.0f;
float displayWeightG = 0.0f;

bool gasAlert = false;
bool fanOn = false;
bool fanAutoMode = true;
bool catNearby = false;
bool pirTriggeredLive = false; 
unsigned long lastMotion = 0;
unsigned long lastPirHighTime = 0; 
unsigned long lastSample = 0, lastPrint = 0;
unsigned long lastRelaySwitch = 0;
bool everSeenMotion = false;

static long emptyBaselineAdc = 0;
static bool isCalibrating = false;
static unsigned long lastAutoZeroTime = 0;
static float lastIdleWeight = 0.0f;

// Visit Event Tracking
static VisitState visitState = STATE_IDLE;
static unsigned long visitStartMs = 0;
static uint64_t visitStartEpochMs = 0;
static unsigned long catExitStartTimeMs = 0;
static unsigned long purgeStartMs = 0;

static float preVisitTareG = 0.0f;
static float visitPeakAmmonia = 0.0f;
static float visitPeakOdor = 0.0f;
static double catWeightAccumG = 0.0;
static uint32_t catWeightSamples = 0;

static float lastCatWeightG = 0.0f;
static float lastDepositG = 0.0f;
static float lastDwellSec = 0.0f;
static float visitPeakWeightG = 0.0f;

// ---- System Helpers ------------------------------------------------------
void softRestart() {
  prefs.begin("purrclean", false);
  prefs.putBool("swr", true);
  prefs.end();
  delay(200);
  ESP.restart();
}

void eraseWifiCredentials() {
  WiFi.mode(WIFI_STA);
  delay(100);
  WiFi.disconnect(true, true);
  delay(100);
  WiFi.mode(WIFI_STA);
  esp_wifi_restore();
  delay(100);
}

// Returns epoch time in milliseconds (UTC+8 synced via NTP)
uint64_t getEpochTimestampMs() {
  struct timeval tv;
  gettimeofday(&tv, NULL);
  if (tv.tv_sec < 100000000) {
    // If NTP has not completed, estimate using standard epoch fallback + millis()
    return 1730300000000ULL + millis();
  }
  return ((uint64_t)tv.tv_sec * 1000ULL) + (tv.tv_usec / 1000ULL);
}

void onWiFiEvent(arduino_event_t *event) {
  switch (event->event_id) {
    case ARDUINO_EVENT_PROV_START:
      provisioningActive = true;
      Serial.printf("Provisioning started. BLE name: %s\n", serviceName);
      break;
    case ARDUINO_EVENT_PROV_CRED_RECV:
      credsReceived = true;
      Serial.printf("Received Wi-Fi credentials for SSID: %s\n",
                    (const char *)event->event_info.prov_cred_recv.ssid);
      break;
    case ARDUINO_EVENT_PROV_CRED_FAIL:
      credsReceived = false;
      Serial.println("Provisioning failed (wrong password or network not found).");
      PROV_RESET_ON_FAIL();
      Serial.println("Provisioning reset: the app can try again.");
      break;
    case ARDUINO_EVENT_PROV_CRED_SUCCESS:
      Serial.println("Provisioning successful.");
      break;
    case ARDUINO_EVENT_PROV_END:
      Serial.println("Provisioning finished.");
      provisioningActive = false;
      provEndedAt = millis();
      break;
    case ARDUINO_EVENT_WIFI_STA_GOT_IP:
      Serial.print("Connected to Wi-Fi. IP: ");
      Serial.println(WiFi.localIP());
      wifiReadySince = millis();
      wifiReady = true;
      setupMode = false;
      wifiConnectStartedAt = 0;
      // Synchronize NTP Time (UTC+8 for Malaysia / Singapore)
      configTime(8 * 3600, 0, "pool.ntp.org", "time.google.com");
      Serial.println("NTP time synchronization requested.");
      break;
    case ARDUINO_EVENT_WIFI_STA_DISCONNECTED: {
      uint8_t reason = event->event_info.wifi_sta_disconnected.reason;
      Serial.printf("[Wi-Fi] Disconnected / Connect failed. Reason code: %d\n", reason);
      if (reason == 201) {
        Serial.println("  -> Reason 201 (NO_AP_FOUND): 2.4GHz network SSID not found or out of range!");
      } else if (reason == 202) {
        Serial.println("  -> Reason 202 (AUTH_FAIL): Password was rejected by the router!");
      } else if (reason == 15) {
        Serial.println("  -> Reason 15 (HANDSHAKE_TIMEOUT): Wrong password or 4-way handshake timeout!");
      } else if (reason == 205) {
        Serial.println("  -> Reason 205 (ASSOC_FAIL): Router refused connection (check WPA3 / PMF settings)!");
      }
      wifiReady = false;
      break;
    }
    default:
      break;
  }
}

// ---- Firebase HTTP Helper ------------------------------------------------
bool firebaseRequest(const char *method, const char *field, const char *body, String *out) {
  if (WiFi.status() != WL_CONNECTED) return false;

  String url = String(DB_URL) + "/devices/" + deviceId;
  if (field && field[0]) url += String("/") + field;
  url += ".json";

  int code = -1;
  for (int attempt = 1; attempt <= 3; attempt++) {
    if (WiFi.status() != WL_CONNECTED) return false;

    uint32_t heap = ESP.getFreeHeap();
    if (heap < MIN_HEAP_FOR_TLS) {
      delay(500);
      continue;
    }

    {
      WiFiClientSecure client;
      client.setInsecure();
      client.setTimeout(8);
      HTTPClient http;
      http.setReuse(false);
      http.setConnectTimeout(8000);
      http.setTimeout(8000);

      if (!http.begin(client, url)) {
        delay(300);
        continue;
      }

      if (strcmp(method, "PUT") == 0) {
        http.addHeader("Content-Type", "application/json");
        code = http.PUT(body ? body : "");
      } else {
        code = http.GET();
        if (code == 200 && out) *out = http.getString();
      }
      http.end();
    }

    if (code == 200) return true;
    if (code > 0) return false;
    delay(500 * attempt);
  }
  return false;
}

bool firebasePut(const char *field, const char *jsonBody) {
  return firebaseRequest("PUT", field, jsonBody, nullptr);
}

bool setProvisionedFlag(bool value) {
  return firebasePut("provisioned", value ? "true" : "false");
}

bool sendHeartbeat() {
  return firebasePut("lastSeen", "{\".sv\":\"timestamp\"}");
}

// Updates /devices/{deviceId}/fan in Firebase RTDB
bool updateFirebaseFanState(bool isRunning, bool autoMode) {
  if (WiFi.status() != WL_CONNECTED) return false;
  char body[128];
  snprintf(body, sizeof(body),
    "{\"auto_mode\":%s,\"is_running\":%s,\"updated_at\":{\".sv\":\"timestamp\"}}",
    autoMode ? "true" : "false",
    isRunning ? "true" : "false"
  );
  return firebasePut("fan", body);
}

// Uploads a complete visit event to /devices/{deviceId}/events/{timestamp_id}
bool sendLitterEvent(uint64_t timestampMs, float dwellSec, float depositGrams,
                     float ammoniaPpm, float odorPct, int outputType,
                     float purgeSec, float catWeightG) {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("[Firebase] Cannot upload event: Wi-Fi not connected");
    return false;
  }

  char path[64];
  snprintf(path, sizeof(path), "events/%llu", (unsigned long long)timestampMs);

  char body[384];
  snprintf(body, sizeof(body),
    "{\"timestamp\":%llu,"
    "\"dwellTimeSeconds\":%.2f,"
    "\"depositMassGrams\":%.2f,"
    "\"peakAmmoniaPpm\":%.2f,"
    "\"peakOdorIndexPct\":%.2f,"
    "\"estimatedOutputType\":%d,"
    "\"fanPurgeDurationSeconds\":%.2f,"
    "\"catWeightGrams\":%.2f}",
    (unsigned long long)timestampMs,
    dwellSec,
    depositGrams,
    ammoniaPpm,
    odorPct,
    outputType,
    purgeSec,
    catWeightG
  );

  Serial.printf("[Firebase] Uploading Event -> %s\n", path);
  Serial.printf("[Firebase] Payload: %s\n", body);

  bool ok = firebasePut(path, body);
  if (ok) {
    Serial.println("[Firebase] Event upload SUCCESSFUL!");
  } else {
    Serial.println("[Firebase] Event upload FAILED.");
  }
  return ok;
}

// ---- Setup & Remote Command Helpers ----------------------------------------
void clearSetupState() {
  prefs.begin("purrclean", false);
  prefs.putBool("setup", false);
  prefs.putBool("restore", false);
  prefs.remove("bakSsid");
  prefs.remove("bakPass");
  prefs.end();
}

void enterSetupMode() {
  prefs.begin("purrclean", false);
  if (!prefs.getBool("setup", false)) {
    wifi_config_t conf;
    if (esp_wifi_get_config(WIFI_IF_STA, &conf) == ESP_OK && conf.sta.ssid[0]) {
      prefs.putString("bakSsid", String((const char *)conf.sta.ssid));
      prefs.putString("bakPass", String((const char *)conf.sta.password));
    }
  }
  prefs.putBool("setup", true);
  prefs.putBool("restore", false);
  prefs.end();

  setProvisionedFlag(false);
  WiFi.mode(WIFI_STA);
  WiFi.disconnect(true, true);
  delay(500);
  softRestart();
}

void restoreOldWifiAndRestart() {
  prefs.begin("purrclean", false);
  prefs.putBool("setup", false);
  prefs.putBool("restore", true);
  prefs.end();
  softRestart();
}

void forgetWifiAndRestart() {
  clearSetupState();
  setProvisionedFlag(false);
  eraseWifiCredentials();
  softRestart();
}

void startBleProvisioning() {
  Serial.println("=================================================");
  Serial.printf("[Wi-Fi] Starting BLE Setup Mode for: %s\n", serviceName);
  Serial.printf("[Wi-Fi] Proof of Possession (POP)  : %s\n", POP);

  // Disconnect active Wi-Fi radio so Bluetooth can initialize cleanly
  WiFi.disconnect(true);
  delay(100);
  WiFi.mode(WIFI_OFF);
  delay(100);

  setupMode = true;
  setupStartedAt = millis();
  wifiConnectStartedAt = 0;

  // IMPORTANT: Passing reset_provisioned = true forces BLE advertising to start
  // even if the ESP32 was previously provisioned!
  WiFiProv.beginProvision(
    PROV_SCHEME_BLE,
    PROV_HANDLER,
    PROV_SECURITY_1,
    POP,
    serviceName,
    NULL,
    NULL,
    true
  );

  Serial.printf("[Wi-Fi] BLE advertising ACTIVE! Device: %s\n", serviceName);
  Serial.println("[Wi-Fi] Open the PurrClean mobile app and tap 'Search via Bluetooth'.");
  Serial.println("=================================================");
}

static bool jsonFlagTrue(const String &json, const char *key) {
  String s = json;
  s.replace(" ", "");
  s.replace("\n", "");
  s.replace("\r", "");
  s.toLowerCase();
  String k = String(key);
  k.toLowerCase();
  return s.indexOf("\"" + k + "\":true") >= 0 ||
         s.indexOf("\"" + k + "\":\"true\"") >= 0;
}

void checkRemoteCommands() {
  String body = "";
  bool ok = firebaseRequest("GET", "", nullptr, &body);
  body.trim();
  if (!ok) return;

  if (jsonFlagTrue(body, "hardReset")) {
    firebasePut("hardReset", "false");
    forgetWifiAndRestart();
  } else if (jsonFlagTrue(body, "resetWifi")) {
    firebasePut("resetWifi", "false");
    enterSetupMode();
  }

  // Parse Fan auto_mode setting from App
  if (body.indexOf("\"auto_mode\":false") >= 0 || body.indexOf("\"auto_mode\":\"false\"") >= 0) {
    fanAutoMode = false;
  } else if (body.indexOf("\"auto_mode\":true") >= 0 || body.indexOf("\"auto_mode\":\"true\"") >= 0) {
    fanAutoMode = true;
  }

  // If in Manual Mode and cat is not inside, obey the App's manual fan switch
  if (!fanAutoMode && visitState != STATE_CAT_IN_BOX) {
    bool appWantsRunning = (body.indexOf("\"is_running\":true") >= 0 || body.indexOf("\"is_running\":\"true\"") >= 0);
    if (appWantsRunning != fanOn) {
      setRelay(appWantsRunning);
    }
  }
}

// ---- Sensor Helpers ------------------------------------------------------
void setRelay(bool on) {
  if (fanOn != on) {
    lastRelaySwitch = millis(); 
  }
  fanOn = on;
  digitalWrite(RELAY_PIN, (on ^ RELAY_ACTIVE_LOW) ? HIGH : LOW);
}

float readSensorVolts(uint8_t pin) {
  uint32_t sum = 0;
  const int N = 32;
  for (int i = 0; i < N; i++) {
    sum += analogReadMilliVolts(pin);
    delayMicroseconds(200);
  }
  float v = (sum / (float)N) / 1000.0f;
  return v * DIVIDER_GAIN;
}

float sensorResistanceK(float vOut, float rlK) {
  if (vOut < 0.01f) vOut = 0.01f;
  if (vOut > VCC_SENSOR - 0.01f) vOut = VCC_SENSOR - 0.01f;
  return rlK * (VCC_SENSOR - vOut) / vOut;
}

float readRs137() { return sensorResistanceK(readSensorVolts(MQ137_PIN), RL_MQ137_K); }
float readRs135() { return sensorResistanceK(readSensorVolts(MQ135_PIN), RL_MQ135_K); }

void calibrateGasSensors() {
  float sum137 = 0, sum135 = 0;
  int samples = 20;
  for (int i = 0; i < samples; i++) {
    sum137 += readRs137();
    sum135 += readRs135();
    delay(250);
  }
  float rsClean137 = sum137 / samples;
  rsClean_135 = sum135 / samples;
  r0_137 = rsClean137 / NH3_CLEAN_RATIO;
}

// ---- Setup & Loop --------------------------------------------------------
void setup() {
  Serial.begin(115200);
  pinMode(RELAY_PIN, OUTPUT);
  setRelay(false);

  pinMode(RED_LED, OUTPUT);
  pinMode(GREEN_LED, OUTPUT);
  pinMode(PIR_PIN, INPUT);
  pinMode(RESET_BUTTON_PIN, INPUT_PULLUP);

  digitalWrite(RED_LED, HIGH);
  digitalWrite(GREEN_LED, LOW);

  analogReadResolution(12);
  analogSetPinAttenuation(MQ135_PIN, ADC_11db);
  analogSetPinAttenuation(MQ137_PIN, ADC_11db);

  uint16_t suffix = (uint16_t)(ESP.getEfuseMac() >> 32);
  snprintf(serviceName, sizeof(serviceName), "%s_%04X", NAME_PREFIX, suffix);
  snprintf(deviceId, sizeof(deviceId), "%04X", suffix);

  prefs.begin("purrclean", false);
  bool wasSwr = prefs.getBool("swr", false);
  prefs.putBool("swr", false);
  setupMode = prefs.getBool("setup", false);
  bool restoreOld = prefs.getBool("restore", false);
  prefs.end();

  if (restoreOld) {
    prefs.begin("purrclean", false);
    String s = prefs.getString("bakSsid", "");
    String p = prefs.getString("bakPass", "");
    prefs.remove("bakSsid");
    prefs.remove("bakPass");
    prefs.putBool("restore", false);
    prefs.end();

    if (s.length() > 0) {
      WiFi.begin(s.c_str(), p.length() > 0 ? p.c_str() : nullptr);
    }
  } else if (!wasSwr && FORGET_WIFI_ON_POWER_CYCLE) {
    clearSetupState();
    eraseWifiCredentials();
    setupMode = true;
  }

  WiFi.onEvent(onWiFiEvent);

  // Start Wi-Fi / Provisioning IMMEDIATELY so BLE starts advertising on boot
  if (setupMode) {
    startBleProvisioning();
  } else {
    wifi_config_t conf;
    bool hasCreds = (esp_wifi_get_config(WIFI_IF_STA, &conf) == ESP_OK && conf.sta.ssid[0]);
    if (!hasCreds) {
      Serial.println("[Wi-Fi] No Wi-Fi credentials found in NVS.");
      startBleProvisioning();
    } else {
      Serial.printf("[Wi-Fi] Connecting to stored network '%s'...\n", (const char *)conf.sta.ssid);
      WiFi.mode(WIFI_STA);
      WiFi.begin();
      wifiConnectStartedAt = millis();
    }
  }

  prefs.begin("purrclean", false);
  calibrationFactor = prefs.getFloat("calFactor", 18.22f);
  // Auto-heal corrupted factor (anything with magnitude < 2 is invalid)
  if (fabsf(calibrationFactor) < 2.0f || isnan(calibrationFactor)) {
    Serial.printf("[Scale] Invalid calFactor (%.4f) detected in NVS! Setting default 18.22f.\n", calibrationFactor);
    calibrationFactor = 18.22f;
    prefs.putFloat("calFactor", calibrationFactor);
  }
  prefs.end();

  scale.begin(LOADCELL_DOUT_PIN, LOADCELL_SCK_PIN);
  scale.set_scale(calibrationFactor);

  if (!setupMode) {
    Serial.println("[Scale] Warming up and stabilizing sensors (60s)...");
    unsigned long t0 = millis();
    while (millis() - t0 < WARMUP_MS) {
      delay(10);
    }
  } else {
    Serial.println("[Setup Mode] Fast boot: skipping 60s sensor warmup so BLE is immediately ready!");
  }

  // 1. Calibrate Gas Sensors FIRST while warm-up finishes
  Serial.println("[Gas] Calibrating gas sensors in clean air...");
  calibrateGasSensors();
  Serial.println("[Gas] Gas sensor calibration complete.");

  // 2. Tare load cell LAST, directly before entering loop()!
  Serial.println("[Scale] Taring load cell with empty box...");
  if (scale.is_ready()) {
    scale.tare(30);
    emptyBaselineAdc = scale.get_offset();
    rawWeightG = 0.0f;
    filteredWeightG = 0.0f;
    displayWeightG = 0.0f;
    Serial.printf("[Scale] Initial tare successful (baseline offset: %ld, factor: %.2f counts/g).\n",
                  emptyBaselineAdc, calibrationFactor);
  } else {
    Serial.println("[Scale] WARNING: HX711 not ready during startup tare!");
  }

  digitalWrite(RED_LED, LOW);
  digitalWrite(GREEN_LED, HIGH);
}

void loop() {
  unsigned long now = millis();

  // Auto-fallback to BLE setup mode if stored Wi-Fi cannot connect within 25 seconds
  if (!wifiReady && !setupMode && !provisioningActive) {
    if (wifiConnectStartedAt > 0 && (now - wifiConnectStartedAt > 25000UL)) {
      Serial.println("[Wi-Fi] Could not connect to stored network within 25s.");
      startBleProvisioning();
    }
  }

  if (setupMode && !wifiReady) {
    if (setupStartedAt > 0 && (now - setupStartedAt > SETUP_WINDOW_MS)) {
      setupStartedAt = now;
      Serial.printf("[Wi-Fi] Still advertising BLE Setup Mode: %s. Waiting for app...\n", serviceName);
    }
  }

  static unsigned long lastButtonPrint = 0;
  if (digitalRead(RESET_BUTTON_PIN) == LOW) {
    if (buttonDownSince == 0) {
      buttonDownSince = millis();
      lastButtonPrint = millis();
      Serial.println("[Button] BOOT button pressed! Keep holding for 5 seconds to reset Wi-Fi...");
    }
    if (now - lastButtonPrint >= 1000UL) {
      lastButtonPrint = now;
      int secHeld = (int)((now - buttonDownSince) / 1000UL);
      Serial.printf("[Button] Holding... %d/5 seconds\n", secHeld);
    }
    if (now - buttonDownSince >= RESET_HOLD_MS) {
      Serial.println("[Button] 5 seconds reached! Wiping Wi-Fi and restarting in BLE setup mode...");
      forgetWifiAndRestart();
    }
  } else {
    if (buttonDownSince > 0 && (now - buttonDownSince < RESET_HOLD_MS)) {
      Serial.println("[Button] Released before 5s. Wi-Fi was NOT reset.");
    }
    buttonDownSince = 0;
  }

  if (digitalRead(PIR_PIN) == HIGH) {
    lastPirHighTime = now;     
    pirTriggeredLive = true;
  }
  bool pirActive = (now - lastPirHighTime < PIR_STRETCH_MS);

  if (Serial.available()) {
    String input = Serial.readStringUntil('\n');
    input.trim();

    if (input.equalsIgnoreCase("help") || input.equalsIgnoreCase("?") || input.equalsIgnoreCase("menu")) {
      Serial.println("=================================================");
      Serial.println("[PurrClean Serial Commands]");
      Serial.println("  help / ?           : Show this command menu");
      Serial.println("  forget / resetwifi : Wipe stored Wi-Fi & enter BLE setup mode");
      Serial.println("  ble                : Force start BLE setup mode immediately");
      Serial.println("  wifi <ssid> <pass> : Connect directly to a Wi-Fi network");
      Serial.println("  wifi status        : Display live Wi-Fi connection info");
      Serial.println("  drift              : Measure load cell ADC drift for 5s");
      Serial.println("  t / tare / zero    : Tare scale to 0.0g");
      Serial.println("  cal                : Step 1 of guided scale calibration");
      Serial.println("  w <grams>          : Step 2 of guided scale calibration");
      Serial.println("  adj <grams>        : Live adjustment to known weight");
      Serial.println("  resetcal           : Reset scale factor to default (-156.4)");
      Serial.println("  raw / adc / diag   : Read live raw ADC values");
      Serial.println("  c                  : Calibrate gas sensors in clean air");
      Serial.println("=================================================");
    } else if (input.equalsIgnoreCase("forget") || input.equalsIgnoreCase("resetwifi") ||
               input.equalsIgnoreCase("reset")  || input.equalsIgnoreCase("setup") ||
               input.equalsIgnoreCase("erase")) {
      Serial.println("=================================================");
      Serial.println("[Wi-Fi] FORGETTING WI-FI CREDENTIALS...");
      Serial.println("[Wi-Fi] Wiping stored network from flash (NVS)...");
      clearSetupState();
      eraseWifiCredentials();
      setProvisionedFlag(false);
      Serial.println("[Wi-Fi] Wi-Fi credentials wiped successfully.");
      Serial.printf("[Wi-Fi] Restarting ESP32 into BLE Setup Mode (%s)...\n", serviceName);
      Serial.println("=================================================");
      delay(500);
      softRestart();
    } else if (input.equalsIgnoreCase("ble")) {
      if (!provisioningActive) {
        startBleProvisioning();
      } else {
        Serial.printf("[Wi-Fi] BLE Setup Mode is ALREADY active: %s\n", serviceName);
      }
    } else if (input.equalsIgnoreCase("resetcal") || input.equalsIgnoreCase("factory")) {
      isCalibrating = false;
      calibrationFactor = 18.22f;
      scale.set_scale(calibrationFactor);
      prefs.begin("purrclean", false);
      prefs.putFloat("calFactor", calibrationFactor);
      prefs.end();
      scale.tare(30);
      emptyBaselineAdc = scale.get_offset();
      rawWeightG = 0.0f;
      filteredWeightG = 0.0f;
      displayWeightG = 0.0f;
      Serial.println("=================================================");
      Serial.println("[Scale] FACTORY RESET SUCCESSFUL!");
      Serial.printf("[Scale] Restored Default Factor : %.4f counts/gram\n", calibrationFactor);
      Serial.printf("[Scale] New Baseline Offset     : %ld\n", emptyBaselineAdc);
      Serial.println("[Scale] Current Weight          : 0.0g");
      Serial.println("=================================================");
    } else if (input.equalsIgnoreCase("t") || input.equalsIgnoreCase("tare") || input.equalsIgnoreCase("zero")) {
      isCalibrating = false;
      Serial.println("[Scale] Taring empty scale... Please ensure box is completely EMPTY and STILL.");
      delay(300);
      scale.tare(30);
      emptyBaselineAdc = scale.get_offset();
      rawWeightG = 0.0f;
      filteredWeightG = 0.0f;
      displayWeightG = 0.0f;
      Serial.printf("[Scale] Tare complete! Empty baseline ADC offset: %ld (Current weight: 0.0g)\n", emptyBaselineAdc);
    } else if (input.equalsIgnoreCase("cal")) {
      // Step 1 of guided calibration: Tare empty baseline and enter calibration mode
      isCalibrating = true;
      Serial.println("=================================================");
      Serial.println("[Scale Calibration] STEP 1: EMPTY BASELINE");
      Serial.println("[Scale] Taring... Please ensure box is completely EMPTY and STILL.");
      delay(400);
      scale.tare(30);
      emptyBaselineAdc = scale.get_offset();
      rawWeightG = 0.0f;
      filteredWeightG = 0.0f;
      displayWeightG = 0.0f;
      Serial.printf("[Scale] STEP 1 COMPLETE! Empty baseline offset: %ld\n", emptyBaselineAdc);
      Serial.println("[Scale] STEP 2: Place your 1060g weight in the center of the box.");
      Serial.println("[Scale]         Watch the [CALIBRATION MODE] lines below.");
      Serial.println("[Scale]         Once Delta jumps & settles, type: w 1060");
      Serial.println("[Scale]         (Type 'cal cancel' anytime to abort).");
      Serial.println("=================================================");
    } else if (input.equalsIgnoreCase("cal cancel") || input.equalsIgnoreCase("cancel")) {
      isCalibrating = false;
      Serial.println("[Scale] Calibration mode CANCELLED.");
    } else if (input.startsWith("w ") || input.startsWith("W ")) {
      // Step 2 of guided calibration: Calculate factor against the empty baseline
      int spaceIdx = input.indexOf(' ');
      float knownG = input.substring(spaceIdx + 1).toFloat();
      if (knownG > 5.0f) {
        Serial.printf("[Scale] Measuring known weight %.1fg (averaging 30 samples)...\n", knownG);
        long loadedAdc = scale.read_average(30);
        long delta = loadedAdc - emptyBaselineAdc;
        Serial.printf("[Scale] Empty ADC Offset : %ld\n", emptyBaselineAdc);
        Serial.printf("[Scale] Loaded ADC Avg   : %ld\n", loadedAdc);
        Serial.printf("[Scale] Delta ADC Counts : %ld\n", delta);

        if (labs(delta) < 5000) {
          Serial.println("[Scale] ERROR: Deflection too small (<5000 counts)!");
          Serial.println("[Scale] Did you type 'cal' with empty box first? Please type 'cal' to restart.");
          isCalibrating = false;
        } else {
          calibrationFactor = (float)delta / knownG;
          scale.set_scale(calibrationFactor);
          scale.set_offset(emptyBaselineAdc);
          prefs.begin("purrclean", false);
          prefs.putFloat("calFactor", calibrationFactor);
          prefs.end();

          isCalibrating = false;
          visitState = STATE_IDLE;
          rawWeightG = scale.get_units(10);
          filteredWeightG = rawWeightG;
          displayWeightG = (fabsf(filteredWeightG) < WEIGHT_DEADBAND_G) ? 0.0f : filteredWeightG;
          preVisitTareG = filteredWeightG;

          Serial.println("=================================================");
          Serial.println("[Scale] CALIBRATION SUCCESS!");
          Serial.printf("[Scale] New Factor Saved : %.4f counts/gram\n", calibrationFactor);
          Serial.printf("[Scale] Verified Weight  : %.1fg (Expected: %.1fg)\n", displayWeightG, knownG);
          Serial.println("[Scale] You can now remove the weight. It will settle back to 0.0g.");
          Serial.println("=================================================");
        }
      } else {
        Serial.println("[Scale] Usage: type 'cal' to tare, then 'w 1060' with known weight.");
      }
    } else if (input.startsWith("adj ") || input.startsWith("ADJ ") || input.startsWith("set ") || input.startsWith("SET ")) {
      // Live Adjustment: Place weight on scale, wait for it to settle, type 'adj 1060'
      int spaceIdx = input.indexOf(' ');
      float actualG = input.substring(spaceIdx + 1).toFloat();
      if (actualG > 5.0f) {
        isCalibrating = false;
        Serial.printf("[Scale] Measuring weight on scale for target %.1fg...\n", actualG);
        long currentAdc = scale.read_average(20);
        long currentOffset = scale.get_offset();
        long delta = currentAdc - currentOffset;

        if (labs(delta) < 5000) {
          Serial.printf("[Scale] ERROR: Deflection (%ld counts) too small (<5000 counts)!\n", delta);
          Serial.println("[Scale] Please ensure the known weight is placed in the center of the box.");
        } else {
          calibrationFactor = (float)delta / actualG;
          scale.set_scale(calibrationFactor);
          prefs.begin("purrclean", false);
          prefs.putFloat("calFactor", calibrationFactor);
          prefs.end();

          rawWeightG = scale.get_units(5);
          filteredWeightG = rawWeightG;
          displayWeightG = (fabsf(filteredWeightG) < WEIGHT_DEADBAND_G) ? 0.0f : filteredWeightG;

          Serial.println("=================================================");
          Serial.printf("[Scale] ADJUSTMENT SUCCESS!\n");
          Serial.printf("[Scale] New Factor Saved : %.4f counts/gram\n", calibrationFactor);
          Serial.printf("[Scale] Current Weight   : %.1fg (Expected: %.1fg)\n", displayWeightG, actualG);
          Serial.println("=================================================");
        }
      } else {
        Serial.println("[Scale] Error: Please place your known weight on the scale first, then type 'adj 1060'.");
      }
    } else if (input.equalsIgnoreCase("raw") || input.equalsIgnoreCase("adc") || input.equalsIgnoreCase("diag")) {
      Serial.println("=================================================");
      Serial.println("[Scale Diagnostic Readouts]");
      Serial.printf("  Stored Cal Factor  : %.4f counts/gram\n", calibrationFactor);
      Serial.printf("  Current Tare Offset: %ld\n", scale.get_offset());
      Serial.println("  Sampling 5 live raw ADC reads from HX711 chip:");
      for (int i = 0; i < 5; i++) {
        long rawVal = scale.read();
        long d = rawVal - scale.get_offset();
        float calcG = (calibrationFactor != 0.0f) ? (float)d / calibrationFactor : 0.0f;
        Serial.printf("   #%d: Raw ADC = %ld (Delta: %ld) -> Calc Weight = %.1fg\n",
                      i + 1, rawVal, d, calcG);
        delay(120);
      }
      Serial.println("=================================================");
    } else if (input.equalsIgnoreCase("drift")) {
      Serial.println("=================================================");
      Serial.println("[Scale Drift Diagnostic Test]");
      Serial.println("Measuring raw ADC drift for 5 seconds...");
      Serial.println("PLEASE DO NOT TOUCH THE SCALE OR BOX.");
      long startAdc = scale.read_average(10);
      unsigned long tStart = millis();
      delay(5000);
      long endAdc = scale.read_average(10);
      unsigned long tEnd = millis();
      float dt = (float)(tEnd - tStart) / 1000.0f;
      long adcDelta = endAdc - startAdc;
      float countsPerSec = (float)adcDelta / dt;
      float gramsPerSec = (calibrationFactor != 0.0f) ? (countsPerSec / calibrationFactor) : 0.0f;

      Serial.println("-------------------------------------------------");
      Serial.printf("Start ADC       : %ld\n", startAdc);
      Serial.printf("End ADC         : %ld\n", endAdc);
      Serial.printf("Total ADC Delta : %ld counts in %.1f seconds\n", adcDelta, dt);
      Serial.printf("Drift Rate      : %.1f counts/sec (%.2f g/sec)\n", countsPerSec, gramsPerSec);
      Serial.println("-------------------------------------------------");
      if (fabsf(countsPerSec) < 15.0f) {
        Serial.println("Result: [EXCELLENT] Hardware is rock solid. Minimal noise.");
      } else if (fabsf(countsPerSec) < 60.0f) {
        Serial.println("Result: [MODERATE] Normal ambient drift. Firmware auto-zero will easily keep it at 0.0g.");
      } else {
        Serial.println("Result: [HIGH DRIFT] Hardware electrical or thermal drift detected!");
        Serial.println("Top Causes & Fixes:");
        Serial.println(" 1. HX711 VCC must be connected to 5V (VIN), NOT 3.3V!");
        Serial.println("    (The HX711 on-chip analog regulator needs >= 4.3V to stabilize).");
        Serial.println(" 2. Ground Loop: Do not share HX711 GND on breadboard with MQ-135/MQ-137.");
        Serial.println("    Connect HX711 GND directly to an ESP32 GND pin.");
        Serial.println(" 3. Disconnect MQ sensor 5V wire temporarily to test if drift stops.");
      }
      Serial.println("=================================================");
    } else if (input.startsWith("wifi ") || input.startsWith("WIFI ")) {
      String params = input.substring(5);
      params.trim();

      if (params.equalsIgnoreCase("status") || params.equalsIgnoreCase("info")) {
        Serial.println("=================================================");
        Serial.println("[Wi-Fi Status]");
        Serial.printf("  Status       : %s\n", wifiReady ? "CONNECTED" : (setupMode ? "BLE SETUP MODE" : "DISCONNECTED / CONNECTING"));
        Serial.printf("  SSID         : %s\n", WiFi.SSID().c_str());
        Serial.printf("  IP Address   : %s\n", WiFi.localIP().toString().c_str());
        Serial.printf("  Signal (RSSI): %d dBm\n", WiFi.RSSI());
        Serial.printf("  BLE Name     : %s\n", serviceName);
        Serial.printf("  Device ID    : %s\n", deviceId);
        Serial.println("=================================================");
      } else {
        String newSsid = "";
        String newPass = "";

        // Handle quoted format: wifi "My Network" "My Password"
        if (params.startsWith("\"")) {
          int endSsid = params.indexOf('"', 1);
          if (endSsid > 1) {
            newSsid = params.substring(1, endSsid);
            int startPass = params.indexOf('"', endSsid + 1);
            if (startPass > 0) {
              int endPass = params.indexOf('"', startPass + 1);
              if (endPass > startPass) {
                newPass = params.substring(startPass + 1, endPass);
              }
            }
          }
        } else {
          // Space separated format: wifi MySSID MyPassword
          int spaceIdx = params.indexOf(' ');
          if (spaceIdx > 0) {
            newSsid = params.substring(0, spaceIdx);
            newPass = params.substring(spaceIdx + 1);
          } else {
            newSsid = params; // Open network with no password
          }
        }

        newSsid.trim();
        newPass.trim();

        if (newSsid.length() > 0) {
          Serial.println("=================================================");
          Serial.printf("[Wi-Fi] Connecting to new network: '%s'...\n", newSsid.c_str());
          Serial.println("[Wi-Fi] Saving to persistent storage...");
          clearSetupState();
          WiFi.disconnect(true);
          delay(200);
          WiFi.mode(WIFI_STA);
          WiFi.persistent(true);
          WiFi.begin(newSsid.c_str(), newPass.length() > 0 ? newPass.c_str() : nullptr);
          wifiConnectStartedAt = millis();
          setupMode = false;
          Serial.println("[Wi-Fi] Connection initiated. Check status in a few seconds.");
          Serial.println("=================================================");
        } else {
          Serial.println("[Wi-Fi] Usage:");
          Serial.println("  wifi <SSID> <Password>          (e.g. wifi HomeNetwork Secret123)");
          Serial.println("  wifi \"<SSID>\" \"<Password>\"      (for networks with spaces)");
          Serial.println("  wifi status                     (view current Wi-Fi status)");
          Serial.println("  forget                          (wipe Wi-Fi & enter BLE setup mode)");
          Serial.println("  ble                             (start Bluetooth setup mode)");
        }
      }
    } else if (input.equalsIgnoreCase("c")) {
      Serial.println("[Gas] Calibrating gas sensors in clean air...");
      calibrateGasSensors();
      Serial.println("[Gas] Calibration complete.");
    }
  }

  // Handle Wi-Fi and Firebase background tasks
  if (wifiReady) {
    if (now - wifiReadySince >= NET_SETTLE_MS) {
      if (!provisionedSent && (lastProvisionedTry == 0 || now - lastProvisionedTry >= PROVISIONED_RETRY_MS)) {
        lastProvisionedTry = now;
        if (setProvisionedFlag(true)) {
          provisionedSent = true;
          clearSetupState();
          updateFirebaseFanState(fanOn, fanAutoMode);
        }
      }

      if (provisionedSent) {
        if (lastHeartbeat == 0 || now - lastHeartbeat >= HEARTBEAT_MS) {
          lastHeartbeat = now;
          sendHeartbeat();
        }
        if (lastRemoteCheck == 0 || now - lastRemoteCheck >= REMOTE_CHECK_MS) {
          lastRemoteCheck = now;
          checkRemoteCommands();
        }
      }
    }
  }

  // Periodic sensor sampling & event detection
  if (now - lastSample >= SAMPLE_MS) {
    lastSample = now;

    // Motion check for this sample window
    bool motionDetected = pirTriggeredLive || pirActive;
    pirTriggeredLive = false;

    // Read Ammonia Sensor (MQ-137)
    float rs137 = readRs137();
    float ratio137 = rs137 / r0_137;
    nh3Ppm = NH3_REF_PPM * powf(ratio137, NH3_SLOPE);
    if (nh3Ppm > 500.0f) nh3Ppm = 500.0f;

    // Read Odor Sensor (MQ-135)
    float rs135 = readRs135();
    float ratio135 = rs135 / rsClean_135;
    if (ratio135 > 1.0f) ratio135 = 1.0f; 
    odourPct = (1.0f - powf(ratio135, 1.5f)) * 100.0f;
    odourPct = constrain(odourPct, 0.0f, 100.0f);
    if (odourPct < 1.0f) odourPct = 0.0f;

    // Read Scale (HX711) with spike rejection
    if (scale.is_ready() && (now - lastRelaySwitch > RELAY_SETTLE_MS)) {
      float reading = scale.get_units(3);
      
      // Filter out invalid/corrupted reads
      if (!isnan(reading) && fabsf(reading) < 50000.0f) {
        rawWeightG = reading;
        // Fast tracking on large step transitions (e.g. cat entry/exit or object placement)
        // Smooth noise rejection when stationary
        float weightDelta = fabsf(rawWeightG - filteredWeightG);
        float alpha = (weightDelta > 100.0f) ? 0.85f : WEIGHT_EMA_ALPHA;
        filteredWeightG = (alpha * rawWeightG) + ((1.0f - alpha) * filteredWeightG);
        // Net display weight: clamp small noise near zero to 0.0g
        if (fabsf(filteredWeightG) < WEIGHT_DEADBAND_G) {
          displayWeightG = 0.0f;
        } else {
          displayWeightG = filteredWeightG;
        }
      }
    }

    // Fast, non-blocking idle zero-tracking for empty box baseline drift:
    // When box is idle and empty with NO cat nearby and NO motion (and not in calibration mode)
    if (!isCalibrating && visitState == STATE_IDLE && !catNearby && !motionDetected && !pirActive) {
      // Any weight below 250g with no motion is empty box baseline drift
      if (fabsf(filteredWeightG) < 250.0f) {
        if (fabsf(filteredWeightG) > 1.0f) {
          if (lastAutoZeroTime == 0) {
            lastAutoZeroTime = now;
          } else if (now - lastAutoZeroTime >= 2000UL) { // Adjust every 2 seconds of undisturbed empty box
            lastAutoZeroTime = now;
            long offsetCorrection = (long)(filteredWeightG * calibrationFactor);
            scale.set_offset(scale.get_offset() + offsetCorrection);
            rawWeightG = 0.0f;
            filteredWeightG = 0.0f;
            displayWeightG = 0.0f;
          }
        } else {
          lastAutoZeroTime = 0;
        }
      } else {
        lastAutoZeroTime = 0;
      }
    } else {
      lastAutoZeroTime = 0;
    }

    // Cat proximity and presence detection
    bool weightPresent = (displayWeightG >= CAT_MIN_WEIGHT_G);

    // Dual-sensor detection: Cat is confirmed present IF AND ONLY IF BOTH motion AND weight trigger
    bool catConfirmed = motionDetected && weightPresent;

    if (catConfirmed) {
      lastMotion = now;
      everSeenMotion = true;
    }
    catNearby = everSeenMotion && (now - lastMotion < CAT_HOLD_MS);
    if (!weightPresent) everSeenMotion = false; 

    // Ambient gas threshold check
    if (!gasAlert && (nh3Ppm >= NH3_ON_PPM || odourPct >= ODOUR_ON)) {
      gasAlert = true;
    } else if (gasAlert && nh3Ppm < NH3_OFF_PPM && odourPct < ODOUR_OFF) {
      gasAlert = false;
    }

    // ---- Visit Event Lifecycle State Machine -------------------------------
    switch (visitState) {
      case STATE_IDLE: {
        // Continuously record baseline tare weight when box is empty
        preVisitTareG = displayWeightG;

        // Enter STATE_CAT_IN_BOX (State: 1) IF AND ONLY IF BOTH sensors trigger
        if (catConfirmed) {
          // Cat has entered the litter box
          visitState = STATE_CAT_IN_BOX;
          visitStartMs = now;
          visitStartEpochMs = getEpochTimestampMs();
          catExitStartTimeMs = 0;
          visitPeakWeightG = displayWeightG;
          visitPeakAmmonia = nh3Ppm;
          visitPeakOdor = odourPct;
          catWeightAccumG = 0.0;
          catWeightSamples = 0;

          // Safety rule: Fan MUST be turned OFF immediately while cat is inside
          if (fanOn) {
            setRelay(false);
            updateFirebaseFanState(false, fanAutoMode);
          }
          Serial.printf("[Event] Cat entered box! (Dual-Trigger: Motion + Weight %.1fg)\n", displayWeightG);
        } else {
          // Normal idle automatic ventilation when ambient odor/NH3 rises
          if (fanAutoMode) {
            // Automatic fan rule: Run for ambient gas ONLY if cat is NOT present or nearby
            bool catPresentOrNearby = catNearby || catConfirmed || weightPresent;
            bool wantAmbientFan = gasAlert && !catPresentOrNearby;
            if (wantAmbientFan != fanOn) {
              setRelay(wantAmbientFan);
              updateFirebaseFanState(wantAmbientFan, fanAutoMode);
            }
          }
        }
        break;
      }

      case STATE_CAT_IN_BOX: {
        // Safety: keep fan off while cat is in the box
        if (fanOn) {
          setRelay(false);
          updateFirebaseFanState(false, fanAutoMode);
        }

        // Track peak gas readings during the visit
        if (nh3Ppm > visitPeakAmmonia) visitPeakAmmonia = nh3Ppm;
        if (odourPct > visitPeakOdor) visitPeakOdor = odourPct;

        if (displayWeightG > visitPeakWeightG) {
          visitPeakWeightG = displayWeightG;
        }

        // Cat is considered still inside if weight is above CAT_MIN_WEIGHT_G
        // AND has not dropped by more than 60% of peak weight
        bool catStillInside = (displayWeightG >= CAT_MIN_WEIGHT_G);
        if (visitPeakWeightG >= (CAT_MIN_WEIGHT_G * 1.5f) && displayWeightG < (visitPeakWeightG * 0.40f)) {
          catStillInside = false; // Weight sharply dropped -> cat stepped out of box
        }

        if (catStillInside) {
          // Accumulate cat body weight while stable inside (ignore the first 1.5s entrance impact)
          if (now - visitStartMs > 1500UL) {
            catWeightAccumG += displayWeightG;
            catWeightSamples++;
          }
          catExitStartTimeMs = 0;
        } else {
          // Weight dropped below threshold: verify if cat has exited
          if (catExitStartTimeMs == 0) {
            catExitStartTimeMs = now;
          } else if (now - catExitStartTimeMs >= CAT_EXIT_CONFIRM_MS) {
            // Cat has confirmed left the box
            float dwellTimeSec = (float)(catExitStartTimeMs - visitStartMs) / 1000.0f;
            if (dwellTimeSec < 0.5f) dwellTimeSec = 0.5f;

            // Compute true cat body weight by subtracting the empty box tare baseline
            float avgInsideWeight = (catWeightSamples > 0) ? (float)(catWeightAccumG / catWeightSamples) : visitPeakWeightG;
            lastCatWeightG = avgInsideWeight - preVisitTareG;
            if (lastCatWeightG < 0.0f) lastCatWeightG = avgInsideWeight;

            // Measure net deposit mass produced
            float postVisitTareG = displayWeightG;
            lastDepositG = postVisitTareG - preVisitTareG;
            if (lastDepositG < 0.0f) lastDepositG = 0.0f;

            lastDwellSec = dwellTimeSec;

            Serial.printf("[Event] Cat exited. Dwell: %.1fs, Deposit: %.1fg, Cat Weight: %.1fg\n",
                          lastDwellSec, lastDepositG, lastCatWeightG);

            // Move to post-visit purge
            visitState = STATE_PURGING;
            purgeStartMs = now;

            // Turn on ventilation fan to clear the air
            if (fanAutoMode) {
              setRelay(true);
              updateFirebaseFanState(true, fanAutoMode);
            }
          }
        }
        break;
      }

      case STATE_PURGING: {
        // If cat re-enters during purge (dual-trigger: BOTH motion + weight), interrupt purge and resume visit
        if (catConfirmed) {
          Serial.println("[Event] Cat re-entered during purge. Interrupting fan and resuming visit.");
          visitState = STATE_CAT_IN_BOX;
          catExitStartTimeMs = 0;
          if (fanOn) {
            setRelay(false);
            updateFirebaseFanState(false, fanAutoMode);
          }
          break;
        }

        // Track peak gas readings
        if (nh3Ppm > visitPeakAmmonia) visitPeakAmmonia = nh3Ppm;
        if (odourPct > visitPeakOdor) visitPeakOdor = odourPct;

        // Check purge completion: gas cleaned OR purge timeout reached
        unsigned long purgeElapsedMs = now - purgeStartMs;
        bool gasClean = (nh3Ppm < NH3_OFF_PPM && odourPct < ODOUR_OFF);
        bool purgeTimeout = (purgeElapsedMs >= MAX_PURGE_MS);

        if (gasClean || purgeTimeout || !fanAutoMode) {
          float fanPurgeDurationSec = (float)purgeElapsedMs / 1000.0f;

          // Turn off fan
          if (fanOn) {
            setRelay(false);
            updateFirebaseFanState(false, fanAutoMode);
          }

          // Sensor Classification:
          // 0 = Straining/None, 1 = Urine, 2 = Feces, 3 = Both
          int outputType = 0;
          if (lastDepositG < 5.0f || (lastDwellSec >= 180.0f && lastDepositG < 8.0f)) {
            outputType = 0; // Dry straining / no deposit
          } else if (lastDepositG >= 8.0f && visitPeakAmmonia >= 18.0f && visitPeakOdor < 60.0f) {
            outputType = 1; // Urine
          } else if (lastDepositG >= 15.0f && visitPeakOdor >= 50.0f && visitPeakAmmonia < 25.0f) {
            outputType = 2; // Feces
          } else if (lastDepositG >= 25.0f && (visitPeakAmmonia >= 20.0f || visitPeakOdor >= 60.0f)) {
            outputType = 3; // Both
          } else {
            outputType = (visitPeakAmmonia >= 15.0f) ? 1 : 2;
          }

          // Upload event to Firebase RTDB (filters accidental nudges under 2.5 seconds)
          if (lastDwellSec >= 2.5f) {
            sendLitterEvent(
              visitStartEpochMs,
              lastDwellSec,
              lastDepositG,
              visitPeakAmmonia,
              visitPeakOdor,
              outputType,
              fanPurgeDurationSec,
              lastCatWeightG
            );
          }

          // Return to IDLE
          visitState = STATE_IDLE;
          Serial.println("[Event] Post-visit cycle complete. Returned to IDLE.");
        }
        break;
      }
    }
  }

  // Periodic Serial debug output
  if (now - lastPrint >= PRINT_MS) {
    lastPrint = now;
    if (isCalibrating) {
      long liveAdc = scale.is_ready() ? scale.read() : emptyBaselineAdc;
      long liveDelta = liveAdc - emptyBaselineAdc;
      Serial.printf("[CALIBRATION MODE] Baseline: %ld | Live ADC: %ld | Delta: %+ld counts\n",
                    emptyBaselineAdc, liveAdc, liveDelta);
      if (labs(liveDelta) < 5000) {
        Serial.println("  -> Action: Place 1060g weight in box. Waiting for deflection...");
      } else {
        Serial.printf("  -> Weight detected (%+ld counts)! Wait 3s to settle, then type: w 1060\n", liveDelta);
      }
    } else {
      Serial.printf("[Status] Net: %.1fg (Raw: %.1fg) | NH3: %.1f ppm | Odor: %.0f%% | State: %d | Fan: %s (%s)\n",
                    displayWeightG, rawWeightG, nh3Ppm, odourPct, (int)visitState,
                    fanOn ? "ON" : "OFF", fanAutoMode ? "AUTO" : "MANUAL");
    }
  }
}
