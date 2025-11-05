#include <WiFi.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>

// Thay bằng thông tin thật của bạn.
static const char *WIFI_SSID = "YOUR_WIFI_SSID";
static const char *WIFI_PASS = "YOUR_WIFI_PASSWORD";
static const char *MQTT_HOST = "192.168.1.50";  // IP máy chạy EMQX hoặc broker khác.
static const uint16_t MQTT_PORT = 1883;
static const char *DEVICE_UID = "dev-esp32-01";

WiFiClient wifiClient;
PubSubClient mqttClient(wifiClient);

unsigned long lastPublishMs = 0;
const unsigned long publishIntervalMs = 5000;  // gửi dữ liệu mỗi 5 giây.

void handleCommand(char *topic, byte *payload, unsigned int length) {
  StaticJsonDocument<256> doc;
  DeserializationError err = deserializeJson(doc, payload, length);
  if (err) {
    Serial.print("[command] invalid payload: ");
    Serial.println(err.c_str());
    return;
  }

  const char *command = doc["cmd"] | "";
  Serial.print("[command] topic: ");
  Serial.print(topic);
  Serial.print(" cmd: ");
  Serial.println(command);

  if (strcmp(command, "led_on") == 0) {
    digitalWrite(LED_BUILTIN, HIGH);
  } else if (strcmp(command, "led_off") == 0) {
    digitalWrite(LED_BUILTIN, LOW);
  }
}

void connectWifi() {
  Serial.print("[wifi] connecting to ");
  Serial.println(WIFI_SSID);
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print('.');
  }
  Serial.println();
  Serial.print("[wifi] connected, ip: ");
  Serial.println(WiFi.localIP());
}

void ensureMqtt() {
  while (!mqttClient.connected()) {
    Serial.print("[mqtt] connecting to ");
    Serial.print(MQTT_HOST);
    Serial.print(":");
    Serial.println(MQTT_PORT);

    String clientId = String("esp32-") + DEVICE_UID;
    if (mqttClient.connect(clientId.c_str())) {
      Serial.println("[mqtt] connected");
      String commandsTopic = String("t0/devices/") + DEVICE_UID + "/commands";
      mqttClient.subscribe(commandsTopic.c_str(), 1);
      Serial.print("[mqtt] subscribed: ");
      Serial.println(commandsTopic);
    } else {
      Serial.print("[mqtt] failed, rc=");
      Serial.print(mqttClient.state());
      Serial.println(" retry in 5 seconds");
      delay(5000);
    }
  }
}

void publishTelemetry() {
  StaticJsonDocument<256> doc;
  doc["msg_id"] = millis();
  doc["device_uid"] = DEVICE_UID;
  doc["temp_c"] = 24.5 + (random(-50, 50) / 10.0);
  doc["humidity"] = 55 + random(-10, 10);

  char buffer[256];
  size_t len = serializeJson(doc, buffer, sizeof(buffer));

  String telemetryTopic = String("t0/devices/") + DEVICE_UID + "/telemetry";
  bool ok = mqttClient.publish(telemetryTopic.c_str(), buffer, len);
  Serial.print("[telemetry] ");
  Serial.print(ok ? "sent" : "failed");
  Serial.print(" topic=");
  Serial.print(telemetryTopic);
  Serial.print(" payload=");
  Serial.println(buffer);
}

void setup() {
  pinMode(LED_BUILTIN, OUTPUT);
  digitalWrite(LED_BUILTIN, LOW);

  Serial.begin(115200);
  delay(100);
  randomSeed(esp_random());

  connectWifi();

  mqttClient.setServer(MQTT_HOST, MQTT_PORT);
  mqttClient.setCallback(handleCommand);
}

void loop() {
  if (WiFi.status() != WL_CONNECTED) {
    connectWifi();
  }

  if (!mqttClient.connected()) {
    ensureMqtt();
  }

  mqttClient.loop();

  const unsigned long now = millis();
  if (now - lastPublishMs >= publishIntervalMs) {
    lastPublishMs = now;
    publishTelemetry();
  }
}