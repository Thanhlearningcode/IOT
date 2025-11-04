<div align="center">

# Tutorial A‑Z: MQTT ↔ FastAPI ↔ PostgreSQL ↔ Flutter

---

## 0. Cài đặt & Chuẩn Bị

Tóm tắt nhanh:
- Cài Docker → `docker compose up -d --build`.

---

Repository này cung cấp một kiến trúc mẫu nhỏ gọn để bạn học nhanh cách kết hợp:
- EMQX (MQTT broker) cho giao tiếp thiết bị / realtime.
- Python FastAPI cho REST API (login, truy vấn telemetry).
- PostgreSQL làm kho lưu trữ và ràng buộc UNIQUE để tránh trùng dữ liệu.
- Ingestor asyncio (worker) subscribe MQTT và ghi DB.
- Flutter Web hiển thị realtime qua MQTT WebSocket và đọc lịch sử qua REST.

Mục tiêu: bạn chỉ cần vài lệnh là chạy được end‑to‑end.

---

## 2. Kiến trúc tổng quan

```
 ┌────────────┐   Publish (QoS1)   t0/devices/dev-01/telemetry
 │  Sim Device│ ─────────────────────────────────────────────────┐
 └────────────┘                                                   │ JSON { msg_id, ts, data.temp }
																																	v
												+-----------------------+        +------------------+
	 t0/devices/+/telemetry subscribe (QoS1) --->  | EMQX Broker (1883/8083) | <-- MQTT WS (Flutter)
												+-----------------------+        +------------------+
																	│                               ^
																	│                               │ Retained status
																	v                               │ t0/devices/+/status
											 +-------------------------+                │
											 | Ingestor (asyncio-mqtt) |                │
											 +-------------------------+                │
												| PostgreSQL (telemetry) | <---- | FastAPI REST (JWT)   |
												+------------------------+       +----------------------+
																			 ^                            │
																			 │  /telemetry/{device_uid}   │ Login /auth/login
																			 └────────────────────────────┘
```

### Topic quy ước
- `t0/devices/{uid}/status` (retained) — thiết bị online/offline.
- `t0/devices/{uid}/telemetry` — dữ liệu thời gian thực.

### Bảng cổng & dịch vụ
| Service | Cổng ngoài | Mô tả |
|---------|-----------|-------|
| EMQX TCP | 1883 | MQTT TCP thiết bị / tool |
| EMQX WS  | 8083 | MQTT WebSocket cho trình duyệt Flutter (path /mqtt) |
| EMQX UI  | 18083 | Dashboard quản trị |
| FastAPI  | 8000 | REST API / Swagger |
| Postgres | 5432 | CSDL |


## 3. Thành phần chi tiết
| File | Vai trò |
|------|---------|
| `backend/app/models.py` | Định nghĩa bảng `User`, `Device`, `Telemetry` (UNIQUE (device_uid,msg_id)). |
| `backend/app/auth.py` | JWT tối giản: cho phép login với email bất kỳ (demo). |
| `backend/ingestor/run.py` | Worker subscribe topic pattern và ghi DB. |
| `backend/app/mqtt_pub.py` | Hàm gửi command MQTT tới thiết bị. |

---


Tuỳ chọn: `curl`, `mqttx` hoặc `mosquitto_sub` để test nhanh.

---

## 5. Khởi động stack (DEV)
```powershell
docker compose up -d --build
```
```powershell
docker compose ps
docker logs mqtt_fastapi_postgres_flutter_demo-api-1 --tail 20
docker logs mqtt_fastapi_postgres_flutter_demo-ingestor-1 --tail 20
```
Swagger: http://localhost:8000/docs  
EMQX UI: http://localhost:18083  (Dev: anonymous đang bật — đừng dùng cho production)

---

## 6. Mô phỏng thiết bị
Script `sim_device.py` gửi:
```json
{
	"msg_id": "0001",
	"ts": 1730700000,
}
```
Chạy:
```powershell
python .\sim_device.py
```
Thiết bị publish retained status trước: `t0/devices/dev-01/status` để client mới subscribe thấy ngay.

---

## 7. Dòng dữ liệu End-to-End

Sequence khi telemetry xuất hiện:
```
Device → EMQX → Ingestor → PostgreSQL → FastAPI → Flutter (HTTP lịch sử)
```
Chi tiết:
1. Thiết bị publish JSON lên `t0/devices/dev-01/telemetry` (QoS1).
2. EMQX broker chuyển tiếp đến Ingestor (subscribe pattern `t0/devices/+/telemetry`).
3. Ingestor parse, tạo `msg_id` nếu thiếu (UUID), ghi bản ghi vào bảng `telemetry`; nếu trùng UNIQUE bỏ qua.
4. Người dùng truy vấn lịch sử qua `GET /telemetry/dev-01` (giới hạn 100 gần nhất).
5. Flutter đồng thời subscribe WebSocket MQTT `t0/devices/dev-01/telemetry` để thấy dữ liệu mới ngay lập tức.

---

## 8. API chi tiết
| Method | Endpoint | Mô tả |
|--------|----------|-------|
| POST | `/auth/login` | Nhận `email`, trả về JWT demo (không kiểm tra mật khẩu). |
| GET | `/telemetry/{device_uid}` | Lấy tối đa 100 telemetry gần nhất. |

Login Flow:

---

## 9. Ingestor & MQTT
File `backend/ingestor/run.py` sử dụng `asyncio-mqtt`:
- Tự động reconnect khi lỗi (`MqttError`).
- Dùng `unfiltered_messages()` để lắng nghe mọi topic đã subscribe.
- Bảo đảm tồn tại `Device` trước khi ghi `Telemetry` (tạo nếu chưa có).
- Unique `(device_uid,msg_id)` bảo vệ chống ghi trùng.
Chuyển đổi tương lai: thay `asyncio-mqtt` (deprecated) bằng `aiomqtt` + sửa API subscribe.

Publish command ví dụ (server → thiết bị) qua `mqtt_pub.py`:
---

## 10. Ứng dụng Flutter
`flutter_app/lib/main.dart`:
- Login REST để lấy JWT và lưu vào Header cho các request sau.
- Tạo `MqttServerClient` với WebSocket: host `localhost`, port `8083`, path `/mqtt` (Flutter lib tự thêm path khi `useWebSocket = true`).
- Subscribe wildcard `t0/devices/+/status` để thấy retained status.
- Subscribe cụ thể `t0/devices/dev-01/telemetry`.
- Hiển thị log chuỗi đơn giản — bạn có thể nâng cấp thành biểu đồ nhiệt độ.

Chạy:
```powershell
cd .\flutter_app
flutter pub get
flutter run -d chrome
```
Nếu chạy trên thiết bị di động thật: đổi `localhost` → IP LAN của máy chạy Docker (ví dụ `192.168.1.10`).

## 11. Bảo mật & Production
| Chủ đề | DEV (hiện tại) | PROD gợi ý |
|--------|----------------|------------|
| JWT | Tùy ý email | Thực hiện đăng nhập thực, lưu user/password hash (bcrypt) |
| DB Migrations | Auto create tables | Dùng Alembic migrations |
| CORS | `*` | Chỉ domain ứng dụng |
| Reload Uvicorn | Bật `--reload` | Tắt để giảm overhead |
| Telemetry Scaling | 1 ingestor | Nhiều ingestor + shared subscription `$share/ingestors/t0/devices/+/telemetry` |
| Observability | Chưa có | Thêm Prometheus, logs tập trung (ELK / Loki) |
| Data Lifecycle | Không dọn | Partition theo ngày/tháng, TTL hoặc archive |

---

## 12. Troubleshooting (Các lỗi thường gặp)
| Vấn đề | Nguyên nhân | Cách xử lý |
| 404 / không vào `/docs` | Container API crash | Kiểm tra `docker logs ...-api-1` |
| ImportError email-validator | Chưa cài dependency | Đã fix bằng thêm `email-validator` vào requirements |


## 13. Nâng cấp tương lai
- Chuyển `asyncio-mqtt` sang `aiomqtt` (repo mới). 
- Thêm `/health` endpoint và `/metrics` Prometheus.
- Caching layer (Redis) cho truy vấn lịch sử gần nhất.
- Gửi command ngược về thiết bị và chờ phản hồi (request/response pattern MQTT).
- WebSocket REST (FastAPI + `websockets`) để stream dữ liệu đã qua xử lý.

---

## 14. Phụ lục lệnh hữu ích
```powershell
# Liệt kê containers
docker compose ps

# Publish thử lệnh điều khiển (bên trong script tùy chỉnh) 
# (ví dụ chạy một file Python sử dụng mqtt_pub.publish_command)

# Dọn dẹp
docker compose down -v
```

---

## 15. Ghi chú triển khai & Dependencies
`backend/requirements.txt` đã bao gồm:
```
fastapi
pydantic
python-jose[cryptography]
asyncio-mqtt (deprecated → xem aiomqtt)
email-validator
```

Lý do pin `paho-mqtt==1.6.1`: giữ API tương thích với phiên bản `asyncio-mqtt` đang dùng.
1. Khởi động stack.
2. Chạy `sim_device.py`.
3. Swagger login → lấy token → gọi `/telemetry/dev-01` thấy dữ liệu.
Nếu OK: bạn đã có pipeline hoàn chỉnh.


## 17. Dọn dẹp & Reset dữ liệu
```powershell
docker compose down -v
docker compose up -d --build
```
(Xoá volume để DB sạch.)

---
## 18. FAQ nhanh
| Hỏi | Đáp |
|-----|-----|
| Vì sao dùng UNIQUE (device_uid,msg_id)? | Tránh ghi trùng telemetry khi thiết bị retry QoS1. |
| Có cần ACK custom không? | QoS1 đủ cho demo; sản xuất có thể thêm logic xác nhận lệnh. |
| Tại sao JWT không lưu DB? | Demo tối giản; thực tế cần bảng phiên / refresh token. |
| Vì sao reload bật? | Để dev code thay đổi tự restart; prod nên tắt. |

---

### Kết luận
Bạn có thể dùng repo này làm nền để mở rộng hệ thống IoT / realtime. Hãy nâng cấp dần: bảo mật, hiệu năng, quan sát và khả năng mở rộng.

Chúc bạn học tốt! 🚀
\n+---
\n+## 19. Triển khai Production Trên Server Thật (Hướng dẫn chi tiết)
Phần này giúp bạn đưa hệ thống lên một VPS / máy chủ Linux (Ubuntu 22.04 ví dụ) với domain và HTTPS.
\n+### 19.1. Mục tiêu
- Chạy stack Docker lâu dài, tự động khởi động lại.
- Bảo mật cơ bản (JWT, EMQX auth, tường lửa, TLS).
- Reverse proxy (Nginx) cho API và EMQX WebSocket.
- Sao lưu định kỳ PostgreSQL.
- Giám sát & log tối thiểu.
\n+### 19.2. Chuẩn bị server
1. Cập nhật hệ thống:
```bash
sudo apt update && sudo apt upgrade -y
```
2. Cài tiện ích:
```bash
sudo apt install -y curl git ufw nginx certbot python3-certbot-nginx
```
3. Cài Docker & Compose Plugin:
```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker
docker compose version
```
4. Mở firewall (UFW) chỉ cần HTTP/HTTPS + MQTT nếu thiết bị kết nối trực tiếp:
```bash
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
# Nếu thiết bị dùng TCP MQTT trực tiếp:
sudo ufw allow 1883/tcp
sudo ufw enable
sudo ufw status
```
\n+### 19.3. Lấy mã nguồn trên server
```bash
git clone https://your.repo/mqtt_fastapi_postgres_flutter_demo.git
cd mqtt_fastapi_postgres_flutter_demo
```
\n+### 19.4. Điều chỉnh `docker-compose.yml` (gợi ý)
Thêm volumes để dữ liệu bền vững:
```yaml
services:
	db:
		image: postgres:16
		volumes:
			- pg_data:/var/lib/postgresql/data
	emqx:
		image: emqx:5.8.2
		# Prod: bật auth, tắt anonymous
		environment:
			- EMQX_ALLOW_ANONYMOUS=false
			- EMQX_DASHBOARD_DEFAULT_USERNAME=admin
			- EMQX_DASHBOARD_DEFAULT_PASSWORD=ThayMatKhau#2025
volumes:
	pg_data:
```
Tắt reload trong API (Dockerfile hoặc compose): bỏ `--reload` để tránh tạo process phụ.
\n+### 19.5. Thiết lập biến môi trường (file `.env` – không commit)
```env
JWT_SECRET=ChuoiBiMatDaiHon_ChangeMe_2025!
DATABASE_URL=postgresql+asyncpg://app:secret@db:5432/app
MQTT__HOST=emqx
MQTT__WS_URL=ws://emqx:8083/mqtt
MQTT__PORT=1883
MQTT__TOPIC=t0/devices/+/telemetry
```
Trong `docker-compose.yml` thêm: `env_file: .env` cho các service cần.
\n+### 19.6. Khởi động stack
```bash
docker compose pull
docker compose up -d --build
docker compose ps
```
\n+### 19.7. Reverse Proxy Nginx
Giả sử domain: `api.iot.example.com` (REST) và `mqtt.iot.example.com` (WebSocket MQTT). 
Tạo file: `/etc/nginx/sites-available/iot.conf`:
```nginx
server {
		listen 80;
		server_name api.iot.example.com;
		location / {
				proxy_pass http://127.0.0.1:8000;
				proxy_set_header Host $host;
				proxy_set_header X-Real-IP $remote_addr;
				proxy_set_header Upgrade $http_upgrade;
				proxy_set_header Connection "upgrade";
		}
}

server {
		listen 80;
		server_name mqtt.iot.example.com;
		location /mqtt {
				proxy_pass http://127.0.0.1:8083/mqtt;
				proxy_set_header Upgrade $http_upgrade;
				proxy_set_header Connection "upgrade";
		}
}
```
Kích hoạt và test:
```bash
sudo ln -s /etc/nginx/sites-available/iot.conf /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```
\n+### 19.8. HTTPS với Let's Encrypt
```bash
sudo certbot --nginx -d api.iot.example.com -d mqtt.iot.example.com --agree-tos -m admin@example.com --redirect
```
Certbot sẽ tự tạo vhost TLS. Sau đó WebSocket dùng `wss://mqtt.iot.example.com/mqtt`.
\n+### 19.9. Thiết bị kết nối qua TLS (tuỳ chọn nâng cao)
- Bật listener TLS trong EMQX (Ports 8883 / 8084).
- Cấp chứng chỉ server (Certbot) và nếu cần mutual TLS thì tạo CA riêng cấp cho client.
\n+### 19.10. Systemd quản lý Docker Compose (tuỳ chọn)
Tạo unit `/etc/systemd/system/iot-stack.service`:
```ini
[Unit]
Description=IoT Stack
After=network-online.target docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/mqtt_fastapi_postgres_flutter_demo
ExecStart=/usr/bin/docker compose up -d --build
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
```
Kích hoạt:
```bash
sudo mv ~/mqtt_fastapi_postgres_flutter_demo /opt/
sudo systemctl daemon-reload
sudo systemctl enable --now iot-stack.service
```
\n+### 19.11. Sao lưu PostgreSQL
Script đơn giản `/opt/pg_backup.sh`:
```bash
#!/usr/bin/env bash
DATE=$(date +%Y%m%d_%H%M)
docker exec mqtt_fastapi_postgres_flutter_demo-db-1 pg_dump -U app app > /opt/backup/pg_${DATE}.sql
find /opt/backup -type f -mtime +7 -delete
```
```bash
sudo mkdir -p /opt/backup && sudo chmod 700 /opt/backup
sudo chmod +x /opt/pg_backup.sh
```
Thêm cron:
```bash
crontab -e
0 2 * * * /opt/pg_backup.sh
```
\n+### 19.12. Giám sát & Logs
- Dùng `docker logs -f <container>` tạm thời.
- Thêm Prometheus + exporters (node_exporter, postgres_exporter) khi mở rộng.
- Centralize logs: Fluent Bit → ELK hoặc Loki + Grafana.
\n+### 19.13. Tối ưu hiệu năng
- Index thêm: `CREATE INDEX ON telemetry (device_uid, ts DESC);`
- Partition theo thời gian: tạo bảng con theo tháng.
- Batch insert trong ingestor (gom N messages trước khi commit) khi tần suất cao.
\n+### 19.14. Checklist Production Nhanh
| Mục | Done? |
|-----|-------|
| JWT_SECRET đủ mạnh | ☐ |
| EMQX anonymous OFF | ☐ |
| Volumes DB + backup | ☐ |
| HTTPS / certificates | ☐ |
| Firewall đóng cổng thừa | ☐ |
| Log rotation / backup | ☐ |
| Giám sát cơ bản | ☐ |
| Script backup chạy OK | ☐ |
| Tắt uvicorn reload | ☐ |
| Migration (Alembic) áp dụng | ☐ |
\n+### 19.15. Mẹo bảo mật nhỏ
- Không dùng mặc định `admin/public` cho EMQX Dashboard.
- Giới hạn password vào EMQX: độ dài > 12, tránh reuse.
- Bật `rate limit` hoặc gateway bảo vệ API nếu public.
- Sử dụng `Fail2ban` nếu có endpoint đăng nhập thật.
\n+### 19.16. Cập nhật định kỳ
```bash
docker compose pull
docker compose up -d
docker image prune -f
```
Đảm bảo backup gần nhất trước khi cập nhật lớn.
\n+### 19.17. Nâng cấp sau cùng
- Triển khai Canary cho ingestor (2 version chạy song song).
- Thêm tracing OpenTelemetry.
- Kết hợp Redis Pub/Sub để fanout message đã xử lý.
\n+---
\n+Hết phần triển khai production. Bạn có thể điều chỉnh tuỳ theo yêu cầu thực tế (multi-region, HA, scaling). Nếu cần script đầy đủ bật TLS cho MQTT hoặc config Alembic, yêu cầu thêm nhé.
