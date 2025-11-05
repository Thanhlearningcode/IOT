# Docker Guide – MQTT ↔ FastAPI ↔ PostgreSQL ↔ Flutter

> Tài liệu này giúp bạn hiểu, cấu hình và vận hành các container Docker trong project.

---
## 1. Tổng quan
- Toàn bộ hệ thống chạy qua `docker compose`.
- Các service chính: `api` (FastAPI), `db` (Postgres), `emqx`, `ingestor` (worker), `adminer` (UI Postgres), `flutter_web` (build demo Web) – tuỳ cấu hình.
- Thư mục quan trọng:
  - `docker-compose.yml`
  - `backend/Dockerfile`
  - `backend/requirements.txt`
  - `.env` (tạo thêm nếu cần biến môi trường riêng).

---
## 2. Chuẩn bị môi trường
1. Cài Docker Desktop (Windows) / Docker Engine + Docker Compose v2 (Linux/Mac).
2. Bật tính năng WSL2 (Windows).
3. Kiểm tra Docker đang chạy:
```powershell
docker version
docker compose version
```
4. Kéo repo về và mở PowerShell tại thư mục gốc.

---
## 3. Cấu trúc docker-compose
| Service | Image | Port | Ghi chú |
|---------|-------|------|---------|
| `api` | Build từ `backend/Dockerfile` | 8000 | FastAPI, phụ thuộc DB + EMQX |
| `db` | `postgres:15-alpine` | 5432 | Dùng volume `pgdata`, init user/password từ env |
| `emqx` | `emqx/emqx:5` | 1883, 8883, 8083, 18083 | Broker MQTT + Dashboard |
| `ingestor` | Build từ `backend/Dockerfile` (khác CMD) | n/a | Worker async, subscribe MQTT |
| `adminer` (tuỳ chọn) | `adminer:latest` | 8080 | Web UI quản lý DB |
| `flutter_web` (tuỳ chọn) | Dùng `flutter` container hoặc build sẵn | 9000 | Demo chạy web | 

Các network/volume tạo tự động:
- `mqtt_fastapi_postgres_flutter_demo_net`
- `pgdata` (volume cho Postgres).

---
## 4. Biến môi trường quan trọng
Tạo file `.env` hoặc đặt trong PowerShell trước khi chạy.
```
POSTGRES_DB=iot
POSTGRES_USER=iot
POSTGRES_PASSWORD=secret
JWT_SECRET=dev-secret
MQTT__HOST=emqx
MQTT__PORT=1883
```
- FastAPI đọc từ biến env (xem `backend/app/config.py` nếu có).
- Ingestor dùng chung `.env` nhờ `env_file` trong compose.
- Có thể override khi chạy: `POSTGRES_PASSWORD=super docker compose up -d`.

---
## 5. Lệnh cơ bản
```powershell
# Build & chạy
docker compose up -d --build

# Kiểm tra trạng thái
docker compose ps

# Xem log từng service
docker compose logs api --tail 100
docker compose logs ingestor -f

# Dừng, giữ dữ liệu
docker compose down

# Dừng và xoá volume (reset database)
docker compose down -v

# Vào shell container
docker compose exec api bash
```

---
## 6. Quy trình Dev Loop
1. Chạy `docker compose up -d --build` lần đầu.
2. Sửa code backend → `docker compose up -d --build api ingestor` để rebuild selective.
3. Dùng `uvicorn --reload` (Dev mode) trong Docker: đã cấu hình sẵn ở `command` service `api`.
4. Kiểm tra API tại `http://localhost:8000/docs`.
5. Mô phỏng thiết bị (ngoài Docker) bằng `python sim_device.py`.

---
## 7. Debug thường gặp
| Vấn đề | Nguyên nhân | Cách xử lý |
|--------|-------------|------------|
| `docker compose up` báo không tìm thấy pipe | Docker Desktop chưa chạy | Mở Docker Desktop, đợi trạng thái "Running" |
| `api` crash khi khởi động | Dependency chưa cài | Kiểm tra `backend/requirements.txt` + rebuild |
| Không kết nối DB | Biến env sai | Xem `docker compose logs api`, kiểm tra `POSTGRES_*` |
| MQTT không nhận message | EMQX chưa sẵn sàng hoặc ACL | Xem log `emqx`, kiểm tra user/password |
| Port xung đột | Cổng đã dùng bởi process khác | Đổi mapping trong compose hoặc dừng process đó |

---
## 8. Volume & dữ liệu
- `pgdata`: lưu toàn bộ dữ liệu Postgres.
- Reset dữ liệu: `docker compose down -v` (cẩn thận mất toàn bộ dữ liệu).
- Backup thử nghiệm: `docker compose exec db pg_dump -U iot iot > dump.sql`.
- Restore: `type dump.sql | docker compose exec -T db psql -U iot iot` (PowerShell dùng `Get-Content` nếu file lớn).

---
## 9. Mở rộng / Production
- Tạo file `docker-compose.prod.yml` override cho prod (disable `--reload`, bật gzip, `.env.prod`).
- Dùng Reverse proxy Nginx/Traefik đứng trước `api` và `emqx`.
- Bật TLS: tham khảo `docs/README_HTTPS.md`.
- Scaling `ingestor`: dùng `docker compose up --scale ingestor=3` + EMQX shared subscription.
- Monitoring: thêm container `prometheus`, `grafana`, `loki`.

---
## 10. Flutter Web bằng Docker (tuỳ chọn)
- Có thể build `flutter_app` trong container để deploy.
- Ví dụ service (tham khảo, chưa có sẵn):
```yaml
flutter_web:
  build: ./flutter_app
  ports:
    - "9000:80"
  depends_on:
    - api
    - emqx
```
- Hoặc chạy `flutter run -d chrome` ngoài Docker cho dev.

---
## 11. Script hữu ích
```powershell
# Xoá image dangling
docker image prune -f

# Xem tài nguyên
docker stats

# Kiểm tra network
docker network ls
docker network inspect mqtt_fastapi_postgres_flutter_demo_default

# Copy file từ container
docker compose cp api:/app/app/main.py .\tmp\main.py
```

---
## 12. Checklist trước khi deploy thật
- [ ] Docker Desktop / Engine đang chạy.
- [ ] `.env` chứa password mạnh, không commit lên git.
- [ ] Port mapping phù hợp firewall (1883/8883/8000/18083).
- [ ] TLS cho API, MQTT (xem README HTTPS).
- [ ] Backup volume Postgres định kỳ.
- [ ] Log shipping sang công cụ tập trung (ELK/Grafana Loki).
- [ ] Theo dõi CPU/RAM container.

---
## 13. Tài liệu tham khảo
- Docker Compose docs: https://docs.docker.com/compose/
- EMQX container: https://hub.docker.com/r/emqx/emqx
- Postgres container: https://hub.docker.com/_/postgres
- Docker Desktop troubleshooting: https://docs.docker.com/desktop/troubleshoot-overview/

---
## 14. Kết luận
Docker giúp khởi chạy toàn bộ hệ thống nhanh chóng, cô lập môi trường và dễ scale. Nắm rõ `docker compose`, volume, biến môi trường và quy trình debug sẽ giúp  phát triển, demo và triển khai sản phẩm IoT này hiệu quả hơn.
