# PostgreSQL & SQLAlchemy Async A‑Z (Dành Cho Newbie – Trong Bối Cảnh Project)

> Mục tiêu: Hiểu cách kết nối, thiết kế bảng, truy vấn, tối ưu, bảo mật, kiểm thử và mở rộng dữ liệu telemetry trong hệ thống FastAPI + PostgreSQL.

---
## 1. PostgreSQL Là Gì? Vì Sao Dùng Ở Đây?
PostgreSQL là hệ quản trị CSDL quan hệ mạnh mẽ, hỗ trợ:
- ACID (an toàn giao dịch)
- Kiểu JSON / JSONB linh hoạt
- Index đa dạng (BTREE, GIN, GiST)
- Khả năng mở rộng (partitioning, replication)

Chúng ta dùng để lưu Users, Devices, Telemetry bảo đảm tính nhất quán và truy vấn linh hoạt (lọc thời gian, phân trang, thống kê sau này).

---
## 2. Cài Đặt / Khởi Chạy
Trong `docker-compose.yml`:
```yaml
db:
  image: postgres:16
  environment:
    - POSTGRES_DB=app
    - POSTGRES_USER=app
    - POSTGRES_PASSWORD=secret
  ports: ["5432:5432"]
```
Local manual (tuỳ chọn):
```bash
# Linux
sudo -u postgres createuser -P app
sudo -u postgres createdb -O app app
```
Kết nối kiểm tra:
```powershell
psql -h localhost -U app -d app -c "SELECT 1;"
```

---
## 3. Chuỗi Kết Nối (Connection URL)
Định dạng chung:
```
postgresql+asyncpg://USER:PASSWORD@HOST:PORT/DBNAME
```
Ví dụ trong project: `postgresql+asyncpg://app:secret@db:5432/app`

Đặt vào biến môi trường `DATABASE_URL` để `db.py` đọc.

---
## 4. Engine & Session (Async SQLAlchemy)
`db.py`:
```python
engine = create_async_engine(DATABASE_URL, echo=False, pool_pre_ping=True)
SessionLocal = sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)
async def get_db():
    async with SessionLocal() as session:
        yield session
```
Giải thích:
- `create_async_engine` dùng driver async (`asyncpg`).
- `pool_pre_ping=True` kiểm tra kết nối hỏng trước khi dùng.
- `expire_on_commit=False` giữ object accessible sau commit.
- Mỗi request tạo session riêng (pattern an toàn).

---
## 5. Định Nghĩa Model (ORM)
`models.py` ví dụ:
```python
class Telemetry(Base):
    __tablename__ = "telemetry"
    id = Column(BigInteger, primary_key=True)
    device_uid = Column(String, ForeignKey("devices.device_uid"), nullable=False)
    msg_id = Column(String, nullable=False)
    payload = Column(JSON, nullable=False)
    ts = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    __table_args__ = (UniqueConstraint("device_uid", "msg_id", name="uq_device_msg"),)
```
Điểm hay:
- Dùng `JSON` cho payload linh hoạt (chưa cần schema cứng từng field).
- Unique `(device_uid, msg_id)` chống trùng bản tin.
- `ForeignKey` đảm bảo telemetry thuộc device hợp lệ.

---
## 6. Ràng Buộc & Tính Toàn Vẹn
Loại thường dùng:
| Kiểu | Mục đích |
|------|----------|
| PRIMARY KEY | Định danh duy nhất dòng |
| UNIQUE | Chống trùng (ví dụ msg_id lặp) |
| FOREIGN KEY | Liên kết bảng, đảm bảo khóa tồn tại |
| CHECK | Giới hạn giá trị (ví dụ nhiệt độ > -50) |
| NOT NULL | Bắt buộc có giá trị |

Ví dụ thêm CHECK (gợi ý):
```sql
ALTER TABLE telemetry ADD CONSTRAINT chk_payload_temp CHECK ((payload->'data'->>'temp')::float < 150);
```

---
## 7. CRUD Cơ Bản (Async)
Tạo mới (User):
```python
user = User(email=email, password_hash=hash_pw)
db.add(user)
await db.commit()
await db.refresh(user)  # lấy giá trị id sau commit
```
Đọc:
```python
res = await db.execute(select(User).where(User.email == email))
user = res.scalar_one_or_none()
```
Cập nhật:
```python
user.role = "admin"
await db.commit()
```
Xóa:
```python
await db.delete(user)
await db.commit()
```

---
## 8. Truy Vấn Linh Hoạt
Lọc kết hợp:
```python
stmt = (
  select(Telemetry)
  .where(Telemetry.device_uid == device_uid)
  .where(Telemetry.ts >= from_ts)
  .where(Telemetry.ts < to_ts)
  .order_by(Telemetry.ts.desc())
  .limit(100)
)
rows = (await db.execute(stmt)).scalars().all()
```
Phân trang:
```python
offset = (page - 1) * size
stmt = select(Telemetry).offset(offset).limit(size)
```
Đếm tổng:
```python
total = (await db.execute(select(func.count()).select_from(Telemetry))).scalar()
```

---
## 9. Transaction & Rollback
Pattern an toàn:
```python
try:
    db.add(obj)
    await db.commit()
except Exception:
    await db.rollback()
    raise
```
Trong ingestor đã dùng rollback khi duplicate (vi phạm UNIQUE).

Bulk insert (giảm round-trip):
```python
db.add_all([Telemetry(...), Telemetry(...), ...])
await db.commit()
```

---
## 10. Upsert (Insert Hoặc Update Khi Trùng)
SQL gốc:
```sql
INSERT INTO telemetry (device_uid, msg_id, payload)
VALUES (:device_uid, :msg_id, :payload)
ON CONFLICT (device_uid, msg_id)
DO UPDATE SET payload = EXCLUDED.payload;
```
Async thực hiện:
```python
await db.execute(
  text("""
  INSERT INTO telemetry (device_uid,msg_id,payload)
  VALUES (:d,:m,:p)
  ON CONFLICT (device_uid,msg_id) DO UPDATE SET payload = EXCLUDED.payload
  """),
  {"d": device_uid, "m": msg_id, "p": payload_dict}
)
await db.commit()
```
Upsert hữu ích khi muốn override dữ liệu không tạo duplicate.

---
## 11. Index & Hiệu Năng
Kiểu phổ biến:
```sql
CREATE INDEX idx_telemetry_device_ts ON telemetry (device_uid, ts DESC);
```
Tìm kiếm bên trong JSON:
```sql
CREATE INDEX idx_payload_temp ON telemetry USING GIN ((payload));
-- Sau đó WHERE (payload->'data'->>'temp')::float > 25
```
Khi truy vấn nhiều cột, index composite có thể tốt hơn 2 index đơn lẻ.

---
## 12. Partitioning (Khi Dữ Liệu Rất Lớn)
Ý tưởng: mỗi tháng 1 bảng con → giảm kích thước index.
Ví dụ khởi tạo:
```sql
CREATE TABLE telemetry_all (
  id BIGSERIAL PRIMARY KEY,
  device_uid TEXT NOT NULL,
  msg_id TEXT NOT NULL,
  payload JSONB NOT NULL,
  ts TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (device_uid,msg_id)
) PARTITION BY RANGE (ts);

CREATE TABLE telemetry_2025_11 PARTITION OF telemetry_all
FOR VALUES FROM ('2025-11-01') TO ('2025-12-01');
```
App code query `telemetry_all` vẫn hoạt động. Thêm partition tiếp theo hàng tháng.

---
## 13. Chiến Lược Retention (Xoá / Lưu Trữ)
Khi dữ liệu tăng quá lớn:
- Giữ 90 ngày gần nhất trong bảng chính.
- Archive > 90 ngày sang storage rẻ (S3 + parquet).
- Cron job chạy câu lệnh:
```sql
DELETE FROM telemetry WHERE ts < now() - interval '90 days';
```
Hoặc chuyển sang partition cũ rồi DROP TABLE partition.

---
## 14. Bảo Mật Cấp DB
| Vấn đề | Giải pháp |
|--------|-----------|
| Dùng superuser cho app | Tạo role riêng chỉ SELECT/INSERT/UPDATE |
| Password yếu | Dài > 12 ký tự, rotate định kỳ |
| SQL Injection | Luôn dùng parameter binding (`:param`) |
| Lộ dữ liệu backup | Mã hoá file dump / lưu trong private bucket |
| Grant rộng | `GRANT SELECT ON telemetry TO readonly_role` |

Tạo role:
```sql
CREATE ROLE app_rw LOGIN PASSWORD 'ChangeMe2025!';
GRANT CONNECT ON DATABASE app TO app_rw;
GRANT USAGE ON SCHEMA public TO app_rw;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_rw;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_rw;
```

---
## 15. Connection Pool Tuning
Mặc định có thể đủ cho dev. Khi tải cao:
- `pool_size` (số kết nối giữ sẵn)
- `max_overflow` (tạm thời thêm kết nối khi peak)
- Tránh quá cao → gây áp lực đến Postgres.
Ví dụ:
```python
e = create_async_engine(DATABASE_URL, pool_size=10, max_overflow=20)
```
Theo dõi `SELECT * FROM pg_stat_activity;` để thấy số kết nối thực.

---
## 16. Thử Nghiệm Query (EXPLAIN / ANALYZE)
Dùng psql:
```sql
EXPLAIN ANALYZE SELECT * FROM telemetry WHERE device_uid='dev-01' ORDER BY id DESC LIMIT 100;
```
Kiểm tra:
- Seq Scan hay Index Scan?
- Thời gian ms
- Số row hợp lý
Tối ưu bằng index hoặc phân trang đúng.

---
## 17. Sử Dụng Raw SQL (Khi Cần)
SQLAlchemy text:
```python
from sqlalchemy import text
rows = (await db.execute(text("SELECT device_uid, count(*) FROM telemetry GROUP BY device_uid"))).all()
```
Sử dụng khi truy vấn phức tạp hơn ORM hoặc cần hàm Postgres đặc thù (window function, CTE).

---
## 18. Kiểm Thử Database
Dùng DB riêng cho test:
- Tạo `DATABASE_URL_TEST` (ví dụ app_test).
- Alembic migrate vào test DB.
- Dùng fixture pytest tạo/dọn dữ liệu.
Ví dụ fixture đơn giản:
```python
@pytest.fixture
async def db_session():
    async with SessionLocal() as s:
        yield s
```
(Tạo SessionLocal test trỏ tới test engine.)

Khi cần isolation: wrap mỗi test trong transaction rollback cuối.

---
## 19. Backup & Restore
Backup:
```powershell
pg_dump -h localhost -U app -d app > backup.sql
```
Restore vào DB rỗng:
```powershell
psql -h localhost -U app -d newdb -f backup.sql
```
Nén & dọn cũ:
```powershell
gzip backup.sql
find backups -type f -mtime +7 -delete
```

---
## 20. Quan Sát & Monitoring
Công cụ:
- `pg_stat_statements` – thống kê query tốn tài nguyên.
- `pgBadger` – phân tích log Postgres.
- Prometheus exporter: `postgres_exporter`.

Bật extension:
```sql
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```
Xem top query:
```sql
SELECT query, calls, total_time FROM pg_stat_statements ORDER BY total_time DESC LIMIT 10;
```

---
## 21. Migrations Với Alembic (Hướng Dẫn Nhanh)
Cài:
```powershell
pip install alembic
alembic init alembic
```
Sửa `alembic.ini` → `sqlalchemy.url = postgresql+asyncpg://app:secret@db:5432/app`
Trong `env.py` dùng async engine pattern (theo docs SQLAlchemy 2.0).
Tạo revision:
```powershell
alembic revision -m "create telemetry" --autogenerate
alembic upgrade head
```
Ghi chú:
- Khi đổi model (thêm cột), tạo revision mới.
- Production: commit migration trước khi deploy code.

---
## 22. Repository Pattern (Tổ Chức Code)
Ví dụ tách logic:
```python
# repositories/telemetry_repo.py
class TelemetryRepo:
    @staticmethod
    async def list_recent(db: AsyncSession, device_uid: str, limit: int = 100):
        stmt = (
            select(Telemetry)
            .where(Telemetry.device_uid == device_uid)
            .order_by(Telemetry.id.desc())
            .limit(limit)
        )
        return (await db.execute(stmt)).scalars().all()
```
Endpoint dùng:
```python
rows = await TelemetryRepo.list_recent(db, device_uid)
```
Lợi ích: dễ test riêng repo, endpoint mỏng.

---
## 23. Xử Lý Duplicate Nâng Cao
Hiện tại: rollback khi vi phạm UNIQUE.
Nâng cấp:
- Upsert (ON CONFLICT DO NOTHING / DO UPDATE)
- Ghi log số lần duplicate để thống kê chất lượng kết nối.
- Sử dụng hàng đợi (buffer) trước DB nếu tốc độ quá cao.

---
## 24. Chiến Lược Scale
| Vấn đề | Giải pháp |
|--------|-----------|
| Rất nhiều telemetry (TPS cao) | Partition + batch insert |
| Đọc nhiều gây nóng DB | Cache Redis kết quả gần nhất |
| Cần phân tích phức tạp | ETL sang Data Warehouse (BigQuery / ClickHouse) |
| Muốn HA | Streaming Replication / Patroni |

---
## 25. Lỗi Thường Gặp & Khắc Phục
| Lỗi | Nguyên nhân | Giải pháp |
|-----|-------------|-----------|
| `psycopg2` import sai | Dùng driver sync | Đảm bảo dùng asyncpg trong URL |
| Timeout kết nối | Pool nhỏ / mạng chậm | Tăng `pool_size`, kiểm tra latency |
| Duplicate telemetry | msg_id trùng | Thiết bị đảm bảo uniqueness hoặc upsert |
| Lock bảng | Transaction dài / vacuum chậm | Giảm thời gian giữ transaction, monitor locks |
| Hiệu năng giảm | Không có index phù hợp | Thêm index composite (device_uid, ts) |

---
## 26. Checklist Cho Bạn
- [ ] Có UNIQUE chống trùng telemetry
- [ ] Index chính dùng cho truy vấn thời gian
- [ ] Tách repository để code endpoint gọn
- [ ] Migrations Alembic hoạt động
- [ ] Có script backup + dọn cũ
- [ ] Connection pool không vượt quá giới hạn server
- [ ] Đã kiểm tra EXPLAIN query nặng
- [ ] Sẵn sàng partition nếu > triệu dòng

---
## 27. Lộ Trình Nâng Cao
1. Thêm cột `ingest_latency_ms` để đo hiệu năng.
2. Thiết lập pg_stat_statements + dashboard Grafana.
3. Partition theo tháng + job tự tạo partition mới.
4. Lưu lịch sử thay đổi thiết bị (audit table).
5. Cơ chế TTL tự động với trigger.
6. Logical replication stream ra Kafka.

---
## 28. Tài Nguyên Tham Khảo
- SQLAlchemy Async: https://docs.sqlalchemy.org/en/20/orm/extensions/asyncio.html
- Postgres Docs: https://www.postgresql.org/docs/
- Alembic: https://alembic.sqlalchemy.org/
- asyncpg: https://github.com/MagicStack/asyncpg
- pg_stat_statements: https://www.postgresql.org/docs/current/pgstatstatements.html

---
## 29. Kết Luận
Nền tảng giao tiếp PostgreSQL: model → session → CRUD → transaction → tối ưu. Khi dữ liệu lớn, nghĩ đến partition, index logic, cache và pipeline ETL.

Tiếp theo: áp dụng repository + migrations, đo hiệu năng, bảo vệ dữ liệu dài hạn.

Làm chủ được PostgreSQL trong hệ thống IoT này! 🚀
