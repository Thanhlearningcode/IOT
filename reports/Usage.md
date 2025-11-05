# 🚀 FastAPI + MQTT + PostgreSQL IoT Backend

## 🧠 Tổng quan

Đây là một dự án **IoT backend** được xây dựng bằng **FastAPI**, kết hợp với **MQTT broker** để giao tiếp với thiết bị (ESP32, ESP8266, v.v.) và **PostgreSQL** để lưu dữ liệu.

Ứng dụng này cung cấp REST API cho:
- Đăng nhập người dùng (`/auth/login`)
- Quản lý danh sách thiết bị (`/devices`)
- Lấy dữ liệu cảm biến (`/telemetry/{device_uid}`)
- Gửi lệnh điều khiển đến thiết bị (`/devices/{device_uid}/command`)

Swagger UI (tài liệu API tự động) có sẵn tại:
👉 **http://localhost:8000/docs**

---

## ⚙️ Kiến trúc hệ thống

```
+-------------+         +-------------+         +-------------------+
|  ESP32/ESP  | <--->   |   MQTT Broker  | <---> |   FastAPI Server   |
+-------------+         +-------------+         +-------------------+
       ↑                                                   ↓
       |                                                   ↓
       +----------------->  PostgreSQL Database  <----------+
```

---

## 🧩 Các thành phần chính

| Thành phần | Công nghệ | Mô tả |
|-------------|------------|-------|
| **Backend API** | FastAPI | Xử lý logic, API REST |
| **Database** | PostgreSQL | Lưu thông tin user, device, telemetry |
| **MQTT Broker** | Mosquitto / EMQX / HiveMQ | Giao tiếp với thiết bị IoT |
| **Docs** | Swagger UI | Test API trực tiếp tại `/docs` |

---

## 🧱 Cấu trúc thư mục (ví dụ)

```
project/
│
├── main.py                  # Điểm khởi động FastAPI
├── database.py              # Kết nối PostgreSQL
├── mqtt_client.py           # Client MQTT
├── models.py                # SQLAlchemy models
├── schemas.py               # Pydantic models
├── routes/
│   ├── auth.py              # Đăng nhập, JWT token
│   ├── devices.py           # Quản lý thiết bị
│   ├── telemetry.py         # Dữ liệu cảm biến
│   └── command.py           # Gửi lệnh qua MQTT
└── requirements.txt         # Danh sách package cần cài
```

---

## ⚙️ Cài đặt

### 1️⃣ Tạo môi trường ảo

```bash
python -m venv venv
source venv/Scripts/activate   # Windows
# hoặc
source venv/bin/activate       # Linux/Mac
```

### 2️⃣ Cài đặt thư viện

```bash
pip install -r requirements.txt
```

### 3️⃣ Cấu hình môi trường `.env`

Tạo file `.env` với nội dung:

```env
DATABASE_URL=postgresql://username:password@localhost:5432/iot_db
MQTT_BROKER=localhost
MQTT_PORT=1883
JWT_SECRET=your_secret_key
JWT_ALGORITHM=HS256
```

### 4️⃣ Chạy ứng dụng

```bash
uvicorn main:app --reload
```

Truy cập: 👉 [http://localhost:8000/docs](http://localhost:8000/docs)

---

## 🔐 API Endpoints

### **1. Đăng nhập**

**POST** `/auth/login`

#### Request:
```json
{
  "email": "admin@example.com",
  "password": "123456"
}
```

#### Response:
```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6...",
  "token_type": "bearer"
}
```

---

### **2. Danh sách thiết bị**

**GET** `/devices`

Yêu cầu gửi Header:

```
Authorization: Bearer <access_token>
```

#### Response:
```json
[
  {
    "device_uid": "esp32_001",
    "name": "Temperature Sensor",
    "status": "online"
  }
]
```

---

### **3. Lấy dữ liệu cảm biến**

**GET** `/telemetry/{device_uid}`

Ví dụ:
```
/telemetry/esp32_001
```

#### Response:
```json
{
  "temperature": 28.4,
  "humidity": 70.2,
  "timestamp": "2025-11-05T09:23:00Z"
}
```

---

### **4. Gửi lệnh điều khiển**

**POST** `/devices/{device_uid}/command`

Ví dụ:
```
/devices/esp32_002/command
```

#### Request:
```json
{
  "command": "TURN_ON"
}
```

#### Response:
```json
{
  "status": "sent",
  "device_uid": "esp32_002"
}
```

---

## 🧠 Luồng hoạt động

1. **Thiết bị (ESP32)** kết nối đến MQTT broker (`topic: telemetry/<device_id>`).
2. **FastAPI** lắng nghe các topic để lưu dữ liệu vào **PostgreSQL**.
3. Người dùng đăng nhập vào hệ thống qua `/auth/login`.
4. Người dùng có thể:
   - Xem danh sách thiết bị (`GET /devices`)
   - Lấy dữ liệu cảm biến (`GET /telemetry/{id}`)
   - Gửi lệnh điều khiển (`POST /devices/{id}/command`)
5. FastAPI publish lệnh đến MQTT topic `devices/<id>/cmd`.

---

## 🧪 Test API trong Swagger

1. Truy cập: [http://localhost:8000/docs](http://localhost:8000/docs)
2. Vào **POST /auth/login**
   - Nhấn **Try it out**
   - Nhập:
     ```json
     {
       "email": "admin@example.com",
       "password": "123456"
     }
     ```
   - Nhấn **Execute** → Nhận token
3. Nhấn nút **Authorize** (góc trên phải)
   - Nhập: `Bearer <token>`
4. Test các API khác như `/devices`, `/telemetry`, `/command`.

---

## 🧰 Công nghệ sử dụng

| Công nghệ | Mục đích |
|------------|-----------|
| **FastAPI** | Xây dựng REST API |
| **Pydantic** | Xác thực dữ liệu (schemas) |
| **SQLAlchemy** | ORM kết nối PostgreSQL |
| **MQTT (paho-mqtt)** | Giao tiếp thiết bị IoT |
| **Uvicorn** | ASGI server chạy FastAPI |
| **PostgreSQL** | Lưu trữ dữ liệu người dùng & thiết bị |

---

## 📦 Cài thêm MQTT Broker (tuỳ chọn)

Nếu chưa có MQTT broker, bạn có thể cài Mosquitto nhanh bằng Docker:

```bash
docker run -it -p 1883:1883 -p 9001:9001 eclipse-mosquitto
```

---

## 🧩 Lệnh MQTT mẫu cho ESP32

```cpp
client.publish("devices/esp32_001/telemetry", "{"temperature":25.4,"humidity":65}");
client.subscribe("devices/esp32_001/command");
```

Khi API `/devices/{id}/command` gửi `"TURN_ON"`, ESP32 sẽ nhận lệnh qua MQTT topic `devices/esp32_001/command`.

---

## 🧾 License

MIT License © 2025

---

## 👨‍💻 Tác giả
**TRÍ TUỆ NHÂN TẠO AI GPT / @tuyetsonphiho178**

Liên hệ: [tuyetsonphiho178@gmail.com](mailto:tuyetsonphiho178@gmail.com)
