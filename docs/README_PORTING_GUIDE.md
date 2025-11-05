# README Porting Dự Án FastAPI + MQTT + PostgreSQL

> Tài liệu này hướng dẫn cách mang (port) toàn bộ stack vào một máy/VM mới, từ bước chuẩn bị môi trường tới kiểm tra hệ thống hoạt động hoàn chỉnh.

---
## 1. Tổng Quan

Kiến trúc triển khai sau khi porting:

```
Thiết bị (sim_device.py / ESP32) → EMQX Broker → Ingestor → PostgreSQL → FastAPI API → Khách (Flutter/Web/REST)
```

- **PostgreSQL** chạy trong Docker, expose cổng `5433` trên host để tránh xung đột với PostgreSQL đã cài sẵn.
- **FastAPI API** & **Ingestor** dùng cùng image Python 3.10, cài dependency từ thư mục `.wheelhouse` (tải trước để không cần Internet khi build).
- **EMQX** cung cấp MQTT TCP (`1883`) và WebSocket (`8083`).

---
## 2. Điều Kiện Tiên Quyết

| Thành phần | Ghi chú |
|------------|---------|
| Git | Để clone repo. |
| Docker Engine + Compose v2 | Kiểm tra bằng `docker --version` và `docker compose version`. |
| Python 3.10 + pip | Dùng để tải trước wheel (nếu cần build offline). |
| Quyền chạy Docker | Người dùng thuộc group `docker` hoặc dùng `sudo`. |

Tuỳ chọn:

- `curl`: kiểm tra API nhanh.
- `psql` hoặc client GUI để truy cập PostgreSQL qua `localhost:5433`.
- Khi muốn chạy các script mô phỏng trên host (`sim_device.py`, `sim_gui.py`), nên cài sẵn dependency Python: 
   ```bash
   pip3 install --user -r backend/requirements.txt
   ```

---
## 3. Chuẩn Bị Mã Nguồn

```bash
git clone https://github.com/Thanhlearningcode/IOT.git
cd IOT
```

Tạo thư mục chứa wheel offline:

```bash
pip3 download -r backend/requirements.txt -d backend/.wheelhouse
```

> Mẹo: Nếu server không có Internet, bạn có thể chạy lệnh trên ở máy có mạng, rồi copy thư mục `backend/.wheelhouse` sang server trước khi build Docker.

---
## 4. Cấu Hình Môi Trường

Các giá trị quan trọng (đã set trong `docker-compose.yml`):

```env
POSTGRES_DB=app
POSTGRES_USER=app
POSTGRES_PASSWORD=secret
DATABASE_URL=postgresql+asyncpg://app:secret@db:5432/app
JWT_SECRET=devsecret
MQTT__HOST=emqx
MQTT__PORT=1883
MQTT__WS_URL=ws://emqx:8083/mqtt
```

- Nếu host đã dùng port 5432, file `docker-compose.yml` map `5433:5432`. Đảm bảo firewall mở cổng 5433 nếu cần truy cập từ xa.
- Có thể đặt riêng file `.env` và dùng `env_file` trong Compose nếu muốn thay đổi thông tin đăng nhập.

---
## 5. Khởi Chạy Stack

```bash
docker compose up -d --build
```

Kiểm tra:

```bash
docker compose ps
docker compose logs api --tail 50
docker compose logs ingestor --tail 50
```

- `api`, `ingestor`, `emqx`, `db` phải ở trạng thái `Up`.
- Lần build đầu sẽ dùng Python 3.10 và bộ wheel offline; những lần sau tái sử dụng layer cache.

---
## 6. Kiểm Tra Hệ Thống Sau Khi Porting

1. **Đăng nhập demo:**

   ```bash
   curl -s -X POST http://localhost:8000/auth/login \
     -H 'Content-Type: application/json' \
     -d '{"email":"demo@example.com","password":"x"}'
   ```

   Nhận lại `access_token` JWT.

2. **Gửi telemetry mẫu:**

   ```bash
   python3 sim_device.py
   ```

   hoặc publish MQTT thủ công tới topic `t0/devices/dev-01/telemetry`.

3. **Đọc dữ liệu qua REST:**

   ```bash
   curl http://localhost:8000/telemetry/dev-01 \
     -H "Authorization: Bearer <token>"
   ```

4. **Kiểm tra MQTT realtime (tuỳ chọn):** Dùng Flutter app (`flutter run -d chrome`) hoặc MQTT client connect `ws://localhost:8083/mqtt`. Có thể sử dụng GUI `sim_gui.py` để publish thủ công (chạy bằng `python3 sim_gui.py`).

5. **Truy cập PostgreSQL:**

   ```bash
   psql postgresql://app:secret@localhost:5433/app
   ```

   Xác minh các bảng `devices`, `telemetry`, `command_queue` được tạo.

---
## 7. Tích Hợp Thiết Bị Thật / ESP32

- Cập nhật `esp32/ESP32/src/main.cpp` với Wi-Fi và địa chỉ broker (`tcp://<IP-máy-host>:1883`).
- Build và flash bằng PlatformIO (`pio run --target upload`).
- Theo dõi log `pio device monitor` để chắc chắn thiết bị publish telemetry.
- Bảng `devices` sẽ tự thêm hàng mới khi Ingestor thấy UIDs chưa tồn tại.

Chi tiết xem `docs/README_ESP32.md`.

---
## 8. Các Lỗi Thường Gặp & Cách Xử Lý

| Triệu chứng | Nguyên nhân | Cách khắc phục |
|-------------|-------------|----------------|
| Docker báo `address already in use` port `5432` | Host đã có PostgreSQL | Sử dụng port host `5433` như trong Compose (mặc định). |
| Build image lỗi `No matching distribution` | Thiếu wheel hoặc sai phiên bản Python | Đảm bảo đã chạy `pip3 download ...` bằng Python 3.10 trước khi build. |
| API không truy cập được | Container `api` crash | Xem `docker compose logs api` để biết stack trace. |
| Không nhận telemetry | Ingestor chưa chạy hoặc EMQX chưa sẵn sàng | Kiểm tra log `ingestor`, đảm bảo topic đúng `t0/devices/+/telemetry`. |
| Flutter không connect MQTT | Sai URL WebSocket | Dùng `ws://<host>:8083/mqtt`. |

---
## 9. Vận Hành & Bảo Trì

- **Sao lưu DB:** Dùng `scripts/pg_backup.sh` hoặc `pg_dump` qua port 5433.
- **Nâng cấp dependency:** Cập nhật `backend/requirements.txt`, chạy lại `pip3 download ...`, `docker compose build`.
- **Giám sát:** EMQX dashboard `http://localhost:18083`, FastAPI docs `http://localhost:8000/docs`.

---
## 10. Dọn Dẹp

```bash
docker compose down -v
docker image prune -f
```

Nếu muốn reset hoàn toàn DB, xoá volume hoặc đổi tên nó trong Compose.

---
## 11. Tài Liệu Liên Quan

- `README_LOCAL_PORTING.md`: Hướng dẫn chi tiết cho môi trường local + Flutter.
- `docs/README_DOCKER.md`: Chi tiết vận hành Docker, tùy chỉnh mạng.
- `docs/README_FASTAPI_DEVICE_API.md`: Tài liệu API thiết bị.
- `docs/README_POSTGRES.md`: Kiến trúc và tối ưu truy vấn.

---
### Ghi chú

Porting thành công khi:

- Các container `api`, `ingestor`, `db`, `emqx` đều Up.
- Bạn đăng nhập được và truy xuất telemetry mẫu.
- Có thể truy cập PostgreSQL qua port 5433.
- MQTT WebSocket hoạt động với client bên ngoài.

Chúc bạn triển khai thuận lợi!
![alt text](image.png)

---
## 12. Tự Động Hoá Toàn Bộ Luồng (A → Z)

Để chạy xuyên suốt từ Docker stack → simulator Python → kiểm tra REST chỉ bằng một lệnh:

```bash
bash scripts/run_end_to_end.sh --install-sim-deps --duration 30
```

Script trên sẽ:

1. Khởi động (hoặc đảm bảo) toàn bộ Docker Compose stack.
2. Đợi Postgres và FastAPI sẵn sàng.
3. Cài dependency cho simulator (khi dùng `--install-sim-deps`).
4. Chạy `sim_device.py` trong ~30 giây để đẩy telemetry demo.
5. Tự đăng nhập và gọi API `/telemetry/dev-01` để kiểm tra dữ liệu lưu vào Postgres.
6. In hướng dẫn mở Flutter app và truy cập pgAdmin.

Các script hỗ trợ khác:

```bash
# Start / stop nhanh
bash scripts/dev_stack.sh start
bash scripts/dev_stack.sh stop

# Theo dõi log hoặc vào shell container
bash scripts/dev_stack.sh logs api
bash scripts/dev_stack.sh shell db psql -U app -d app

# Chỉ chạy simulator thủ công
bash scripts/run_simulator.sh --install-deps
bash scripts/run_simulator.sh
```

### Ghi chú pgAdmin
- URL: http://localhost:5050
- Đăng nhập: `admin@local.test` / `ChangeMe!`
- Add New Server → Host: `db`, Port: `5432`, Username: `app`, Password: `secret`.
