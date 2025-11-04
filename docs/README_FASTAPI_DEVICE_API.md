# FastAPI Device-Facing API (ESP32 / Edge)

> Các endpoint bổ sung phục vụ thiết bị thật khi không (hoặc song song) dùng MQTT.

## 1. Mục Tiêu
- Cho phép thiết bị đăng ký và nhận secret.
- Gửi telemetry qua HTTP fallback.
- Poll command nếu thiết bị không thể nhận MQTT.
- Ack command để server biết trạng thái.
- Kiểm tra phiên bản firmware.

## 2. Bảng / Model Bổ Sung
| Model | Mục đích |
|-------|----------|
| `Device.device_secret` | Secret đơn giản demo (prod: hash / JWT). |
| `CommandQueue` | Hàng đợi lệnh cho chế độ HTTP polling. |

## 3. Endpoint Chi Tiết
| Method | Path | Body | Header | Mô tả |
|--------|------|------|--------|------|
| POST | `/devices/register` | `{device_uid,name?}` | - | Tạo thiết bị + secret, trả JWT chứa secret. |
| POST | `/devices/{uid}/telemetry` | `{msg_id?, payload}` | `X-Device-Secret` | Gửi telemetry qua HTTP. |
| POST | `/devices/{uid}/command` | `{cmd,params?}` | Auth (user JWT) | Publish lệnh ngay MQTT (cũ). |
| POST | `/devices/{uid}/command/store` | `{cmd,params?}` | Auth (user JWT) | Lưu vào queue + publish MQTT. |
| GET | `/devices/{uid}/commands/poll` | - | `X-Device-Secret` | Thiết bị lấy các lệnh `sent` chưa ack. |
| POST | `/devices/{uid}/commands/{id}/ack` | - | `X-Device-Secret` | Thiết bị xác nhận đã thực thi. |
| GET | `/devices/{uid}/firmware/check?version=X` | - | - | Kiểm tra phiên bản latest giả lập. |

## 4. Đăng Ký Thiết Bị
```powershell
$reg = Invoke-RestMethod http://localhost:8000/devices/register -Method Post -Body '{"device_uid":"dev-esp32-01"}' -ContentType 'application/json'
$deviceToken = $reg.access_token   # chứa secret demo
```
Secret nằm trong phần `sub` của JWT; `main.py` dùng trực tiếp chuỗi secret.

## 5. Gửi Telemetry HTTP
```powershell
$secret = '<SECRET_DA_NHAN>'
$headers = @{ 'X-Device-Secret' = $secret }
Invoke-RestMethod http://localhost:8000/devices/dev-esp32-01/telemetry -Method Post -Headers $headers -Body '{"msg_id":"t123","payload":{"temp":26.4}}' -ContentType 'application/json'
```
Phản hồi:
```json
{"status":"ok","msg_id":"t123"}
```
Duplicate (msg_id trùng) sẽ trả `{"status":"duplicate"}`.

## 6. Lưu & Poll Command
Tạo command và lưu queue:
```powershell
$userToken = '<USER_JWT>'
$headersUser = @{ Authorization = "Bearer $userToken" }
Invoke-RestMethod http://localhost:8000/devices/dev-esp32-01/command/store -Method Post -Headers $headersUser -Body '{"cmd":"led_on"}' -ContentType 'application/json'
```
Thiết bị poll:
```powershell
$headersDev = @{ 'X-Device-Secret' = $secret }
Invoke-RestMethod http://localhost:8000/devices/dev-esp32-01/commands/poll -Headers $headersDev
```
Ack:
```powershell
Invoke-RestMethod http://localhost:8000/devices/dev-esp32-01/commands/123/ack -Method Post -Headers $headersDev
```

## 7. Firmware Check
```powershell
Invoke-RestMethod "http://localhost:8000/devices/dev-esp32-01/firmware/check?version=0.9.0"
```
Phản hồi mẫu:
```json
{"update_available":true,"current_version":"0.9.0","latest_version":"1.0.0","url":"https://example.com/fw/dev-esp32-01/1.0.0.bin"}
```

## 8. Lưu Ý Bảo Mật (Prod)
- Không lưu `device_secret` dạng plain: hash (bcrypt) hoặc dùng long random API key.
- Thay cơ chế secret bằng JWT cấp riêng cho thiết bị (scope device, expiry ngắn). Endpoint đăng ký cần auth hoặc provisioning offline.
- Thêm rate limit cho `/telemetry` (per device). Dùng Redis + bucket.
- Validate payload (schema từng loại sensor, min/max). Reject dữ liệu bất thường.
- Sử dụng HTTPS + TLS mutual (client cert) nếu thiết bị hỗ trợ.
- Hàng đợi command có thể cần TTL + retry logic.

## 9. Khi Nên Dùng HTTP Thay MQTT
| Tình huống | HTTP phù hợp |
|-----------|--------------|
| Firewall chặn port 1883 | Có (443 tunneling dễ) |
| Thiết bị không có lib MQTT ổn định | Có |
| Batch gửi ít, thưa | Có |
| Yêu cầu xác thực phức tạp dựa API Gateway | Có |

Trường hợp cần realtime dày đặc → ưu tiên MQTT.

## 10. Luồng Kết Hợp MQTT + HTTP
```
(ESP32) --publish telemetry--> MQTT Broker --> Ingestor --> DB
   |                                          ^
   |--poll command HTTP (fallback)-------------|
   |--ack command------------------------------|
```
Nếu mất kết nối MQTT: thiết bị tạm gửi `/telemetry` HTTP cho đến khi khôi phục.

## 11. Checklist Triển Khai
- [ ] Thêm migration cho bảng mới (CommandQueue + device_secret). (Hiện tại auto create)
- [ ] Viết test integration cho register + telemetry + poll + ack.
- [ ] Cấu hình CORS hẹp (chỉ domain UI).
- [ ] Logging chi tiết (request id, device uid).
- [ ] Metrics Prometheus: số telemetry HTTP vs MQTT.

## 12. Mở Rộng Tương Lai
- WebSocket riêng cho thiết bị không dùng MQTT.
- gRPC streaming telemetry.
- Firmware delta updates + ký số SHA256.
- Config push: `/devices/{uid}/config` từ server xuống.

## 13. Thử Nhanh (PowerShell Script Gộp)
```powershell
# Đăng ký thiết bị
$reg = Invoke-RestMethod http://localhost:8000/devices/register -Method Post -Body '{"device_uid":"dev-esp32-01"}' -ContentType 'application/json'
$secret = ($reg.access_token) # sub chứa secret đơn giản
$hDev = @{ 'X-Device-Secret' = $secret }

# Gửi telemetry
Invoke-RestMethod http://localhost:8000/devices/dev-esp32-01/telemetry -Method Post -Headers $hDev -Body '{"payload":{"temp":25.3}}' -ContentType 'application/json'

# User tạo command
$login = Invoke-RestMethod http://localhost:8000/auth/login -Method Post -Body '{"email":"admin@example.com","password":"x"}' -ContentType 'application/json'
$ut = $login.access_token
$hUser = @{ Authorization = "Bearer $ut" }
Invoke-RestMethod http://localhost:8000/devices/dev-esp32-01/command/store -Method Post -Headers $hUser -Body '{"cmd":"led_on"}' -ContentType 'application/json'

# Poll command
Invoke-RestMethod http://localhost:8000/devices/dev-esp32-01/commands/poll -Headers $hDev
```

---
## 14. Kết Luận
Bộ endpoint mới cho phép thiết bị hoạt động linh hoạt: ưu tiên MQTT cho realtime, fallback HTTP cho đăng ký, telemetry ít, và nhận lệnh khi không duy trì kết nối MQTT. Prod cần tăng cường xác thực, rate limit, và theo dõi.
