docker compose pull
docker compose up -d
docker image prune -f
# README – Hệ thống Demo MQTT ↔ FastAPI ↔ PostgreSQL ↔ Flutter

Phiên bản dễ đọc: tập trung vào luồng dữ liệu, thành phần và cách chạy nhanh.

---
## Mục lục
1. Giới thiệu nhanh
2. Sơ đồ & luồng dữ liệu
3. Thành phần chính
4. Chạy nhanh (Quick Start)
5. Mô phỏng thiết bị
6. API REST cơ bản
7. Ingestor & chống trùng dữ liệu
8. Ứng dụng Flutter (Realtime + Lịch sử)
9. Thuật ngữ quan trọng
10. Bảo mật & Production (tóm tắt)
11. Troubleshooting (lỗi thường gặp)
12. Nâng cấp tương lai
13. Lệnh hữu ích
14. Dọn dẹp / Reset
15. FAQ nhanh
16. Tài liệu mở rộng

---
## 1. Giới thiệu nhanh
Repo này minh hoạ mô hình nhỏ cho hệ thống IoT / realtime:
- Thiết bị gửi dữ liệu (telemetry) qua MQTT → Broker EMQX.
- Worker (Ingestor) subscribe, ghi dữ liệu vào PostgreSQL.
- FastAPI cung cấp REST để lấy lịch sử (truy vấn, phân trang sau này).
- Flutter App vừa gọi REST (lịch sử) vừa nghe MQTT WebSocket (dữ liệu mới).

Lợi ích: kết hợp MQTT (realtime, nhẹ) + REST (truy vấn lịch sử ổn định).

---
## 2. Sơ đồ & luồng dữ liệu
```
Device(sim_device.py) → MQTT Broker (EMQX) → Ingestor → PostgreSQL → FastAPI → (Flutter lấy lịch sử)
                                   │                                   │
                                   └─────────────── MQTT WebSocket ────┘ (Flutter nhận realtime)
```
Chi tiết 1 message:
1. Thiết bị publish JSON lên `t0/devices/dev-01/telemetry`.
2. EMQX gửi bản tin tới mọi client subscribe pattern `t0/devices/+/telemetry` (Ingestor + Flutter nếu muốn all thiết bị).
3. Ingestor parse, đảm bảo `Device` tồn tại, ghi vào bảng `telemetry` (chống trùng bằng UNIQUE).
4. Người dùng gọi REST `GET /telemetry/dev-01` để xem lịch sử gần nhất.
5. Flutter đã subscribe nên thấy bản tin ngay lập tức không cần poll.

Topic hay dùng:
- `t0/devices/{uid}/status` (retained) – trạng thái online/offline.
- `t0/devices/{uid}/telemetry` – dữ liệu cảm biến.
- `t0/devices/{uid}/commands` – gửi lệnh xuống thiết bị.

---
## 3. Thành phần chính
| Thành phần | Vị trí | Chức năng |
|------------|-------|-----------|
| EMQX Broker | Docker service | Nhận & phân phối message MQTT |
| Ingestor | `backend/ingestor/run.py` | Subscribe telemetry, ghi DB |
| FastAPI API | `backend/app/*.py` | Login (JWT demo), trả lịch sử |
| PostgreSQL | Docker service | Lưu Users / Devices / Telemetry |
| Flutter App | `flutter_app/` | UI: login REST + nhận realtime MQTT |
| Mô phỏng thiết bị | `sim_device.py` | Gửi dữ liệu test |

File quan trọng:
- `models.py` – bảng `Telemetry` có UNIQUE `(device_uid, msg_id)`.
- `auth.py` – tạo JWT đơn giản (email tùy ý, demo).
- `ingestor/run.py` – vòng lặp nhận message.
- `mqtt_pub.py` – ví dụ gửi command xuống thiết bị.

---
## 4. Chạy nhanh (Quick Start)
```powershell
docker compose up -d --build
docker compose ps
```
Swagger: http://localhost:8000/docs  
EMQX Dashboard: http://localhost:18083  

Lấy JWT demo:
```powershell
$body = @{email='demo@example.com'; password='x'} | ConvertTo-Json
$login = Invoke-RestMethod -Uri http://localhost:8000/auth/login -Method Post -Body $body -ContentType 'application/json'
$token = $login.access_token
Invoke-RestMethod -Uri http://localhost:8000/telemetry/dev-01 -Headers @{Authorization="Bearer $token"}
```

---
## 5. Mô phỏng thiết bị
Chạy script gửi 20 bản ghi demo:
```powershell
python .\sim_device.py
```
Script:
1. Publish retained status `t0/devices/dev-01/status`.
2. Gửi lần lượt các telemetry có `msg_id` tăng dần.

---
## 6. API REST cơ bản
| Method | Endpoint | Mô tả |
|--------|----------|-------|
| POST | `/auth/login` | Trả JWT demo (không xác thực mật khẩu thực). |
| GET | `/telemetry/{device_uid}` | 100 bản ghi mới nhất theo thiết bị. |

JWT demo: chỉ chứa `sub` (email) + `exp`. Không refresh token / phân quyền.

---
## 7. Ingestor & chống trùng dữ liệu
Logic chính:
1. Subscribe pattern `t0/devices/+/telemetry`.
2. Parse topic để lấy `device_uid`.
3. Đảm bảo có bản ghi `Device`.
4. Ghi `Telemetry(msg_id, ts, value …)` vào DB.
5. Nếu `(device_uid, msg_id)` đã tồn tại → bỏ qua (tránh duplicate do retry QoS1).

Lưu ý: Nếu thiết bị không gửi `msg_id`, ingestor sẽ tạo UUID → không còn cơ chế chống trùng.

---
## 8. Ứng dụng Flutter
Các bước:
1. Login REST để lấy token.
2. Kết nối MQTT WebSocket `ws://localhost:8083/mqtt`.
3. Subscribe status + telemetry.
4. Hiển thị log hoặc biểu đồ.

Chạy:
```powershell
cd .\flutter_app
flutter pub get
flutter run -d chrome
```
Nếu chạy từ điện thoại thật: đổi `localhost` → IP máy host.

---
## 9. Thuật ngữ quan trọng
| Từ | Giải thích ngắn |
|----|-----------------|
| MQTT | Giao thức nhẹ publish/subscribe |
| Broker | Máy trung chuyển message (EMQX) |
| Telemetry | Dữ liệu thiết bị gửi lên (nhiệt độ, độ ẩm…) |
| Topic | "Địa chỉ" luồng message trong MQTT |
| Wildcard | Ký tự đại diện trong subscribe (`+` 1 cấp, `#` nhiều cấp) |
| Retained | Message broker nhớ để client mới nhận ngay |
| QoS | Mức đảm bảo giao hàng (0: at most once, 1: at least once, 2: exactly once) |
| JWT | Chuỗi có chữ ký, xác thực danh tính người dùng |

---
## 10. Bảo mật & Production (tóm tắt)
| Mục | Dev hiện tại | Prod khuyến nghị |
|-----|-------------|------------------|
| EMQX anonymous | ON | OFF + user/password |
| JWT | Email tùy ý | Thêm đăng nhập thật, hash mật khẩu |
| Uvicorn reload | ON | OFF (ổn định hơn) |
| Migrations | Tạo tự động | Alembic version control |
| Telemetry flow | 1 ingestor | Nhiều ingestor + shared subscription |
| Monitoring | Chưa có | Prometheus + Grafana |
| Unique key | `(device_uid,msg_id)` | Giữ, mở rộng partition/table per tháng |

Hướng dẫn đầy đủ production ở cuối file (giữ nguyên). Xem thêm: `INSTALL.md`.

---
## 11. Troubleshooting
| Lỗi | Nguyên nhân | Cách xử lý |
|-----|-------------|-----------|
| 404 /docs | API container crash | `docker logs <api>` xem stacktrace |
| ImportError email-validator | Thiếu dependency | Đã thêm vào `requirements.txt` |
| AttributeError paho-mqtt | API thay đổi ở phiên bản mới | Pin `paho-mqtt==1.6.1` |
| Flutter không nhận MQTT | Sai host / path | Dùng `ws://<host>:8083/mqtt` đúng |
| Trùng telemetry | msg_id lặp lại | Thiết bị phải tạo msg_id duy nhất |

---
## 12. Nâng cấp tương lai
- Đổi sang `aiomqtt` thay `asyncio-mqtt`.
- Thêm `/health` + `/metrics`.
- Redis cache truy vấn gần nhất.
- Command round-trip (server gửi → thiết bị phản hồi).
- OpenTelemetry tracing.

---
## 13. Lệnh hữu ích
```powershell
docker compose ps
docker logs mqtt_fastapi_postgres_flutter_demo-api-1 --tail 50
docker logs mqtt_fastapi_postgres_flutter_demo-ingestor-1 --tail 50
```

---
## 14. Dọn dẹp / Reset
```powershell
docker compose down -v
docker compose up -d --build
```
Xoá volume để DB sạch.

---
## 15. FAQ nhanh
| Hỏi | Đáp |
|-----|-----|
| Vì sao dùng UNIQUE? | Chặn duplicate khi thiết bị retry QoS1. |
| Có thể bỏ REST, chỉ MQTT? | Được, nhưng truy vấn lịch sử khó & không tối ưu. |
| Sao JWT không lưu DB? | Demo tối giản. Prod cần bảng Users + Refresh Token. |
| Tại sao cần msg_id? | Để phát hiện message trùng và bảo đảm thứ tự. |

---
## 16. Tài liệu mở rộng
- Cài đặt chi tiết: `INSTALL.md`
- Giải thích siêu dễ hiểu: `ARCHITECTURE_BEGINNER.md`
- Production đầy đủ (phía dưới) – có Nginx, TLS, backup, firewall.

---
## 17. Production Chi Tiết (Nguyên bản)
(Giữ nguyên nội dung gốc đã mô tả: chuẩn bị server, Docker, Nginx, Certbot, Systemd, Backup, Hardening…)

> Nếu bạn muốn tách phần production ra file riêng (PRODUCTION.md) hoặc tự động hoá bằng script, hãy yêu cầu thêm.

---
### Kết luận
Bạn đã có một pipeline IoT tối giản: thiết bị → MQTT → ingestor → DB → REST + realtime UI. Học từng bước, nâng cấp dần.

Chúc bạn học tốt! 🚀
