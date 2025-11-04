#!/usr/bin/env bash
# pg_backup.sh - Sao lưu PostgreSQL container và xoá file quá 7 ngày.
# Chạy độc lập hoặc qua cron. Ví dụ thêm vào crontab: 0 2 * * * /opt/pg_backup.sh

set -euo pipefail
DATE=$(date +%Y%m%d_%H%M)
BACKUP_DIR="/opt/backup"
CONTAINER_NAME="mqtt_fastapi_postgres_flutter_demo-db-1"
DB_NAME="app"
DB_USER="app"

mkdir -p "$BACKUP_DIR"
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "[ERROR] Container ${CONTAINER_NAME} không chạy." >&2
  exit 1
fi

FILE="${BACKUP_DIR}/pg_${DATE}.sql"

echo "[INFO] Dumping database ${DB_NAME} vào ${FILE} ..."
docker exec "$CONTAINER_NAME" pg_dump -U "$DB_USER" "$DB_NAME" > "$FILE"

echo "[INFO] Xoá backup cũ quá 7 ngày ..."
find "$BACKUP_DIR" -type f -name 'pg_*.sql' -mtime +7 -delete || true

echo "[INFO] Hoàn tất."
