# So Sánh HTTP Và MQTT (Trong Hệ Thống IoT Này)

> Mục tiêu: hiểu rõ điểm mạnh/yếu của HTTP và MQTT, thời điểm sử dụng, và cách chúng bổ trợ nhau trong project.

---
## 1. Tổng Quan Nhanh
| Tiêu chí | HTTP | MQTT |
|----------|------|------|
| Mô hình | Request/Response | Publish/Subscribe |
| Kết nối | Ngắn, stateless | Duy trì kết nối (persistent) |
| Overhead | Cao hơn (header lớn) | Rất thấp (tối ưu IoT) |
| QoS | Không có built-in | Có QoS 0/1/2 |
| Realtime | Kém (phải poll) | Rất tốt (push) |
| Firewall friendly | Dễ (port 80/443) | Cần mở port riêng (1883/8883) |
| Tính chuẩn hoá | Rộng (REST, JSON, gRPC) | Dành riêng IoT, broker phụ thuộc |

---
## 2. Khi Nào Dùng HTTP?
- Truy vấn lịch sử, dữ liệu phức tạp → SQL + REST (GET `/telemetry/{device_uid}`).
- CRUD user/device, quản trị admin.
- Giao diện web/mobile → tích hợp dễ (Fetch API, axios).
- Tương thích hạ tầng sẵn có (cache, proxies, API gateway).

**Nhược điểm:**
- Polling tốn tài nguyên, không realtime.
- Header lớn, tốn băng thông cho thiết bị rất yếu.
- Không có cơ chế QoS / retain built-in.

---
## 3. Khi Nào Dùng MQTT?
- Telemetry realtime: thiết bị publish `t0/devices/dev-01/telemetry`.
- Status online/offline dùng retained message.
- Gửi command ngược (server → device) qua topic `commands`.
- Tối ưu băng thông, định dạng linh hoạt.

**Nhược điểm:**
- Cần broker (EMQX) vận hành.
- Thiết kế topic/ACL cẩn thận để tránh lộ dữ liệu.
- Không phù hợp query lịch sử phức tạp (phải lưu DB).

---
## 4. Cách Kết Hợp Trong Project
```
Device ----MQTT----> EMQX -----> Ingestor -----> PostgreSQL
                                   │             │
                                   ▼             ▼
                                MQTT WS        REST (HTTP)
                                   │             │
                                Flutter ⟵----------------
```
- **MQTT**: luồng realtime đi thẳng (đo nhiệt độ, status, command).
- **HTTP REST**: lấy dữ liệu quá khứ, login, quản lý.
- Flutter nhận dữ liệu mới qua MQTT và dùng REST để refresh lịch sử.

---
## 5. QoS & Độ Tin Cậy
| QoS | Mô tả | So sánh HTTP |
|-----|-------|--------------|
| 0 | At most once | HTTP không có QoS, coi như QoS0 |
| 1 | At least once | HTTP có thể retry nhưng không idempotent → cần tự xử lý |
| 2 | Exactly once | HTTP không có tương đương |

Trong hệ thống: dùng QoS1 + `msg_id` UNIQUE để chống trùng.

---
## 6. Độ Trễ & Băng Thông
- MQTT: payload nhỏ, giữ kết nối → độ trễ thấp (<100ms tuỳ mạng).
- HTTP: mỗi request tạo kết nối (hoặc keep-alive) → overhead, header ~800 byte.
- Thiết bị pin yếu → MQTT tiết kiệm đáng kể.

---
## 7. Bảo Mật
| Giao thức | Phương án |
|-----------|-----------|
| HTTP | HTTPS (TLS) + JWT / OAuth2 |
| MQTT | MQTTS (TLS 8883), username/password, ACL topic, mutual TLS |

Cần đồng bộ credential, phân quyền (ví dụ thiết bị chỉ publish topic của nó).

---
## 8. Triển khai & Vận hành
| Tiêu chí | HTTP | MQTT |
|----------|------|------|
| Triển khai | Uvicorn, Nginx reverse proxy | EMQX cluster, listener config |
| Monitoring | Access log, Prometheus, APM | EMQX metrics, message rate |
| Scaling | Load balancer, horizontal pods | Shared subscription, cluster broker |

---
## 9. Troubleshooting (So Sánh)
| Hiện tượng | HTTP | MQTT |
|------------|------|------|
| Không nhận dữ liệu | Kiểm tra response code, log API | Kiểm tra subscription, topic, ACL |
| Lặp dữ liệu | Idempotent endpoint, ETag | msg_id trùng, QoS1 retry |
| Timeout | Nginx/Client timeout | Keepalive thấp, broker disconnect |

---
## 10. Checklist Quyết Định Giao Thức
- [ ] Cần realtime push? → MQTT.
- [ ] Packet < 1KB, gửi thường xuyên? → MQTT.
- [ ] Cần query phức tạp, lọc, phân trang? → HTTP + DB.
- [ ] Muốn thiết bị dễ dùng (REST client)? → HTTP.
- [ ] Cần gửi lệnh xuống thiết bị? → MQTT (commands) + ack.
- [ ] Tích hợp bên thứ ba (Zapier/Webhook)? → HTTP.

---
## 11. Kịch Bản Mở Rộng
- **HTTP Streaming / SSE**: thay thế polling nếu không muốn MQTT.
- **MQTT → HTTP bridge**: EMQX rule engine forward message vào REST khi cần ghi dữ liệu.
- **MQTT + Kafka**: khi cần phân tích big data.
- **REST + WebSocket**: All-in-one, nhưng MQTT vẫn nhẹ hơn cho IoT.

---
## 12. Khuyến Nghị Thực Tế
1. Giữ cả hai giao thức: REST cho lịch sử/quản trị, MQTT cho realtime.
2. Tài liệu hoá topic, payload, QoS, ACL rõ ràng.
3. Đảm bảo REST endpoint idempotent hoặc có lock khi nhận command từ MQTT bridging.
4. Monitor message rate MQTT để điều chỉnh QoS/payload.
5. Dùng TLS cho cả hai (HTTPS, WSS, MQTTS).

---
## 13. Tài Liệu Tham Khảo
- MQTT vs HTTP: https://www.hivemq.com/mqtt-vs-rest/ 
- MQTT Essentials: https://www.hivemq.com/mqtt-essentials/ 
- REST Best Practices: https://restfulapi.net/ 
- EMQX Documentation: https://www.emqx.com/en/docs 

---
## 14. Kết Luận
HTTP và MQTT không loại trừ nhau. Trong ứng dụng IoT này:
- MQTT đảm nhận realtime, nhẹ, push.
- HTTP đảm nhận truy vấn lịch sử, auth, quản trị.
Kết hợp cả hai giúp hệ thống linh hoạt, hiệu quả và dễ tích hợp.
