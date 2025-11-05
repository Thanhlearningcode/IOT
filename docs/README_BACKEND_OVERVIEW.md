# Tổng Quan Backend (FastAPI + MQTT + Postgres)

> Tài liệu tóm lược code backend để bạn xem lại nhanh khi rảnh.

---
## 1. Thành phần chính
- FastAPI (`backend/app/main.py`) cung cấp REST: login, danh sách thiết bị, lấy telemetry, gửi command.
- PostgreSQL lưu `users`, `devices`, `telemetry` với Unique `(device_uid, msg_id)` chống trùng.
- MQTT (EMQX) dùng cho telemetry realtime và command xuống thiết bị.
- Ingestor (`backend/ingestor/run.py`) subscribe MQTT, ghi dữ liệu vào DB.

Sơ đồ:
```
Device → MQTT Broker → Ingestor → PostgreSQL → FastAPI → Client
                             ↘────────────── MQTT commands ───↗
```

---
## 2. `backend/app/main.py`
- Khởi tạo FastAPI, bật CORS dev.
- `startup`: tạo bảng (nếu chưa có) qua SQLAlchemy metadata.
- `/auth/login`:
  - Nhận `LoginIn` (email, password).
  - Tìm user theo email; nếu chưa có tạo user mới password giả `demo`.
  - Trả `TokenOut` với JWT từ `create_token`.
- `/devices` (bảo vệ bởi `require_user`): trả danh sách devices.
- `/telemetry/{device_uid}`: trả 100 record mới nhất dạng `TelemetryOut` (payload JSON, ts ISO).
- `/devices/{device_uid}/command`: nhận `CommandIn`, publish MQTT topic `t0/devices/{uid}/commands` với QoS1.

---
## 3. `backend/app/db.py`
- Đọc `DATABASE_URL` từ env (ví dụ `postgresql+asyncpg://iot:secret@db:5432/iot`).
- Tạo `create_async_engine`, `sessionmaker` Async.
- Hàm `get_db()` yield session, dùng trong FastAPI dependency.

---
## 4. `backend/app/models.py`
- `User`: email unique, password_hash, role, created_at.
- `Device`: `device_uid` unique, tên và tenant.
- `Telemetry`: `device_uid` (FK), `msg_id`, payload JSON, `ts`, UNIQUE `(device_uid, msg_id)` đảm bảo Idempotent.

---
## 5. `backend/app/schemas.py`
- Pydantic dùng để validate I/O:
  - `LoginIn` (EmailStr, password).
  - `TokenOut` (access_token, bearer).
  - `TelemetryOut` (device_uid, payload dict, ts string).
  - `CommandIn` (cmd string, params optional dict).

---
## 6. `backend/app/auth.py`
- JWT HS256: sử dụng `JWT_SECRET` env (mặc định `devsecret`).
- `create_token(sub, minutes=60)` tạo token với `iat` và `exp`.
- `require_user` (FastAPI dependency) dùng `HTTPBearer` giải mã token; lỗi → 401.

---
## 7. `backend/app/mqtt_pub.py`
- Dùng `asyncio-mqtt.Client` kết nối broker (host/port lấy từ `MQTT__HOST`, `MQTT__PORT`).
- `publish_command(device_uid, payload)`: publish JSON lên topic `t0/devices/{uid}/commands` QoS1.

---
## 8. `backend/ingestor/run.py`
- Thông số env: `MQTT__HOST`, `MQTT__PORT`, `MQTT__TOPIC` (mặc định `t0/devices/+/telemetry`).
- `ensure_device`: auto tạo `Device` nếu chưa có trong DB.
- `handle_message(topic, payload)`:
  - Parse topic lấy `device_uid`.
  - Parse JSON, fallback raw text; tạo `msg_id` nếu thiếu.
  - Lưu `Telemetry` và commit; duplicate → rollback bỏ qua.
- `main()`:
  - Vòng lặp, subscribe topic QoS1, xử lý từng message.
  - Catch `MqttError` → sleep 3s rồi reconnect.

---
## 9. Lệnh kiểm tra nhanh
```powershell
# Login và lấy token
$body = @{email='demo@example.com'; password='x'} | ConvertTo-Json
$login = Invoke-RestMethod http://localhost:8000/auth/login -Method Post -Body $body -ContentType 'application/json'
$token = $login.access_token

# Lấy telemetry
docker compose up -d --build
Invoke-RestMethod http://localhost:8000/telemetry/dev-01 -Headers @{Authorization="Bearer $token"}

# Gửi command MQTT
python - <<'PY'
import asyncio
from app.mqtt_pub import publish_command
asyncio.run(publish_command("dev-01", {"cmd": "reboot", "params": {"delay": 5}}))
PY

# Chạy ingestor (nếu muốn chạy ngoài Docker)
python -m backend.ingestor.run
```

---
## 10. Điểm lưu ý khi đọc code
- JWT demo: không xác thực password thật; chỉ minh hoạ.
- Ingestor dùng `SessionLocal` trực tiếp, không FastAPI dependency.
- MQTT dùng QoS1 → cần `msg_id` để chống trùng (đã xử lý bằng UNIQUE + rollback).
- CORS mở toàn bộ để tiện cho Flutter Web khi dev.

---
## 11. Hướng dẫn đọc thêm
- `docs/README_FASTAPI.md`: diễn giải chi tiết từng endpoint.
- `docs/README_MQTT.md`: hướng dẫn MQTT, topic, QoS.
- `docs/README_POSTGRES.md`: vận hành DB, schema.
- `docs/README_HTTP_vs_MQTT.md`: khi chọn HTTP hay MQTT.
- `docs/README_DOCKER.md`: cách chạy stack bằng Docker.
- `docs/README_HTTPS.md`: bảo mật HTTPS/MQTTS.

---
## 12. Checklist khi run
- [ ] Docker Desktop đang chạy (`docker info`).
- [ ] Env `DATABASE_URL`, `JWT_SECRET`, `MQTT__HOST` cấu hình đúng.
- [ ] `docker compose up -d --build` thành công.
- [ ] `python sim_device.py` để có dữ liệu mẫu.
- [ ] Gọi `/telemetry/dev-01` bằng token để kiểm tra pipeline.

---
## 13. Kết luận
Tài liệu này  nhanh chóng nắm lại backend: REST API, cơ chế auth đơn giản, worker ingest dữ liệu qua MQTT và cách gửi command. Khi cần đổi behaviour, xem lại từng file tương ứng rồi cập nhật.
