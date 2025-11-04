## RUN
# 1. Khởi động toàn bộ services (EMQX, Postgres, FastAPI, ingestor)
docker compose up -d --build

# 2. Kiểm tra log ingestor xem đã subscribe chưa
docker compose logs -f ingestor

# 3. (Tuỳ chọn) Mở Dashboard EMQX trên trình duyệt
# http://localhost:18083  (dev đang bật anonymous)
# 4 Trong thư mục gốc dự án
python sim_device.py
# 5 Flutter
cd flutter_app
flutter pub get
flutter run -d chrome --web-port=5173
---