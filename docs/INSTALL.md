# Hướng Dẫn Cài Đặt & Chuẩn Bị Môi Trường (Windows / Linux)

Tài liệu này tách riêng phần cài đặt từ README nhằm giúp bạn tập trung vào bước chuẩn bị trước khi chạy demo.

## Mục tiêu
Thiết lập toàn bộ công cụ để chạy: Docker stack (EMQX, Postgres, FastAPI, Ingestor), mô phỏng thiết bị Python, và UI Flutter Web.

## 1. Thành phần cần cài
| Thành phần | Mục đích | Bắt buộc? | Ghi chú |
|------------|----------|-----------|--------|
| Git | Lấy mã nguồn | Có | https://git-scm.com/downloads |
| Docker Desktop (Windows) / Docker Engine (Linux) | Chạy EMQX, Postgres, API, Ingestor | Có | Bật WSL2 backend (Windows) |
| Python 3.10+ | Chạy `sim_device.py` | Tuỳ chọn | https://www.python.org/downloads/ |
| Flutter SDK | Chạy UI Flutter Web | Tuỳ chọn | https://docs.flutter.dev |
| Chrome | Render Flutter Web | Có (nếu web) | Edge cũng được |
| MQTTX / mosquitto-clients | Test MQTT thủ công | Tuỳ chọn | MQTTX: https://mqttx.app |
| VS Code | Chỉnh sửa mã | Khuyến nghị | Extensions: Python, Dart |

## 2. Cài Git (Windows)
```powershell
git --version
```
Nếu chưa có: tải installer Git và cài với mặc định.

## 3. Cài Docker Desktop (Windows)
1. https://www.docker.com/products/docker-desktop
2. Bật WSL2 + Virtualization trong BIOS.
3. Mở Docker Desktop chờ trạng thái "Running".
4. Kiểm tra:
```powershell
docker version
docker compose version
```
Nếu lỗi pipe: restart Docker Desktop và mở PowerShell mới.

## 4. Cài Docker Engine (Ubuntu)
```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker
docker version
docker compose version
```

## 5. Cài Python (Windows)
- Tải Python, tick "Add to PATH".
- Kiểm tra:
```powershell
python --version
pip --version
```
- (Tuỳ chọn) Virtual env:
```powershell
python -m venv .venv
.\.venv\Scripts\activate
pip install paho-mqtt
```

## 6. Cài Flutter SDK (Windows)
1. Tải zip stable → giải nén `C:\src\flutter`.
2. Thêm `C:\src\flutter\bin` vào PATH.
3. Mở PowerShell mới:
```powershell
flutter --version
flutter doctor
```
Bỏ qua Android nếu chỉ web.

## 7. Cài Chrome
https://www.google.com/chrome/

## 8. Cài MQTTX / mosquitto-clients
- MQTTX: GUI tiện test.
- Ubuntu:
```bash
sudo apt install mosquitto-clients
mosquitto_sub -h localhost -t 't0/devices/+/telemetry' -v
```

## 9. Clone repository
```powershell
git clone https://your.repo/mqtt_fastapi_postgres_flutter_demo.git
cd mqtt_fastapi_postgres_flutter_demo
```

## 10. Khởi động backend stack
```powershell
docker compose up -d --build
docker compose ps
```
Logs nhanh:
```powershell
docker logs mqtt_fastapi_postgres_flutter_demo-api-1 --tail 20
docker logs mqtt_fastapi_postgres_flutter_demo-ingestor-1 --tail 20
```

## 11. Mô phỏng thiết bị (tuỳ chọn)
```powershell
python .\sim_device.py
```
Gửi ~20 telemetry JSON.

## 12. Flutter Web
```powershell
cd .\flutter_app
flutter pub get
flutter run -d chrome --web-port 5173
```
Browser: bấm "Login REST" → "Connect MQTT".

## 13. Kiểm tra REST + Telemetry
```powershell
$body = @{email='demo@example.com'; password='x'} | ConvertTo-Json
$resp = Invoke-RestMethod -Uri http://localhost:8000/auth/login -Method Post -Body $body -ContentType 'application/json'
$token = $resp.access_token
Invoke-RestMethod -Uri http://localhost:8000/telemetry/dev-01 -Headers @{Authorization="Bearer $token"}
```

## 14. Dừng & dọn dẹp
```powershell
docker compose down
# Xoá volumes (xoá DB):
docker compose down -v
```

## 15. Lỗi thường gặp
| Lỗi | Nguyên nhân | Khắc phục |
|-----|-------------|-----------|
| docker not recognized | PATH / Docker chưa chạy | Mở Docker Desktop, restart, shell mới |
| Pipe dockerDesktopLinuxEngine | Engine chưa lên | Chờ vài giây, restart Docker Desktop |
| flutter not recognized | PATH chưa thêm đúng | Thêm bin, mở shell mới |
| email-validator missing | requirements cũ | Pull code, rebuild compose |
| message_retry_set error | paho-mqtt v2.x | Pin `paho-mqtt==1.6.1` |
| MQTT WS fail | Sai path `/mqtt` | Dùng `ws://localhost:8083/mqtt` |
| Mobile không MQTT | Dùng localhost | Dùng IP LAN host Docker |
| WSL2 missing | Chưa cài backend Docker | `wsl --install` (admin PowerShell) |

## 16. Thứ tự tối thiểu chạy nhanh
1. Cài Docker.
2. `docker compose up -d --build`.
3. (Tuỳ chọn) Python → `sim_device.py`.
4. (Tuỳ chọn) Flutter → giao diện realtime.
5. Gọi `/auth/login` và `/telemetry/dev-01` kiểm tra.

## 17. Nâng cấp bảo mật dev nhanh
| Mục | Mặc định | Cải tiến |
|-----|----------|---------|
| JWT_SECRET | devsecret | Đặt chuỗi mạnh trong `.env` |
| EMQX anonymous | ON | OFF + user/password |
| CORS | * | Giới hạn domain |
| Uvicorn reload | ON | Tắt khi ổn định |


