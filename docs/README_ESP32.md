# ESP32 Integration Guide

> Hướng dẫn thay thiết bị mô phỏng (`sim_device.py`) bằng ESP32 thật để gửi telemetry vào hệ thống MQTT ↔ FastAPI ↔ PostgreSQL.

---
## 1. Chuẩn bị phần cứng & phần mềm
- ESP32 DevKit (ví dụ DOIT ESP32 DEVKIT V1).
- Cáp USB Type-C hoặc Micro USB tuỳ board.
- Laptop chạy Docker stack (EMQX, FastAPI, PostgreSQL).
- PlatformIO (plugin trong VS Code hoặc CLI `pip install platformio`).
- Thư viện Arduino cho ESP32 (PlatformIO tự tải).

Kiểm tra Docker stack chạy: `docker compose up -d --build`.
IP máy host (broker) lấy qua `ipconfig` (Windows) / `ip addr` (Linux).

---
## 2. Cấu trúc project PlatformIO
```
esp32/
  ESP32/
    platformio.ini
    src/
      main.cpp
    lib/
```
Nếu chưa có PlatformIO: `pio project init --board esp32doit-devkit-v1 --project-dir esp32/ESP32`.

Thêm thư viện MQTT & JSON trong `platformio.ini`:
```ini
[env:esp32doit-devkit-v1]
platform = espressif32
board = esp32doit-devkit-v1
framework = arduino
monitor_speed = 115200
lib_deps =
  knolleary/PubSubClient @ ^2.8
  bblanchon/ArduinoJson @ ^7.0.4
```

Cài thư viện: `pio pkg install --project-dir esp32/ESP32` (hoặc build sẽ tự kéo).

---
## 3. Code chính (`src/main.cpp`)
- Kết nối Wi-Fi STA (điền `WIFI_SSID`, `WIFI_PASS`).
- Thiết lập MQTT tới EMQX (địa chỉ LAN, port 1883).
- Publish JSON telemetry mỗi 5 giây lên `t0/devices/{DEVICE_UID}/telemetry`.
- Subscribe `t0/devices/{DEVICE_UID}/commands` để nhận lệnh (ví dụ bật/tắt LED).

Điểm chính trong code:
```cpp
static const char *MQTT_HOST = "192.168.1.50";  // IP laptop chạy EMQX
static const char *DEVICE_UID = "dev-esp32-01";
...
void publishTelemetry() {
  StaticJsonDocument<256> doc;
  doc["msg_id"] = millis();
  doc["temp_c"] = 24.5 + random(-50, 50) / 10.0;
  mqttClient.publish("t0/devices/dev-esp32-01/telemetry", buffer, len);
}
```
- Giữ `msg_id` khác nhau (dùng `millis()`); backend dùng để chống trùng.
- `handleCommand` nhận `cmd` → điều khiển `LED_BUILTIN`.

Đừng quên sửa `WIFI_SSID`, `WIFI_PASS`, `MQTT_HOST`, `DEVICE_UID` trước khi flash.

---
## 4. Build & flash
```powershell
cd esp32/ESP32
pio run                # build
pio run --target upload  # flash (đã cắm ESP32)
pio device monitor       # xem serial 115200
```
Nếu gặp lỗi driver: cài CP210x/CH340 tuỳ board.

---
## 5. Kiểm tra dữ liệu trong hệ thống
1. Đảm bảo EMQX (Docker) expose port 1883 và laptop & ESP32 cùng mạng LAN.
2. Mở `pio device monitor` → xem log `[telemetry] sent ...`.
3. Backend ingest → Postgres:
   ```powershell
   $token = (Invoke-RestMethod http://localhost:8000/auth/login -Method Post -Body '{"email":"demo@example.com","password":"x"}' -ContentType 'application/json').access_token
   Invoke-RestMethod http://localhost:8000/telemetry/dev-esp32-01 -Headers @{Authorization="Bearer $token"}
   ```
4. MQTT tool (MQTTX, mosquitto_sub): `mosquitto_sub -h 192.168.1.50 -t 't0/devices/dev-esp32-01/telemetry'` để xem trực tiếp.

---
## 6. Gửi command xuống ESP32
- Từ backend (mã đã có `/devices/{device_uid}/command`).
- Ví dụ PowerShell:
```powershell
$body = @{ cmd = 'led_on'; params = @{ duration = 5 } } | ConvertTo-Json
Invoke-RestMethod "http://localhost:8000/devices/dev-esp32-01/command" -Method Post -Headers @{Authorization="Bearer $token"} -Body $body -ContentType 'application/json'
```
- ESP32 sẽ hiện log và bật LED.

---
## 7. Troubleshooting
| Lỗi | Nguyên nhân | Cách xử lý |
|-----|-------------|------------|
| Không nối Wi-Fi | Sai SSID/PASS hoặc ngoài vùng phủ sóng | Kiểm tra `Serial` log, reset router |
| MQTT `failed rc=-2` | Sai IP/port, EMQX không reachable | Ping `MQTT_HOST`, mở firewall port 1883 |
| Backend không thấy dữ liệu | Chưa chạy Docker ingestor, msg_id trùng | `docker compose ps`, kiểm tra log ingestor |
| Lệnh không nhận | Chưa subscribe đúng topic | Đảm bảo `DEVICE_UID` trùng và broker gửi QoS1 |

---
## 8. Mở rộng
- Dùng TLS (port 8883): cập nhật chứng chỉ cho PubSubClient.
- Thêm cảm biến thực (DHT22, INA219) → đọc giá trị thật vào JSON.
- Gửi ack lên topic `.../command_ack`.
- Dùng `ESP32` deep sleep → publish theo chu kỳ, tiết kiệm pin.

---
## 9. Tài liệu tham khảo
- PubSubClient: https://pubsubclient.knolleary.net/
- ArduinoJson: https://arduinojson.org/
- EMQX Arduino sample: https://www.emqx.com/en/blog/esp32-connects-to-emqx-using-mqtt
- PlatformIO docs: https://docs.platformio.org/

---
## 10. Checklist nhanh
- [ ] Docker stack chạy (EMQX/FastAPI/Postgres).
- [ ] Sửa `main.cpp` với Wi-Fi/MQTT thực tế.
- [ ] ESP32 flash thành công, monitor thấy log.
- [ ] Topic telemetry có bản tin trong EMQX.
- [ ] `/telemetry/{device_uid}` trả dữ liệu.
- [ ] Command từ API đã kiểm chứng.

Hoàn tất: ESP32 gửi dữ liệu thật vào hệ thống, thay thế script mô phỏng. Khi cần, mở rộng cảm biến và logic điều khiển trực tiếp trên board.
