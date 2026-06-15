#include <Arduino.h>
#include <WiFi.h>
#include <FirebaseESP32.h>
#include <PZEM004Tv30.h>
#include <Wire.h>
#include <Adafruit_INA219.h>
#include <Preferences.h>   // ADD: persistent energy storage for INA219
#include <time.h>          // ADD: NTP timestamps

// ============================================================================
// 1. CONFIGURATION WI-FI & FIREBASE
// ============================================================================
#define WIFI_SSID "Byaku"
#define WIFI_PASSWORD "agadirofla0"
#define FIREBASE_HOST "ocp-energy-monitor-default-rtdb.europe-west1.firebasedatabase.app"
#define FIREBASE_AUTH "AIzaSyDhAbbyOUj0CzJVUJWNw_bDImGZ0vnI_m4"

// ============================================================================
// 2. CONFIGURATION DES PINS HARDWARE
// ============================================================================
const int potPin         = 34;
const int motorPin       = 13;
const int pumpRelayPin   = 12;
const int waterSensorPin = 32;

#define RX_PIN 16
#define TX_PIN 17

// ============================================================================
// 3. PARAMÈTRES DE CALIBRATION DU CAPTEUR DE NIVEAU
// ============================================================================
const int VAL_MIN_DRY = 50;
const int VAL_MAX_WET = 1800;

// ============================================================================
// 4. INSTANCES DES CAPTEURS HARDWARE
// ============================================================================
PZEM004Tv30 pzem(Serial2, RX_PIN, TX_PIN);

Adafruit_INA219 ina219_0x40;
Adafruit_INA219 ina219_0x41(0x41);

FirebaseData fbdo_fan;
FirebaseData fbdo_pump;
FirebaseAuth auth;
FirebaseConfig config;

// ADD: persistent energy for INA219 units
Preferences preferences;
float ina40EnergyKwh = 0.0;  // Unit 2 fan accumulated kWh
float ina41EnergyKwh = 0.0;  // Unit 3 pump accumulated kWh
int   energySaveCounter = 0; // save to flash every 5 min (150 × 2s)

int lastPotValue = 0;
int currentVitessePourcentage = 0;
String lastPumpStatus = "OFF";
int globalWaterPercent = 0;

unsigned long lastMetricsCheck = 0;
const long metricsInterval = 2000;

bool isIna40Ready = false;
bool isIna41Ready = false;

const float AC_CURRENT_NOISE_A = 0.005;
const float AC_POWER_NOISE_W = 0.5;

// ADD: NTP timestamp helper
String getIsoTimestamp() {
  struct tm t;
  if (!getLocalTime(&t)) return "";
  char buf[25];
  strftime(buf, sizeof(buf), "%Y-%m-%dT%H:%M:%SZ", &t);
  return String(buf);
}

void setup() {
  Serial.begin(115200);
  delay(1000);

  Wire.begin();

  if (!ina219_0x40.begin()) Serial.println("[ERREUR] INA219 (0x40) introuvable !");
  else isIna40Ready = true;

  if (!ina219_0x41.begin()) Serial.println("[ERREUR] INA219 (0x41) introuvable !");
  else isIna41Ready = true;

  // ADD: restore persisted INA219 energy counters
  preferences.begin("energy", false);
  ina40EnergyKwh = preferences.getFloat("fan_kwh",  0.0);
  ina41EnergyKwh = preferences.getFloat("pump_kwh", 0.0);
  Serial.printf("[OK] Energie chargée — Fan: %.4f kWh, Pompe: %.4f kWh\n",
                ina40EnergyKwh, ina41EnergyKwh);

  pinMode(pumpRelayPin, OUTPUT);
  digitalWrite(pumpRelayPin, LOW);

  ledcAttach(motorPin, 5000, 8);
  ledcWrite(motorPin, 0);

  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  while (WiFi.status() != WL_CONNECTED) { delay(500); Serial.print("."); }
  Serial.println("\n[OK] Wi-Fi Connecté !");

  // ADD: NTP sync (UTC — Firestore/RTDB use UTC)
  configTime(0, 0, "pool.ntp.org", "time.nist.gov");
  Serial.print("[NTP] Synchronisation");
  struct tm t;
  int ntpRetry = 0;
  while (!getLocalTime(&t) && ntpRetry < 20) { delay(500); Serial.print("."); ntpRetry++; }
  Serial.println(ntpRetry < 20 ? " OK" : " TIMEOUT (timestamps approximatifs)");

  config.host = FIREBASE_HOST;
  config.signer.tokens.legacy_token = FIREBASE_AUTH;
  Firebase.begin(&config, &auth);
  Firebase.reconnectWiFi(true);

  lastPotValue = analogRead(potPin);
}

void loop() {
  unsigned long currentMillis = millis();

  // Niveau d'eau
  int rawWater = analogRead(waterSensorPin);
  globalWaterPercent = map(rawWater, VAL_MIN_DRY, VAL_MAX_WET, 0, 100);
  globalWaterPercent = constrain(globalWaterPercent, 0, 100);

  // --- Unit 2 (Ventilateur PWM) ---
  int rawPot = analogRead(potPin);
  int potPourcentage = map(rawPot, 0, 4095, 0, 100);

  if (abs(potPourcentage - map(lastPotValue, 0, 4095, 0, 100)) > 2) {
    currentVitessePourcentage = potPourcentage;
    ledcWrite(motorPin, map(currentVitessePourcentage, 0, 100, 0, 255));
    lastPotValue = rawPot;
    Firebase.setInt(fbdo_fan, "/KOFERT_Unit_2/fan_control/speed_percent", currentVitessePourcentage);
    Firebase.setInt(fbdo_fan, "/KOFERT_Unit_2/current_metrics/fan_speed", currentVitessePourcentage);
  } else {
    if (Firebase.getInt(fbdo_fan, "/KOFERT_Unit_2/fan_control/speed_percent")) {
      if (fbdo_fan.dataType() == "int") {
        int fbPourcentage = fbdo_fan.intData();
        if (fbPourcentage != currentVitessePourcentage) {
          currentVitessePourcentage = constrain(fbPourcentage, 0, 100);
          ledcWrite(motorPin, map(currentVitessePourcentage, 0, 100, 0, 255));
          Firebase.setInt(fbdo_fan, "/KOFERT_Unit_2/current_metrics/fan_speed", currentVitessePourcentage);
        }
      }
    }
  }

  // --- Unit 3 (Pompe & Sécurité <= 30%) ---
  if (globalWaterPercent <= 30) {
    if (lastPumpStatus != "OFF") {
      digitalWrite(pumpRelayPin, LOW);
      lastPumpStatus = "OFF";
      Firebase.setString(fbdo_pump, "/KOFERT_Unit_3/current_metrics/pump_status", "OFF");
    }
  } else {
    if (Firebase.getString(fbdo_pump, "/KOFERT_Unit_3/current_metrics/pump_status")) {
      if (fbdo_pump.dataType() == "string") {
        String pumpStatus = fbdo_pump.stringData();
        if (pumpStatus != lastPumpStatus) {
          lastPumpStatus = pumpStatus;
          digitalWrite(pumpRelayPin, (lastPumpStatus == "ON") ? HIGH : LOW);
        }
      }
    }
  }

  // --- Télémétrie (chaque 2 secondes) ---
  if (currentMillis - lastMetricsCheck >= metricsInterval) {
    lastMetricsCheck = currentMillis;

    // ── UNIT 1 : Réseau AC (PZEM-004T) ──────────────────────────────────────
    float acVoltage  = pzem.voltage();
    float acCurrent  = pzem.current();
    float acPower    = pzem.power();
    float acPf       = pzem.pf();
    float acEnergy   = pzem.energy();    // ADD: kWh odometer
    float acFreq     = pzem.frequency(); // ADD: Hz

    bool pzemOnline = !isnan(acVoltage);
    bool acCurrentValid = !isnan(acCurrent);
    bool acPowerValid = !isnan(acPower);
    bool loadLooksOff =
      !pzemOnline ||
      !acCurrentValid ||
      !acPowerValid ||
      (abs(acCurrent) <= AC_CURRENT_NOISE_A && abs(acPower) <= AC_POWER_NOISE_W);

    if (!pzemOnline) acVoltage = 0.0;
    if (loadLooksOff) {
      acCurrent = 0.0;
      acPower = 0.0;
      acPf = 0.0;
    } else if (isnan(acPf)) {
      acPf = 0.0;
    }

    Firebase.setFloat(fbdo_fan, "/KOFERT_Unit_1/current_metrics/voltage",      acVoltage);
    Firebase.setFloat(fbdo_fan, "/KOFERT_Unit_1/current_metrics/current",      acCurrent);
    Firebase.setFloat(fbdo_fan, "/KOFERT_Unit_1/current_metrics/power",        acPower);
    Firebase.setFloat(fbdo_fan, "/KOFERT_Unit_1/current_metrics/power_factor", acPf);
    Firebase.setString(fbdo_fan, "/KOFERT_Unit_1/current_metrics/load_status",
                       !pzemOnline ? "pzem_offline" : (loadLooksOff ? "load_off" : "active"));
    // ADD: energy + frequency. Keep the last valid RTDB value if PZEM is offline.
    if (!isnan(acEnergy)) Firebase.setFloat(fbdo_fan, "/KOFERT_Unit_1/current_metrics/energy",    acEnergy);
    if (!isnan(acFreq))   Firebase.setFloat(fbdo_fan, "/KOFERT_Unit_1/current_metrics/frequency", acFreq);

    // ── UNIT 2 & 3 : DC (INA219) ────────────────────────────────────────────
    float fanVoltage  = 0.0, fanCurrent  = 0.0, fanPower  = 0.0;
    float pumpVoltage = 0.0, pumpCurrent = 0.0, pumpPower = 0.0;

    if (isIna40Ready) {
      fanVoltage = ina219_0x40.getBusVoltage_V();
      fanCurrent = ina219_0x40.getCurrent_mA() / 1000.0;
      fanPower   = ina219_0x40.getPower_mW()   / 1000.0; // mW → W
    }
    if (isIna41Ready) {
      pumpVoltage = ina219_0x41.getBusVoltage_V();
      pumpCurrent = ina219_0x41.getCurrent_mA() / 1000.0;
      pumpPower   = ina219_0x41.getPower_mW()   / 1000.0; // mW → W
    }

    // ADD: accumulate INA219 energy (W × 2s ÷ 3600 ÷ 1000 = kWh)
    const float DT_KWH = 2.0 / 3600000.0; // 2 seconds in kWh per watt
    if (isIna40Ready) ina40EnergyKwh += fanPower  * DT_KWH;
    if (isIna41Ready) ina41EnergyKwh += pumpPower * DT_KWH;

    // ADD: persist to flash every 5 min (avoid flash wear)
    if (++energySaveCounter >= 150) {
      energySaveCounter = 0;
      preferences.putFloat("fan_kwh",  ina40EnergyKwh);
      preferences.putFloat("pump_kwh", ina41EnergyKwh);
    }

    // Envoi Unit 2
    Firebase.setFloat(fbdo_fan, "/KOFERT_Unit_2/current_metrics/voltage", fanVoltage);
    Firebase.setFloat(fbdo_fan, "/KOFERT_Unit_2/current_metrics/current", fanCurrent);
    Firebase.setFloat(fbdo_fan, "/KOFERT_Unit_2/current_metrics/power",   fanPower);
    Firebase.setFloat(fbdo_fan, "/KOFERT_Unit_2/current_metrics/energy",  ina40EnergyKwh); // ADD

    // Envoi Unit 3
    Firebase.setFloat(fbdo_fan, "/KOFERT_Unit_3/current_metrics/voltage",  pumpVoltage);
    Firebase.setFloat(fbdo_fan, "/KOFERT_Unit_3/current_metrics/current",  abs(pumpCurrent));
    Firebase.setFloat(fbdo_fan, "/KOFERT_Unit_3/current_metrics/power",    pumpPower);
    Firebase.setFloat(fbdo_fan, "/KOFERT_Unit_3/current_metrics/energy",   ina41EnergyKwh); // ADD
    Firebase.setInt  (fbdo_fan, "/KOFERT_Unit_3/current_metrics/water_level", globalWaterPercent);

    // ADD: ISO timestamp for all units
    String ts = getIsoTimestamp();
    if (ts.length() > 0) {
      Firebase.setString(fbdo_fan, "/KOFERT_Unit_1/current_metrics/timestamp", ts);
      Firebase.setString(fbdo_fan, "/KOFERT_Unit_2/current_metrics/timestamp", ts);
      Firebase.setString(fbdo_fan, "/KOFERT_Unit_3/current_metrics/timestamp", ts);
    }

    // Serial monitor (unchanged)
    Serial.println("\n==================================================");
    Serial.println("[UNIT 1 - RESEAU ALIMENTATION GENERALE AC]");
    if (pzemOnline) {
      Serial.printf("  -> Tension     : %.1f V\n",  acVoltage);
      Serial.printf("  -> Intensite   : %.2f A\n",  acCurrent);
      Serial.printf("  -> Puissance   : %.1f W\n",  acPower);
      Serial.printf("  -> Facteur Pf  : %.2f\n",    acPf);
      Serial.printf("  -> Etat charge : %s\n",      loadLooksOff ? "OFF" : "ACTIVE");
      Serial.printf("  -> Energie     : %.3f kWh\n", isnan(acEnergy) ? 0.0f : acEnergy);
      Serial.printf("  -> Frequence   : %.1f Hz\n",  isnan(acFreq)   ? 0.0f : acFreq);
    } else {
      Serial.println("  -> [ERREUR] PZEM-004T introuvable, courant force a 0A dans RTDB.");
    }
    Serial.println("[UNIT 2 - VENTILATION]");
    Serial.printf("  -> %.2fV  %.3fA  %.2fW  Cumulé: %.5f kWh\n",
                  fanVoltage, fanCurrent, fanPower, ina40EnergyKwh);
    Serial.println("[UNIT 3 - POMPE]");
    Serial.printf("  -> %.2fV  %.3fA  %.2fW  Cumulé: %.5f kWh\n",
                  pumpVoltage, abs(pumpCurrent), pumpPower, ina41EnergyKwh);
    Serial.printf("  -> Reservoir: %d%%   Pompe: %s\n",
                  globalWaterPercent, lastPumpStatus.c_str());
    Serial.println("==================================================");
  }

  delay(30);
}
