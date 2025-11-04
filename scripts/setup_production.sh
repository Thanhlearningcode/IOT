#!/usr/bin/env bash
# setup_production.sh - Script tự động hoá triển khai cơ bản cho MQTT + FastAPI + Postgres + EMQX
# Dùng trên Ubuntu 22.04 (root hoặc user có sudo). Chạy: sudo bash setup_production.sh
# WARNING: Kiểm tra lại DOMAIN, EMAIL, SECRET trước khi chạy. Script mang tính tham khảo, có thể tuỳ chỉnh thêm.

set -euo pipefail

# ==========================
# CẤU HÌNH TUỲ CHỈNH (EDIT)
# ==========================
API_DOMAIN="api.iot.example.com"        # Domain cho REST API
MQTT_DOMAIN="mqtt.iot.example.com"      # Domain cho MQTT WebSocket
ADMIN_EMAIL="admin@example.com"        # Email nhận thông báo Certbot
REPO_URL="https://your.repo/mqtt_fastapi_postgres_flutter_demo.git"  # Thay bằng repo thực tế
INSTALL_DIR="/opt/mqtt_fastapi_postgres_flutter_demo"
JWT_SECRET="ChangeMe_SuperSecret_2025"  # Thay bằng chuỗi mạnh hơn
EMQX_DASHBOARD_USER="admin"
EMQX_DASHBOARD_PASS="StrongDash#2025"   # Thay đổi dashboard password
POSTGRES_PASSWORD="secret"              # Có thể thay bằng password mạnh

# ==========================
# HÀM TIỆN ÍCH
# ==========================
log() { echo -e "\e[32m[INFO]\e[0m $*"; }
warn() { echo -e "\e[33m[WARN]\e[0m $*"; }
err() { echo -e "\e[31m[ERROR]\e[0m $*"; }

require_root() {
  if [[ $EUID -ne 0 ]]; then
    err "Script cần chạy với sudo hoặc root. Dùng: sudo bash setup_production.sh"; exit 1
  fi
}

# ==========================
# 1. CẬP NHẬT HỆ THỐNG
# ==========================
require_root
log "Cập nhật apt package index ..."
apt update -y && apt upgrade -y

# ==========================
# 2. CÀI ĐẶT TIỆN ÍCH CƠ BẢN
# ==========================
log "Cài curl, git, ufw, nginx, certbot ..."
apt install -y curl git ufw nginx certbot python3-certbot-nginx

# ==========================
# 3. CÀI DOCKER & COMPOSE
# ==========================
if ! command -v docker >/dev/null 2>&1; then
  log "Cài Docker bằng script chính thức ..."
  curl -fsSL https://get.docker.com | sh
else
  log "Docker đã tồn tại, bỏ qua."; fi

if ! docker compose version >/dev/null 2>&1; then
  warn "Docker compose plugin chưa thấy, đảm bảo phiên bản Docker mới."
fi

# Cho phép user hiện tại dùng docker (nếu không phải root)
if id "${SUDO_USER}" &>/dev/null && [[ "${SUDO_USER}" != "root" ]]; then
  log "Thêm ${SUDO_USER} vào nhóm docker"
  usermod -aG docker "${SUDO_USER}" || true
fi

# ==========================
# 4. FIREWALL
# ==========================
log "Thiết lập UFW firewall ..."
ufw allow OpenSSH || true
ufw allow 80/tcp || true
ufw allow 443/tcp || true
# Tuỳ chọn: mở 1883 nếu thiết bị kết nối trực tiếp qua TCP MQTT
ufw allow 1883/tcp || true
ufw --force enable

# ==========================
# 5. CLONE REPO
# ==========================
if [[ -d "$INSTALL_DIR" ]]; then
  warn "Thư mục $INSTALL_DIR đã tồn tại, kéo cập nhật (git pull)."
  cd "$INSTALL_DIR" && git pull || warn "Không thể pull, kiểm tra repo URL."
else
  log "Clone code vào $INSTALL_DIR"
  git clone "$REPO_URL" "$INSTALL_DIR"
fi
cd "$INSTALL_DIR"

# ==========================
# 6. TẠO FILE .env
# ==========================
log "Tạo file .env ..."
cat > .env <<EOF
JWT_SECRET=$JWT_SECRET
DATABASE_URL=postgresql+asyncpg://app:$POSTGRES_PASSWORD@db:5432/app
MQTT__HOST=emqx
MQTT__WS_URL=ws://emqx:8083/mqtt
MQTT__PORT=1883
MQTT__TOPIC=t0/devices/+/telemetry
EMQX_ALLOW_ANONYMOUS=false
EMQX_DASHBOARD_DEFAULT_USERNAME=$EMQX_DASHBOARD_USER
EMQX_DASHBOARD_DEFAULT_PASSWORD=$EMQX_DASHBOARD_PASS
EOF

# ==========================
# 7. CHỈNH DOCKER-COMPOSE (THÊM VOLUMES NẾU CHƯA CÓ)
# ==========================
log "Đảm bảo docker-compose.yml có volumes cho Postgres"
if ! grep -q 'pg_data' docker-compose.yml; then
  cat >> docker-compose.yml <<'YAML_APPEND'

volumes:
  pg_data:
YAML_APPEND
  log "Đã append volumes section.";
fi
# Thêm env_file nếu chưa
if ! grep -q 'env_file:' docker-compose.yml; then
  sed -i 's/^  api:/  api:\n    env_file: .env/' docker-compose.yml || true
  sed -i 's/^  ingestor:/  ingestor:\n    env_file: .env/' docker-compose.yml || true
  sed -i 's/^  emqx:/  emqx:\n    env_file: .env/' docker-compose.yml || true
  sed -i 's/^  db:/  db:\n    env_file: .env/' docker-compose.yml || true
fi

# ==========================
# 8. BUILD & RUN STACK
# ==========================
log "Khởi động stack Docker ..."
docker compose up -d --build
sleep 5
docker compose ps

# ==========================
# 9. NGINX REVERSE PROXY CONFIG
# ==========================
log "Tạo file Nginx reverse proxy ..."
NGINX_FILE="/etc/nginx/sites-available/iot.conf"
cat > "$NGINX_FILE" <<NGINX
server {
    listen 80;
    server_name $API_DOMAIN;
    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}

server {
    listen 80;
    server_name $MQTT_DOMAIN;
    location /mqtt {
        proxy_pass http://127.0.0.1:8083/mqtt;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
NGINX
ln -sf "$NGINX_FILE" /etc/nginx/sites-enabled/iot.conf
nginx -t && systemctl reload nginx

# ==========================
# 10. SSL (CERTBOT)
# ==========================
if [[ "$API_DOMAIN" != "api.iot.example.com" ]]; then
  log "Chạy Certbot lấy HTTPS cho $API_DOMAIN và $MQTT_DOMAIN"
  certbot --nginx -d "$API_DOMAIN" -d "$MQTT_DOMAIN" -m "$ADMIN_EMAIL" --agree-tos --non-interactive --redirect || warn "Certbot thất bại, kiểm tra domain DNS." 
else
  warn "Domain là mặc định placeholder, bỏ qua Certbot. Sửa API_DOMAIN/MQTT_DOMAIN rồi chạy lại phần SSL.";
fi

# ==========================
# 11. BACKUP SCRIPT
# ==========================
log "Tạo script backup Postgres /opt/pg_backup.sh"
cat > /opt/pg_backup.sh <<'BK'
#!/usr/bin/env bash
set -e
DATE=$(date +%Y%m%d_%H%M)
mkdir -p /opt/backup
docker exec mqtt_fastapi_postgres_flutter_demo-db-1 pg_dump -U app app > /opt/backup/pg_${DATE}.sql
find /opt/backup -type f -mtime +7 -delete
BK
chmod +x /opt/pg_backup.sh

# Cron entry (chỉ thêm nếu chưa có)
CRON_LINE="0 2 * * * /opt/pg_backup.sh"
if ! crontab -l 2>/dev/null | grep -q '/opt/pg_backup.sh'; then
  (crontab -l 2>/dev/null; echo "$CRON_LINE") | crontab -
fi

# ==========================
# 12. SYSTEMD UNIT (TUỲ CHỌN)
# ==========================
log "Tạo systemd unit (iot-stack.service)"
UNIT_FILE="/etc/systemd/system/iot-stack.service"
cat > "$UNIT_FILE" <<UNIT
[Unit]
Description=IoT Stack
After=network-online.target docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now iot-stack.service

# ==========================
# 13. HOÀN TẤT
# ==========================
log "HOÀN TẤT: Kiểm tra truy cập http://$API_DOMAIN (hoặc IP:8000 nếu chưa cấu hình domain)."
log "MQTT WS qua wss://$MQTT_DOMAIN/mqtt (sau khi có SSL)."
log "Xem logs: docker logs mqtt_fastapi_postgres_flutter_demo-api-1 --tail 50"
log "Backup: /opt/backup/*"
log "Nếu thay đổi domain/secret: sửa .env + nginx + chạy lại Certbot."

exit 0
