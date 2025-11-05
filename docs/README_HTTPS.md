# Hướng Dẫn HTTPS Cho Hệ Thống FastAPI ↔ MQTT ↔ Flutter

> Mục tiêu: hiểu HTTPS là gì, tại sao cần, và cách áp dụng vào luồng hiện tại (FastAPI API, EMQX WebSocket, Flutter, thiết bị).

---
## 1. HTTPS Là Gì?
- **HTTPS = HTTP + TLS** (Transport Layer Security).
- Mã hoá kênh truyền → dữ liệu không bị nghe lén.
- Xác thực máy chủ (cert do CA tin cậy cấp).
- Toàn vẹn: phát hiện thay đổi dữ liệu trên đường đi.

### Thành phần chính
| Thành phần | Vai trò |
|------------|---------|
| Chứng chỉ (certificate) | Chứa public key, domain, CA ký tên |
| Private key | Bảo mật trên server, dùng giải mã + ký |
| TLS handshake | Thoả thuận phiên mã hoá (cipher suite, session key) |

---
## 2. Vì Sao Cần HTTPS Trong Hệ Thống Này?
| Luồng | Nguy cơ khi HTTP | Lợi ích HTTPS |
|------|------------------|---------------|
| Flutter ↔ FastAPI | Token JWT bị nghe lén | Token an toàn, cookie secure |
| Flutter ↔ EMQX (WebSocket) | Message telemetry realtime bị leak | Bảo vệ dữ liệu nhạy cảm |
| Thiết bị ↔ EMQX | Kẻ xấu giả dạng broker/s device | Mutual TLS + ACL |
| Admin truy cập Dashboard | Password admin bị sniff | Login an toàn |

---
## 3. Kiến Trúc HTTPS Đề Xuất
```
Flutter(App/Web) --HTTPS--> Nginx Reverse Proxy --HTTP--> FastAPI (port 8000)
                         |--WSS--> Nginx --> EMQX WS (8083)
Devices --MQTTS(8883)--> EMQX Broker (TLS)
Admin --HTTPS--> Nginx --> EMQX Dashboard (18083 via proxy)
```
- Nginx nhận HTTPS (443), terminate TLS.
- Backend container vẫn HTTP nội bộ (docker network).
- Thiết bị IoT: sử dụng cổng TLS của EMQX (8883) hoặc mutual TLS.

---
## 4. Thiết Lập Chứng Chỉ (Let’s Encrypt)
```bash
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d api.iot.example.com -d mqtt.iot.example.com --agree-tos -m admin@example.com --redirect
```
- Certbot tự cấu hình Nginx + gia hạn tự động (cron). 
- Kiểm tra `sudo certbot renew --dry-run`.

### Trường hợp không có domain
- Dùng self-signed certificate (chỉ dev).
- Hoặc mua wildcard / dùng ZeroSSL.

---
## 5. Cấu Hình Nginx (Ví Dụ)
`/etc/nginx/sites-available/iot.conf`:
```nginx
server {
    listen 80;
    server_name api.iot.example.com mqtt.iot.example.com;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name api.iot.example.com;

    ssl_certificate /etc/letsencrypt/live/api.iot.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.iot.example.com/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

server {
    listen 443 ssl;
    server_name mqtt.iot.example.com;

    ssl_certificate /etc/letsencrypt/live/mqtt.iot.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/mqtt.iot.example.com/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    location /mqtt {
        proxy_pass http://127.0.0.1:8083/mqtt;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
    }
}
```

---
## 6. EMQX MQTT TLS (MQTTS)
1. Trong EMQX Dashboard → Listener → bật 8883 (TLS).
2. Cung cấp cert: 
   - `certfile`: `/etc/emqx/certs/fullchain.pem`
   - `keyfile`: `/etc/emqx/certs/privkey.pem`
3. Thiết bị kết nối `mqtts://mqtt.iot.example.com:8883`.
4. Mutual TLS: nhập CA signing cert, bắt thiết bị gửi client certificate.

---
## 7. Flutter & HTTP Client
- REST: sử dụng `https://api.iot.example.com`.
- WebSocket MQTT: `wss://mqtt.iot.example.com/mqtt`.
- Nếu self-signed → cần trust cert (khuyến nghị dev-only).

---
## 8. Cập Nhật Cấu Hình Ứng Dụng
| Thành phần | Biến môi trường |
|------------|------------------|
| FastAPI | `API_BASE_URL=https://api.iot.example.com` |
| Flutter | `mqttWsUrl = wss://mqtt.iot.example.com/mqtt` |
| Ingestor | MQTT host vẫn là `emqx` (nội bộ Docker) → không cần TLS |

---
## 9. Bảo Mật Bổ Sung
- HSTS (`Strict-Transport-Security`) trên Nginx.
- Bật `Secure` + `HttpOnly` cho cookie (nếu dùng session).
- Rate limit (Nginx `limit_req`) chống brute-force.
- Sử dụng firewall chặn cổng 1883/8083 public (chỉ 443, 8883).
- Monitor cert expiry (Prometheus exporter hoặc cron).

---
## 10. Kiểm Thử HTTPS
```bash
curl -I https://api.iot.example.com/healthz
openssl s_client -connect mqtt.iot.example.com:8883
```
Flutter: đảm bảo không báo lỗi `CERTIFICATE_VERIFY_FAILED`.
Thiết bị: log handshake success.

---
## 11. Troubleshooting
| Vấn đề | Nguyên nhân | Cách xử lý |
|--------|-------------|-----------|
| `certificate verify failed` | Domain không khớp, chain thiếu | Kiểm tra DNS, fullchain.pem |
| CORS fail | Quên update origin https | `allow_origins=["https://..." ]` |
| MQTT client disconnect | TLS version mismatch | EMQX config TLSv1.2+, update client |
| Cert hết hạn | Quên renew | Cron certbot, alert trước 15 ngày |
| Mixed content | App vẫn gọi http:// | Audit code, config environment |

---
## 12. Checklist Triển Khai HTTPS
- [ ] Domain trỏ đúng IP server.
- [ ] Certbot cài đặt & cert hợp lệ.
- [ ] Nginx redirect HTTP → HTTPS.
- [ ] FastAPI trả `X-Forwarded-Proto` đúng → Trust proxy.
- [ ] WebSocket (WSS) hoạt động.
- [ ] MQTT TLS test OK (cert chain).
- [ ] HSTS bật, TLS version >=1.2.
- [ ] Cron renew kiểm tra.
- [ ] Firewall đóng cổng HTTP không cần.

---
## 13. Nguồn Tham Khảo
- HTTPS Explained: https://howhttps.works/
- Mozilla TLS Config: https://ssl-config.mozilla.org/
- EMQX TLS Guide: https://www.emqx.com/en/blog/emqx-tls-encryption-configuration
- Certbot Docs: https://certbot.eff.org/

---
## 14. Tổng Kết
- HTTPS bảo vệ REST API, WSS đảm bảo realtime secure.
- Thiết bị nên dùng MQTTS + auth.
- Quản lý cert tự động để tránh downtime.

Áp dụng các bước trên, hệ thống IoT của bạn sẽ an toàn hơn trước việc nghe lén, giả mạo và tổn thất dữ liệu.
