# Quy Trình Porting & Chạy Dự Án Này Trên Máy Local

> Mục tiêu: Hướng dẫn đầy đủ để bạn clone repo, dựng Docker stack, chạy FastAPI + MQTT + PostgreSQL + Flutter Web, và (tuỳ chọn) thay thiết bị giả lập bằng ESP32.

---
## 1. Tổng Quan Kiến Trúc
```
(sim_device.py hoặc ESP32) → MQTT Broker (EMQX) → Ingestor → PostgreSQL → FastAPI API → Flutter App (REST + MQTT WebSocket)
                                       ↘── /devices/{device_uid}/command ── MQTT commands → thiết bị
```
- Telemetry realtime: MQTT topic `t0/devices/{uid}/telemetry`.
- Lịch sử / truy vấn: REST endpoint `/telemetry/{device_uid}`.
- Command xuống thiết bị: REST → publish MQTT `t0/devices/{uid}/commands`.

---
## 2. Yêu Cầu Trước Khi Bắt Đầu
| Thành phần | Windows | Linux | Ghi chú |
|------------|---------|-------|--------|
| Docker Engine / Desktop | Cài Docker Desktop | `sudo apt install docker.io docker-compose-plugin` | Compose v2 bắt buộc |
| Python 3.12 (tuỳ chọn) | Winget / Python.org | Package manager | Chỉ dùng nếu chạy script ngoài Docker |
| Flutter SDK | Website / `choco install flutter` | `snap install flutter --classic` | Dùng cho UI Web/Mobile |
| PlatformIO (ESP32) | VS Code Extension | VS Code Extension | Tuỳ chọn khi dùng ESP32 |

Kiểm tra cài đặt:
```powershell
# Docker
docker --version
# Flutter
flutter --version
```

---
## 3. Clone Repo & Chuẩn Bị Môi Trường
```powershell
git clone <repo-url> mqtt_fastapi_postgres_flutter_demo
cd mqtt_fastapi_postgres_flutter_demo
```
Tạo file `.env` nếu cần (ví dụ):
```
POSTGRES_DB=iot
POSTGRES_USER=iot
POSTGRES_PASSWORD=secret
JWT_SECRET=dev-secret
MQTT__HOST=emqx
MQTT__PORT=1883
DATABASE_URL=postgresql+asyncpg://iot:secret@db:5432/iot
```

---
## 4. Khởi Chạy Docker Stack
```powershell
docker compose up -d --build
docker compose ps
```
Port mặc định:
- FastAPI: `8000`
- EMQX: `1883 (MQTT)`, `8083 (WebSocket)`, `18083 (Dashboard)`
- PostgreSQL: `5432`

Kiểm tra log nhanh:
```powershell
docker compose logs api --tail 40
docker compose logs ingestor --tail 40
```
Nếu lỗi pipe / engine: mở Docker Desktop trước rồi chạy lại.

---
## 5. Mô Phỏng Thiết Bị (Python)
```powershell
python .\sim_device.py
```
Script gửi retained status + telemetry tuần tự với `msg_id` tăng dần. Ingestor sẽ ghi vào DB.

Xem dữ liệu:
```powershell
$body = @{email='demo@example.com'; password='x'} | ConvertTo-Json
$login = Invoke-RestMethod http://localhost:8000/auth/login -Method Post -Body $body -ContentType 'application/json'
$token = $login.access_token
Invoke-RestMethod http://localhost:8000/telemetry/dev-01 -Headers @{Authorization="Bearer $token"}
```

---
## 6. Chạy Flutter App (Web)
### 6.1 Cài dependency
```powershell
cd flutter_app
flutter pub get
```
### 6.2 Bật Web Support (nếu chưa có)
Nếu lần đầu chạy mà báo `No pubspec.yaml` hoặc `not configured to build on the web`, nguyên nhân thường là:
1. Chạy sai thư mục (phải ở `flutter_app`).
2. Chưa bật web hoặc chưa scaffold platform.

Khắc phục:
```powershell
flutter config --enable-web
flutter create .   # thêm thư mục web/, ios/, android/ nếu thiếu
flutter run -d chrome --web-port=5173
```
Mở trình duyệt: `http://localhost:5173` (hoặc URL Flutter in ra).

### 6.3 Sử dụng UI
- Nhấn "Login REST" → nhận JWT (gọi `/auth/login`).
- Nhấn "Connect MQTT" → kết nối WebSocket `ws://localhost:8083/mqtt` và subscribe:
  - `t0/devices/+/status`
  - `t0/devices/dev-01/telemetry`
- Log hiển thị message realtime.

Nếu chạy trên thiết bị di động thật: thay `localhost` bằng IP LAN máy host trong `lib/main.dart`.

---
## 7. Gửi Command MQTT Từ API
```powershell
$cmdBody = @{cmd='led_on'; params=@{duration=5}} | ConvertTo-Json
Invoke-RestMethod http://localhost:8000/devices/dev-01/command -Method Post -Headers @{Authorization="Bearer $token"} -Body $cmdBody -ContentType 'application/json'
```
Thiết bị hoặc simulator cần subscribe `t0/devices/dev-01/commands`.

---
## 8. Thay Thiết Bị Mô Phỏng Bằng ESP32 (Tuỳ Chọn)
Tóm tắt (chi tiết xem `README_ESP32.md`):
1. Mở `esp32/ESP32/platformio.ini` → đã khai báo `PubSubClient`, `ArduinoJson`.
2. Sửa `src/main.cpp` với Wi-Fi + IP broker (IP máy host Docker).
3. Flash:
```powershell
cd esp32/ESP32
pio run --target upload
pio device monitor
```
4. Xác nhận log `[telemetry] sent ...` và kiểm tra `/telemetry/dev-esp32-01`.

---
## 9. Kiểm Tra & Xác Nhận Pipeline
| Bước | OK Khi | Lệnh kiểm tra |
|------|--------|---------------|
| Docker lên | Container trạng thái Up | `docker compose ps` |
| Telemetry | REST trả dữ liệu JSON | `Invoke-RestMethod /telemetry/dev-01` |
| Command | API trả `{status: sent}` | `Invoke-RestMethod /devices/dev-01/command` |
| MQTT realtime | Log Flutter hiển thị message | Mở UI và xem logs |
| ESP32 (tuỳ chọn) | Serial log + REST thấy device mới | `pio device monitor` + REST |

---
## 10. Troubleshooting Nhanh
| Vấn đề | Nguyên nhân | Giải pháp |
|--------|-------------|-----------|
| `No pubspec.yaml` | Chạy sai thư mục | `cd flutter_app` rồi chạy lại |
| Web not configured | Chưa scaffold web | `flutter config --enable-web && flutter create .` |
| Không login được | API chưa chạy | Kiểm tra `docker compose logs api` |
| Không nhận telemetry | Ingestor chưa subscribe / EMQX chưa sẵn sàng | Chờ vài giây, xem log ingestor |
| Duplicate telemetry | `msg_id` lặp lại | Đảm bảo thiết bị tạo `msg_id` duy nhất |
| MQTT WebSocket fail | Sai port hoặc host | Dùng `ws://localhost:8083/mqtt` đúng container mapping |
| ESP32 không kết nối | Sai IP broker / Wi-Fi | Ping IP, kiểm tra firewall port 1883 |

---
## 11. Khác Biệt Windows vs Linux
| Tác vụ | Windows | Linux |
|--------|---------|-------|
| Set env tạm | `$env:VAR=value` | `export VAR=value` |
| Đường dẫn | `C:\...` | `/home/...` |
| Serial monitor (PlatformIO) | VS Code terminal | VS Code terminal |
| Quyền cổng thấp | Không thường gặp | Có thể cần `sudo` |

---
## 12. Dọn Dẹp / Reset
```powershell
docker compose down -v   # Xoá containers + volume (reset DB)
docker image prune -f    # Xoá dangling images
```
Rebuild sạch:
```powershell
docker compose up -d --build
```

---
## 13. Tài Liệu Liên Quan
| File | Nội dung |
|------|----------|
| `README.md` | Tổng quan nhanh toàn bộ hệ thống |
| `docs/README_DOCKER.md` | Chi tiết Docker & vận hành |
| `docs/README_FASTAPI.md` | Giải thích API, auth, cấu trúc code |
| `docs/README_MQTT.md` | MQTT topics, QoS, best practices |
| `docs/README_POSTGRES.md` | DB, schema, tối ưu |
| `docs/README_HTTP_vs_MQTT.md` | So sánh HTTP vs MQTT |
| `docs/README_BACKEND_OVERVIEW.md` | Tóm tắt backend nhanh |
| `docs/README_ESP32.md` | Hướng dẫn ESP32 thật |
| `docs/README_HTTPS.md` | Thiết lập HTTPS/MQTTS |

---
## 14. Checklist Cuối Cùng (Done Khi ✅)
- [ ] Docker stack chạy (api, emqx, db, ingestor lên).
- [ ] Login REST thành công (JWT nhận được).
- [ ] Telemetry được hiển thị qua REST và realtime qua Flutter.
- [ ] Command gửi xuống thiết bị/SIM thành công.
- [ ] (Tuỳ chọn) ESP32 publish thấy trong hệ thống.

---
## 15. Kết Luận
Bạn đã nắm toàn bộ chu trình porting: từ clone → khởi chạy Docker → mô phỏng thiết bị → chạy UI → chuyển sang thiết bị thật. Khi mở rộng thêm (TLS, scale ingestor, phân quyền MQTT), tham khảo các file docs tương ứng.

Chúc bạn thành công!
