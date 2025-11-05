# Kiến Trúc Hệ Thống 

> Mục tiêu: Sau khi đọc xong bạn nắm được "mảnh ghép" trong hệ thống và dữ liệu đi từ thiết bị đến màn hình Flutter như thế nào.

## 1. Bức Tranh Tổng Quan
Hệ thống này giống một bưu điện nhỏ:
- Thiết bị (device) gửi "bưu kiện" (telemetry JSON) lên **EMQX** (trạm trung chuyển MQTT).
- Một nhân viên nhận hàng (**Ingestor**) đứng ở EMQX, lấy mỗi gói và ghi vào **PostgreSQL** (kho lưu trữ).
- Khách hàng (ứng dụng Flutter, hoặc bạn qua trình duyệt) hỏi thông tin lịch sử qua **FastAPI** (quầy dịch vụ REST).
- Khách hàng cũng có thể đứng cạnh trạm trung chuyển (kết nối MQTT WebSocket) để nghe trực tiếp gói mới tới.

Kết hợp REST + MQTT giúp: REST lấy lịch sử ổn định, MQTT nhận realtime.

## 2. Các Thành Phần Chính
| Thành phần | Vai trò | Ghi nhớ nhanh |
|------------|---------|---------------|
| Thiết bị giả (`sim_device.py`) | Gửi dữ liệu demo | Thay cho IoT thật | 
| EMQX Broker | Trung chuyển MQTT | Nơi publish/subscribe | 
| Ingestor (`backend/ingestor/run.py`) | Lắng nghe telemetry | Viết vào DB | 
| PostgreSQL | CSDL quan hệ | Lưu Users, Devices, Telemetry | 
| FastAPI API (`backend/app/*.py`) | REST endpoints | Login, lấy danh sách, lịch sử | 
| Flutter App | Giao diện | Login REST + nhận realtime MQTT | 

## 3. Luồng Dữ Liệu Chi Tiết
1. Thiết bị publish JSON lên topic: `t0/devices/dev-01/telemetry`.
2. EMQX phát tán message đó cho mọi client đã subscribe pattern `t0/devices/+/telemetry`.
3. Ingestor nhận message, phân tích:
   - Rút ra `device_uid` từ topic.
   - Parse JSON, lấy hoặc tạo `msg_id` (nếu thiếu).
   - Ghi bản ghi vào bảng `telemetry`.
4. Khi người dùng gọi `GET /telemetry/dev-01`, FastAPI truy vấn 100 bản ghi gần nhất trả về.
5. Flutter đã subscribe cùng topic MQTT nên vừa lấy lịch sử (REST) vừa thấy message mới (MQTT) ngay lập tức.

Sơ đồ đơn giản:
```
Device ──(MQTT)──► EMQX ──► Ingestor ──► PostgreSQL
   │                               │
   └────────(MQTT WebSocket)───────┤ (Flutter nhận realtime)
                                   └──► FastAPI (REST lịch sử) ─► Flutter (HTTP)
```

## 4. Tại Sao Dùng MQTT?
- Nhẹ, tối ưu cho kết nối thiết bị không ổn định.
- Có QoS (chất lượng giao hàng) đảm bảo lặp/không mất tùy mức.
- Giữ (retain) trạng thái cuối cùng: ví dụ thiết bị online/offline.

## 5. Vì Sao Vẫn Cần REST?
| MQTT | REST |
|------|------|
| Streaming realtime | Truy vấn lịch sử ổn định |
| Push model | Pull model |
| Ít phù hợp cho lọc phức tạp | SQL query phức tạp tốt |

=> Ghép hai giao thức: realtime (MQTT) + lịch sử (REST) = giải pháp đầy đủ.

## 6. Topics (Đường Dẫn Dữ Liệu)
| Topic | Ý nghĩa |
|-------|---------|
| `t0/devices/dev-01/status` | Trạng thái online/offline (retained) |
| `t0/devices/dev-01/telemetry` | Dữ liệu đo (nhiệt độ, v.v.) |
| `t0/devices/dev-01/commands` | Lệnh điều khiển gửi xuống thiết bị |
| Pattern `t0/devices/+/telemetry` | Subscribe mọi thiết bị |

Ký tự `+` là wildcard "một cấp" trong MQTT.

## 7. Chống Ghi Trùng Telemetry
Bảng `telemetry` có ràng buộc UNIQUE `(device_uid, msg_id)`. Ý nghĩa:
- Nếu thiết bị gửi lại cùng `msg_id` (do retry QoS1) → DB không tạo bản ghi duplicate.
- Bạn cần đảm bảo thiết bị tạo `msg_id` duy nhất (ví dụ số tăng dần hoặc UUID).

Nếu quên `msg_id`, Ingestor sẽ tạo một UUID mới — nhưng như vậy không chống trùng được.

## 8. JWT Đơn Giản (Login REST)
- Khi POST `/auth/login` với email bất kỳ → server tạo JWT chứa `sub=email` + `exp`.
- Flutter / client dùng token này đi kèm header: `Authorization: Bearer <token>`.
- Không có refresh token hoặc role phức tạp trong demo. Thực tế cần thêm bảng người dùng, hash mật khẩu, v.v.

## 9. Code Chính (Bạn nên biết)
| File | Điểm quan trọng |
|------|-----------------|
| `backend/app/main.py` | Khai báo các endpoint REST, tạo bảng khi startup |
| `backend/ingestor/run.py` | Vòng lặp subscribe + ghi DB + reconnect | 
| `backend/app/models.py` | Quy cấu trúc dữ liệu (User, Device, Telemetry) |
| `backend/app/auth.py` | Tạo và kiểm tra JWT |
| `sim_device.py` | Publish 20 bản ghi nhiệt độ giả lập |
| `flutter_app/lib/main.dart` | Kết nối REST + MQTT WebSocket, in log |

## 10. Chạy Nhanh (Tối Thiểu)
```powershell
# 1. Khởi động backend
docker compose up -d --build

# 2. (Tuỳ chọn) Mô phỏng thiết bị
python .\sim_device.py

# 3. Login để lấy token
$body = @{email='demo@example.com'; password='x'} | ConvertTo-Json
$resp = Invoke-RestMethod -Uri http://localhost:8000/auth/login -Method Post -Body $body -ContentType 'application/json'
$token = $resp.access_token

# 4. Lấy lịch sử telemetry
Invoke-RestMethod -Uri http://localhost:8000/telemetry/dev-01 -Headers @{Authorization="Bearer $token"}
```

Realtime (nếu cài Flutter):
```powershell
cd .\flutter_app
flutter pub get
flutter run -d chrome
```
Bấm “Login REST” → “Connect MQTT”.

## 11. Mở Rộng Sau Này
| Nhu cầu | Hướng mở rộng |
|---------|---------------|
| Nhiều thiết bị hơn | Partition / sharding DB, load balancing Ingestor |
| Bảo mật | EMQX auth, TLS, JWT chuẩn, RBAC |
| Giám sát | Prometheus, Grafana, log tập trung |
| Hiệu năng | Batch insert, Redis cache, nén payload |
| Chống mất dữ liệu | QoS2, lưu file raw trước khi xử lý |

## 12. Những Thuật Ngữ Ngắn Gọn
| Từ | Nghĩa siêu ngắn |
|----|-----------------|
| MQTT | Giao thức publish/subscribe cho IoT |
| Broker | Máy trung gian chuyển message (EMQX) |
| Telemetry | Dữ liệu đo đạc gửi lên (temp, độ ẩm...) |
| QoS | Mức đảm bảo giao hàng (0,1,2) |
| JWT | Chuỗi chữ ký mang thông tin đăng nhập |
| Topic | Chuỗi định tuyến message trong MQTT |
| Wildcard | Ký tự đại diện trong subscribe (`+` hoặc `#`) |

## 13. Checklist Tự Kiểm Tra
- [ ] Đã chạy `docker compose up -d --build`
- [ ] EMQX UI mở được (http://localhost:18083)
- [ ] Login REST trả token
- [ ] `/telemetry/dev-01` có dữ liệu
- [ ] Hiểu vì sao dùng UNIQUE `(device_uid,msg_id)`
- [ ] Hiểu sự khác nhau MQTT vs REST

## 14. Câu Hỏi Thường Gặp Cho Newbie
| Hỏi | Trả lời |
|-----|---------|
| Không thấy dữ liệu mới trên REST? | REST trả lịch sử; dữ liệu mới hiển thị qua MQTT. Refresh hoặc gọi lại endpoint. |
| Sao cần cả MQTT và REST? | MQTT realtime, REST truy vấn lịch sử chuẩn SQL. |
| Có thể bỏ FastAPI chỉ dùng MQTT? | Được, nhưng khó truy vấn lịch sử, lọc, phân trang. |
| Tại sao chọn PostgreSQL? | Quan hệ + JSON + mạnh mẽ, dễ index. |
| Làm sao biết message trùng? | Cùng `device_uid` + `msg_id` đã tồn tại (UNIQUE vi phạm). |

## 15. Kết Luận
phiên bản "dễ hiểu" của kiến trúc: tư duy như bưu điện chuyển gói; MQTT để gói tới ngay, REST để tra cứu lịch sử. Nắm vững 4 điểm cốt lõi: Topics, Ingestor, UNIQUE, Kết hợp REST + MQTT.


