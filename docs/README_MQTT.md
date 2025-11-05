# Tutorial MQTT A‑Z Cho Newbie (Dựa Trên Project Này)

> Mục tiêu: Hiểu rõ MQTT là gì, cách thiết kế topic & payload, cách publish/subscribe bằng Python và Flutter, chống trùng dữ liệu, mở rộng quy mô, bảo mật, và xử lý sự cố.

---
## Mục lục
1. MQTT Là Gì? Khi Nào Dùng?
2. Các Khái Niệm Cốt Lõi
3. Broker EMQX (Dev vs Prod)
4. Thiết Kế Topic Trong Project
5. Payload Các Loại Message
6. QoS & Ảnh Hưởng Thực Tế
7. Retained Message & Trạng Thái Thiết Bị
8. Wildcard Subscribe (+ và #)
9. Last Will & Clean Session (Giới Thiệu)
10. Python Publish Telemetry (paho-mqtt)
11. Python Async Ingestion (asyncio-mqtt)
12. Gửi Command Từ Server (publish_command)
13. Flutter WebSocket MQTT Kết Nối
14. Chống Trùng Dữ Liệu (msg_id + UNIQUE)
15. Shared Subscription & Scale Worker
16. Bảo Mật Cơ Bản (Auth, ACL, TLS)
17. Kiến Trúc Kết Hợp MQTT + REST
18. Testing Nhanh Với MQTTX / mosquitto_sub
19. Troubleshooting (Lỗi Thường Gặp)
20. Tối Ưu Thực Tế & Best Practices
21. Checklist Cho Newbie
22. Lộ Trình Nâng Cao
23. Tài Nguyên Tham Khảo

---
## 1. MQTT Là Gì? Khi Nào Dùng?
MQTT là giao thức publish/subscribe siêu nhẹ cho thiết bị (IoT, sensor). Thiết bị gửi (publish) lên broker; client quan tâm nhận (subscribe). 
Dùng khi:
- Thiết bị mạng chập chờn.
- Cần realtime, overhead nhỏ hơn HTTP.
- Mô hình nhiều bên nhận cùng 1 luồng dữ liệu.

Không tối ưu nếu:
- Chỉ cần truy vấn lịch sử phức tạp → dùng REST/SQL.
- Truyền file rất lớn (nên HTTP).

---
## 2. Các Khái Niệm Cốt Lõi
| Term | Ý nghĩa |
|------|--------|
| Broker | Máy trung gian phân phối message (EMQX). |
| Client | Bất kỳ thiết bị / app kết nối broker. |
| Topic | Chuỗi định tuyến message dạng cây. |
| Publish | Gửi dữ liệu lên 1 topic. |
| Subscribe | Đăng ký nhận message của topic (hoặc pattern). |
| QoS | Mức đảm bảo giao hàng (0/1/2). |
| Retained | Broker lưu bản tin cuối cùng cho topic. |
| Wildcard | Ký tự đại diện khi subscribe: `+`, `#`. |
| Last Will | Message broker tự gửi nếu client "chết" bất ngờ. |
| Clean Session | Kết nối không nhớ subscription trước đó (session state). |

---
## 3. Broker EMQX (Dev vs Prod)
Trong `docker-compose.yml`:
```yaml
emqx:
  image: emqx:5.8.2
  environment:
    - EMQX_ALLOW_ANONYMOUS=true  # DEV ONLY
```
Dev bật anonymous để dễ thử. Production:
- Tắt anonymous: `EMQX_ALLOW_ANONYMOUS=false`.
- Tạo user/password hoặc dùng JWT auth / ACL.
- Bật TLS port 8883 / 8084 (WebSocket TLS).

Dashboard: `http://localhost:18083` (đổi pass mặc định khi prod).

---
## 4. Thiết Kế Topic Trong Project
Dùng namespace `t0/devices/{uid}/...`
| Topic | Ý nghĩa |
|-------|--------|
| `t0/devices/dev-01/status` | Trạng thái online/offline (retained). |
| `t0/devices/dev-01/telemetry` | Dữ liệu đo (nhiệt độ...). |
| `t0/devices/dev-01/commands` | Lệnh điều khiển từ server xuống. |

Pattern Ingestor subscribe: `t0/devices/+/telemetry` (mọi thiết bị). 
Có thể mở rộng multi-tenant: `tenantA/devices/...`.

---
## 5. Payload Các Loại Message
Telemetry ví dụ (`sim_device.py`):
```json
{
  "msg_id": "0005",
  "ts": 1730700000,
  "data": { "temp": 22.15 }
}
```
Status retained:
```json
{ "online": true, "ts": 1730700000 }
```
Command xuống thiết bị:
```json
{ "cmd": "reboot", "reason": "manual" }
```
Best practice:
- Có `msg_id` duy nhất (UUID hoặc sequence).
- Có `ts` (UTC timestamp) để đồng bộ.
- Nhóm dữ liệu trong `data` để dễ mở rộng.

---
## 6. QoS & Ảnh Hưởng Thực Tế
| QoS | Mô tả | Ưu | Nhược |
|-----|-------|----|-------|
| 0 | At most once | Nhanh, ít overhead | Có thể mất message |
| 1 | At least once | Không mất (thường) | Có thể trùng (duplicate) |
| 2 | Exactly once | Không mất, không trùng | Chậm nhất, hiếm dùng thường xuyên |

Dự án dùng QoS1 cho telemetry (có cơ chế chống trùng bằng UNIQUE).

---
## 7. Retained Message & Trạng Thái Thiết Bị
`sim_device.py`:
```python
c.publish(f't0/devices/{uid}/status', json.dumps({...}), qos=1, retain=True)
```
Client mới subscribe status sẽ thấy ngay bản tin cuối cùng → biết thiết bị đang online.

Lưu ý: Publish retained với payload rỗng hoặc `None` để xóa.

---
## 8. Wildcard Subscribe (+ và #)
| Ký tự | Ý nghĩa |
|-------|--------|
| `+` | Đại diện đúng 1 cấp (segment). |
| `#` | Đại diện nhiều cấp cuối (chỉ xuất hiện cuối chuỗi). |

Ví dụ: `t0/devices/+/telemetry` → khớp `t0/devices/dev-01/telemetry`, `t0/devices/dev-999/telemetry`.

Không có wildcard khi publish (publish phải topic cụ thể).

---
## 9. Last Will & Clean Session (Giới Thiệu)
Last Will: Broker gửi message (ví dụ offline) nếu client ngắt bất thường.
```python
mqtt.Client(will_set=f"t0/devices/{uid}/status", payload='{"online": false}', qos=1, retain=True)
```
Clean Session: nếu `clean_session=False` (paho cũ) / persistent session, broker nhớ subscription + QoS1 message pending.

Trong demo chưa bật Last Will. Production nên dùng để chính xác trạng thái.

---
## 10. Python Publish Telemetry (paho-mqtt)
`sim_device.py`:
```python
c = mqtt.Client()
c.connect(BROKER_HOST, BROKER_PORT, 60)
for i in range(20):
    payload = {...}
    c.publish(f't0/devices/{uid}/telemetry', json.dumps(payload), qos=1)
```
Note:
- Gửi đều đặn mỗi giây.
- Sử dụng `msg_id` tăng dần để chống trùng.

---
## 11. Python Async Ingestion (asyncio-mqtt)
`ingestor/run.py`:
```python
async with Client(MQTT_HOST, MQTT_PORT) as client:
    await client.subscribe(TOPIC, qos=1)
    async with client.unfiltered_messages() as messages:
        async for m in messages:
            await handle_message(m.topic, m.payload)
```
`handle_message`:
- Parse topic lấy `device_uid`.
- Tạo `msg_id` nếu thiếu.
- Commit vào DB; rollback nếu trùng (UNIQUE). 

Nâng cấp:
- Chuyển sang `aiomqtt` (khi asyncio-mqtt deprecated hẳn).
- Batch insert.

---
## 12. Gửi Command Từ Server
`mqtt_pub.py`:
```python
async def publish_command(device_uid: str, payload: dict):
    topic = f"t0/devices/{device_uid}/commands"
    async with Client(...) as client:
        await client.publish(topic, json.dumps(payload), qos=1)
```
Thiết bị subscribe `t0/devices/dev-01/commands` để nhận.

Mẫu lệnh:
```json
{ "cmd": "set_interval", "seconds": 10 }
```

---
## 13. Flutter WebSocket MQTT Kết Nối
Flutter client (Dart) thường dùng package `mqtt_client`:
- Host: `localhost`
- Port WS: `8083`
- Path: `/mqtt`
- Kết nối → subscribe `t0/devices/dev-01/telemetry` + `t0/devices/+/status`.

Lưu ý khi chạy trên thiết bị thật: đổi `localhost` → IP.

---
## 14. Chống Trùng Dữ Liệu (Idempotency)
Trong DB: UNIQUE `(device_uid, msg_id)`.
- MQTT QoS1 có thể gửi lại (duplicate) → DB reject commit → rollback.
- Yêu cầu: thiết bị phải đảm bảo `msg_id` duy nhất.

Nếu thiếu `msg_id`, ingestor tạo UUID → không còn chống trùng.

---
## 15. Shared Subscription & Scale Worker
Scale ingestion nhiều instance để chia tải:
Topic subscribe dạng:
```
$share/ingestors/t0/devices/+/telemetry
```
Broker EMQX sẽ phân phối đều message giữa các client cùng group `ingestors`.

---
## 16. Bảo Mật Cơ Bản (Auth, ACL, TLS)
Mức dev hiện tại: anonymous ON.
Production:
1. Tắt anonymous.
2. Tạo user/role (Dashboard hoặc API).
3. Thiết lập ACL: ví dụ chỉ thiết bị `dev-01` được publish vào `t0/devices/dev-01/telemetry`.
4. Bật TLS (port 8883) – thiết bị dùng `mqtts://`.
5. Cân nhắc mutual TLS (client cert) cho thiết bị quan trọng.

---
## 17. Kiến Trúc Kết Hợp MQTT + REST
| MQTT | REST |
|------|------|
| Realtime push | Query có điều kiện |
| Nhẹ, tiết kiệm băng thông | Chuẩn hoá, dễ cache |
| Có QoS, retain | Hỗ trợ phân trang, lọc |

Luồng: MQTT thu thập → DB → REST trả lịch sử.

---
## 18. Testing Nhanh Với MQTTX / mosquitto_sub
Dùng MQTTX GUI: connect → subscribe `t0/devices/+/telemetry`.
CLI Mosquitto (nếu có):
```bash
mosquitto_sub -h localhost -p 1883 -t 't0/devices/+/telemetry' -v
```
Publish manual:
```bash
mosquitto_pub -h localhost -t 't0/devices/dev-01/telemetry' -m '{"msg_id":"m1","ts":123,"data":{"temp":23}}' -q 1
```

---
## 19. Troubleshooting (Lỗi Thường Gặp)
| Vấn đề | Nguyên nhân | Cách xử lý |
|--------|-------------|-----------|
| Không nhận message | Sai topic hoặc wildcard | Kiểm tra dấu `/` và pattern `+` |
| Trùng dữ liệu DB | msg_id trùng khi QoS1 retry | Thiết bị tạo msg_id duy nhất |
| Không connect WS | Sai path `/mqtt` hoặc port | Đúng: ws://host:8083/mqtt |
| Token expired (Auth tương lai) | JWT hết hạn | Refresh token / login lại |
| Dropped connection | Mạng kém / keepalive thấp | Tăng keepalive, bật reconnect |
| Retained cũ sai | Cập nhật status không retain | Publish lại với retain=True |

---
## 20. Tối Ưu Thực Tế & Best Practices
- Dùng QoS1 + idempotent DB key (đủ cho đa số telemetry).
- Nhóm nhiều giá trị vào 1 payload thay vì nhiều topic lẻ.
- Có chiến lược nén (gzip) nếu dữ liệu lớn (qua CDN hoặc gateway, không native MQTT).
- Bật Last Will để cập nhật offline chính xác.
- Metric: theo dõi TPS (messages/second), latency ingest → DB.
- Rate limit publish để tránh flood.

---
## 21. Checklist Cho Newbie
- [ ] Hiểu publish vs subscribe.
- [ ] Tạo 1 script paho gửi telemetry.
- [ ] Nhận được message bằng MQTTX.
- [ ] Thử retained status và thấy trên subscribe mới.
- [ ] Thử gửi duplicate cùng msg_id → DB không nhân đôi.
- [ ] Đổi wildcard `+` sang cụ thể để hiểu khác nhau.
- [ ] Đọc command từ server và xử lý (giả lập).

---
## 22. Lộ Trình Nâng Cao
1. TLS + mutual auth.
2. ACL chi tiết per topic.
3. Shared subscription cluster nhiều worker.
4. Bridge MQTT → Kafka (nếu cần phân tích lớn).
5. Nén + batching giảm chi phí.
6. QoS2 khi yêu cầu đảm bảo tuyệt đối (hiếm).
7. Thiết kế provisioning device (add/remove dynamic).

---
## 23. Tài Nguyên Tham Khảo
- MQTT OASIS Spec: https://mqtt.org/
- EMQX Docs: https://www.emqx.com/en/docs
- Paho MQTT Python: https://www.eclipse.org/paho/index.php?page=clients/python/index.php
- Async MQTT (aiomqtt): https://github.com/sbtinstruments/aiomqtt
- MQTTX: https://mqttx.app/

---
## Kết Luận
Nền tảng MQTT trong bối cảnh hệ thống: thiết bị → broker → ingestor → DB → REST + realtime UI. Hãy bắt đầu từ publish đơn giản, sau đó thêm QoS, retained, idempotency, bảo mật, scaling.
