# Hướng Dẫn FastAPI 

## Mục lục nhanh
1. FastAPI Là Gì? Vì Sao Dùng?
2. Cài Đặt Nhanh & Hello World
3. Cấu Trúc Dự Án Khuyến Nghị
4. Endpoint (Path Operation)
5. Request Body & Pydantic Model
6. Dependency Injection (`Depends`)
7. Async vs Sync Endpoint
8. Kết Nối Database Async
9. Authentication JWT Đơn Giản
10. Error Handling
11. CORS Middleware
12. Background Tasks
13. WebSocket Cơ Bản
14. Pagination & Filtering
15. Logging & Cấu Hình
16. Testing (pytest + httpx)
17. Tùy Biến Docs
18. Performance Cơ Bản
19. Bảo Mật Cốt Lõi
20. Docker Hoá Nhanh
21. Quản Lý Biến Môi Trường
22. Tổ Chức Code Lớn Hơn
23. Pitfall Thường Gặp
24. Checklist Cho Newbie
25. Lộ Trình Học Thêm
26. Ví Dụ End-to-End
27. Nâng Cấp Telemetry
28. Tối Ưu Bảo Mật JWT
29. Tài Nguyên Tham Khảo
30. Kết Luận
31. Lộ Trình / Lịch Phát Triển Chi Tiết

> Mục tiêu: Sau khi đọc xong bạn hiểu cách xây dựng API với FastAPI: từ cài đặt, endpoint, model, DB async, JWT, test, bảo mật, tối ưu và đóng gói Docker.

---
## 1. FastAPI Là Gì? Vì Sao Dùng?
FastAPI là framework Python hiện đại để xây dựng API nhanh, dựa trên:
- Kiểu khai báo (Python type hints) → tự sinh docs Swagger + validate dữ liệu.
- Hiệu năng cao (Starlette + Uvicorn, async), gần mức Node / Go ở nhiều scenario.
- Học nhanh: code ngắn, rõ ràng.

Khi nào nên chọn?
- Bạn cần REST API nhẹ, nhiều CRUD.
- Muốn tự động có OpenAPI docs.
- Muốn tận dụng async (gọi DB, dịch vụ ngoài song song).

---
## 2. Cài Đặt Nhanh & Hello World
Tạo virtualenv (khuyên dùng):
```powershell
python -m venv .venv
.\.venv\Scripts\activate
pip install fastapi uvicorn[standard]
```
File `hello.py`:
```python
from fastapi import FastAPI
app = FastAPI()

@app.get("/")
async def root():
    return {"message": "Hello FastAPI"}
```
Chạy:
```powershell
uvicorn hello:app --reload --port 8000
```
Mở: http://localhost:8000/docs (Swagger) và http://localhost:8000/redoc.

---
## 3. Cấu Trúc Dự Án Khuyến Nghị (Ví dụ từ repo này)
```
backend/
  app/
    main.py          (điểm vào FastAPI)
    auth.py          (JWT tạo & kiểm tra)
    db.py            (kết nối Async SQLAlchemy)
    models.py        (ORM models)
    schemas.py       (Pydantic request/response)
    mqtt_pub.py      (ví dụ gửi lệnh MQTT - ngoài phạm vi API chuẩn)
  ingestor/          (worker nền - không phải FastAPI)
    run.py
```
Khi mở rộng lớn hơn, tách thêm:
- `routers/` – nhóm endpoint theo domain.
- `services/` – logic nghiệp vụ.
- `repositories/` – giao tiếp DB.
- `core/config.py` – biến môi trường, settings.

---
## 4. Endpoint (Path Operation) Cơ Bản
Mẫu trong `main.py`:
```python
@app.post("/auth/login", response_model=TokenOut)
async def login(body: LoginIn, db: AsyncSession = Depends(get_db)):
    ...
```
Ý nghĩa:
- `@app.post("/auth/login")` → method POST.
- `response_model=TokenOut` → trả về Pydantic model (tự lọc field thừa).
- Tham số `body: LoginIn` tự động parse JSON request.

Các method thường dùng:
- `@app.get` (lấy dữ liệu / read)
- `@app.post` (tạo / hành động có side-effect)
- `@app.put` (cập nhật toàn bộ)
- `@app.patch` (cập nhật một phần)
- `@app.delete` (xóa)

---
## 5. Request Body & Pydantic Model
`schemas.py`:
```python
class LoginIn(BaseModel):
    email: EmailStr
    password: str
```
Validate tự động:
- Nếu email sai định dạng → HTTP 422 với chi tiết lỗi.
- Password không phải string → cũng 422.

Response model:
```python
class TokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"
```
Khai báo trong endpoint `response_model=TokenOut` giúp:
- Chỉ trả fields định nghĩa.
- Tự sinh docs ở `/docs`.

---
## 6. Dependency Injection (`Depends`)
Trong login:
```python
async def login(body: LoginIn, db: AsyncSession = Depends(get_db)):
```
- `Depends(get_db)` gọi hàm `get_db()` (context async session) và inject vào tham số `db`.
- Giúp tái sử dụng: các endpoint khác chỉ cần thêm cùng pattern.

Ví dụ custom dependency (bắt buộc API key):
```python
from fastapi import Header, HTTPException

def require_api_key(x_api_key: str = Header(...)):
    if x_api_key != "secret-demo":
        raise HTTPException(status_code=401, detail="Bad API key")
```
Dùng:
```python
@app.get("/secure", dependencies=[Depends(require_api_key)])
async def secure():
    return {"ok": True}
```

---
## 7. Async vs Sync Endpoint
Bạn có thể viết:
```python
@app.get("/sync")
def sync_example():
    return {"mode": "sync"}
```
hoặc:
```python
@app.get("/async")
async def async_example():
    return {"mode": "async"}
```
Khuyến nghị dùng `async def` khi:
- Gọi DB async.
- Chờ IO (HTTP request khác, gởi email...).

Nếu viết `async` nhưng làm tác vụ CPU nặng (ví dụ xử lý ảnh lớn) → block event loop. Dùng thread pool (`run_in_threadpool`) hoặc tách background worker.

---
## 8. Kết Nối Database (Async SQLAlchemy)
`db.py`:
```python
engine = create_async_engine(DATABASE_URL, echo=False, pool_pre_ping=True)
SessionLocal = sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)
async def get_db():
    async with SessionLocal() as session:
        yield session
```
Mẫu truy vấn trong `login`:
```python
res = await db.execute(select(User).where(User.email == body.email))
user = res.scalar_one_or_none()
```
Lưu ý:
- Dùng `await` mỗi thao tác DB.
- Sau khi `db.add(...)` nhớ `await db.commit()` để ghi.

Nâng cấp:
- Tách repository: `UserRepository.get_by_email(db, email)`.
- Thêm migration: Alembic.

---
## 9. Authentication JWT Đơn Giản
`auth.py`:
```python
def create_token(sub: str, minutes: int = 60):
    payload = {"sub": sub, "iat": now, "exp": now + timedelta(minutes=minutes)}
    return jwt.encode(payload, JWT_SECRET, algorithm=ALGO)
```
Check token:
```python
def require_user(token: HTTPAuthorizationCredentials = Depends(security)):
    data = jwt.decode(token.credentials, JWT_SECRET, algorithms=[ALGO])
    return data["sub"]
```
Trong endpoint:
```python
@app.get("/devices", dependencies=[Depends(require_user)])
```
Nâng cấp thật sự cần:
- Hash mật khẩu (bcrypt / argon2).
- Refresh token + revoke.
- Phân quyền (Role / Permission).
- Rate limit brute-force.

---
## 10. Error Handling
Tự raise lỗi:
```python
from fastapi import HTTPException
raise HTTPException(status_code=404, detail="Not found")
```
Validation error Pydantic tự sinh: HTTP 422.
Custom exception handler:
```python
@app.exception_handler(ValueError)
async def handle_value_error(_, exc: ValueError):
    return JSONResponse(status_code=400, content={"error": str(exc)})
```

---
## 11. CORS Middleware
`main.py`:
```python
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # DEV ONLY
    allow_methods=["*"],
    allow_headers=["*"],
)
```
Prod nên giới hạn origin: `allow_origins=["https://app.example.com"]`.

---
## 12. Background Tasks (Ví dụ)
```python
from fastapi import BackgroundTasks

@app.post("/notify")
async def notify(background: BackgroundTasks):
    background.add_task(send_email, to="user@example.com")
    return {"queued": True}
```
Hàm `send_email` là sync bình thường (FastAPI tự chạy ở threadpool).

---
## 13. WebSocket Cơ Bản
FastAPI hỗ trợ WebSocket:
```python
from fastapi import WebSocket
@app.websocket("/ws")
async def ws_endpoint(ws: WebSocket):
    await ws.accept()
    while True:
        data = await ws.receive_text()
        await ws.send_text(f"Echo: {data}")
```
Dùng cho realtime nếu không muốn dùng MQTT ở trình duyệt.

---
## 14. Pagination & Filtering
Mẫu đơn giản:
```python
@app.get("/telemetry/{device_uid}")
async def telemetry(device_uid: str, page: int = 1, size: int = 50, db: AsyncSession = Depends(get_db)):
    offset = (page - 1) * size
    res = await db.execute(
        select(Telemetry)
        .where(Telemetry.device_uid == device_uid)
        .order_by(Telemetry.id.desc())
        .offset(offset).limit(size)
    )
    return [ ... ]
```
Nên trả thêm meta: `total`, `page`, `size`.

---
## 15. Logging & Cấu Hình
```python
import logging
logger = logging.getLogger("app")
logger.info("Server started")
```
Khuyên dùng `.env` + pydantic Settings:
```python
from pydantic import BaseSettings
class Settings(BaseSettings):
    database_url: str
    jwt_secret: str
    class Config:
        env_file = ".env"
settings = Settings()
```

---
## 16. Testing (pytest + TestClient)
Cài:
```powershell
pip install pytest httpx
```
Test sync cơ bản:
```python
from fastapi.testclient import TestClient
from app.main import app

def test_root():
    client = TestClient(app)
    r = client.get("/")
    assert r.status_code == 200
```
Test async (httpx):
```python
import pytest, httpx
from app.main import app
from fastapi import status

@pytest.mark.asyncio
def test_login():
    async with httpx.AsyncClient(app=app, base_url="http://test") as client:
        r = await client.post("/auth/login", json={"email": "a@b.com", "password": "x"})
        assert r.status_code == status.HTTP_200_OK
```

---
## 17. Tùy Biến Docs
```python
app = FastAPI(title="FastAPI + MQTT + Postgres", description="Demo IoT stack", version="1.0.0")
```
Ẩn route khỏi docs:
```python
@app.get("/internal", include_in_schema=False)
```

---
## 18. Performance Cơ Bản
- Dùng `uvicorn --workers N` với endpoint mostly sync/blocking (cẩn thận state share).
- Tắt debug / reload ở production.
- Kết hợp Redis cache khi truy vấn lặp lại.
- Bật gzip (Reverse proxy Nginx) cho JSON lớn.
- Dùng `orjson` (trong FastAPI: `ORJSONResponse`).

---
## 19. Bảo Mật Cốt Lõi
| Vấn đề | Giải pháp |
|--------|-----------|
| Password lưu thô | Hash bằng bcrypt/argon2 |
| JWT quá dài hạn | Exp ngắn + refresh token |
| Token bị lộ | Cơ chế revoke (danh sách đen) |
| CORS rộng | Giới hạn domain tin cậy |
| DDoS / brute-force | Rate limit + WAF / Cloudflare |
| SQL Injection | Dùng ORM / parameterized queries |
| XSS | Chỉ trả JSON sạch, encode UI phía client |

---
## 20. Docker Hoá Nhanh
`Dockerfile` mẫu:
```dockerfile
FROM python:3.11-slim
WORKDIR /app
COPY backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY backend/app ./app
ENV PYTHONUNBUFFERED=1
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```
Compose: ánh xạ port 8000.

---
## 21. Quản Lý Biến Môi Trường
`.env` ví dụ:
```
DATABASE_URL=postgresql+asyncpg://app:secret@db:5432/app
JWT_SECRET=SuperSecretChangeMe
```
Không commit giá trị bí mật.

---
## 22. Tổ Chức Code Lớn Hơn
Tách router:
```python
from fastapi import APIRouter
router = APIRouter(prefix="/users", tags=["users"])
@router.get("/")
async def list_users(): ...
```
Đăng ký:
```python
app.include_router(router)
```
Tách logic ra `services/user_service.py` tránh endpoint phình to.

---
## 23. Các Lỗi & Pitfall Thường Gặp
| Lỗi | Nguyên nhân | Gợi ý |
|-----|-------------|-------|
| Blocking CPU trong async | Xử lý nặng ngay trong coroutine | Dùng threadpool / Celery / RQ |
| Đóng DB connection | Quên `await db.commit()` hoặc session scope | Dùng `Depends(get_db)` chuẩn |
| 422 khó hiểu | Body không đúng schema | Kiểm tra docs / mẫu JSON gửi |
| CORS fail | Sai origin hoặc thiếu headers | Cấu hình CORSMiddleware chuẩn |
| Token 401 | Expired / ký sai | Kiểm tra `JWT_SECRET`, thời hạn | 

---
## 24. Checklist Cho Newbie
- [ ] Chạy được Hello World.
- [ ] Hiểu `response_model` lọc dữ liệu.
- [ ] Biết dùng `Depends` inject DB session.
- [ ] Tạo 1 model Pydantic mới và test validation.
- [ ] Thêm endpoint yêu cầu JWT.
- [ ] Dùng TestClient viết ít nhất 1 test.
- [ ] Đóng gói Docker chạy lên.
- [ ] Chuyển 1 endpoint sang pagination.

---
## 25. Lộ Trình Học Thêm
1. Alembic migrations.
2. Phân lớp service / repository.
3. OAuth2 / Refresh token / Role-based access.
4. WebSocket / SSE streaming.
5. Rate limiting (SlowAPI) & caching (Redis).
6. Observability (Prometheus metrics + OpenTelemetry tracing).
7. CI/CD: chạy test + build image tự động.

---
## 26. Ví Dụ End-to-End Từ Project
Đăng nhập (mã thật trong `main.py`):
```python
@app.post("/auth/login", response_model=TokenOut)
async def login(body: LoginIn, db: AsyncSession = Depends(get_db)):
    res = await db.execute(select(User).where(User.email == body.email))
    user = res.scalar_one_or_none()
    if not user:
        user = User(email=body.email, password_hash="demo")
        db.add(user)
        await db.commit()
    return TokenOut(access_token=create_token(sub=body.email))
```
Lấy telemetry:
```python
@app.get("/telemetry/{device_uid}", response_model=List[TelemetryOut], dependencies=[Depends(require_user)])
async def get_telemetry(device_uid: str, db: AsyncSession = Depends(get_db)):
    res = await db.execute(
        select(Telemetry)
        .where(Telemetry.device_uid == device_uid)
        .order_by(Telemetry.id.desc())
        .limit(100)
    )
    rows = res.scalars().all()
    return [
        {"device_uid": r.device_uid, "payload": r.payload, "ts": r.ts.isoformat() if r.ts else None}
        for r in rows
    ]
```
Điểm rút ra:
- Sử dụng query builder SQLAlchemy + `await`.
- Trả về list đã map sang schema.
- Bảo vệ route bằng JWT dependency.

---
## 27. Nâng Cấp Tính Năng Telemetry (Gợi Ý)
- Thêm filter theo thời gian: `?from=...&to=...`.
- Thêm sort asc/desc.
- Thêm trường `meta` cho thiết bị (location, version firmware...).
- Dùng WebSocket để stream cập nhật xử lý (nén, tính toán trung bình...).

---
## 28. Tối Ưu Bảo Mật Cho JWT
| Mục | Hiện tại | Nên làm |
|-----|----------|---------|
| Secret | `devsecret` fallback | Dùng biến môi trường mạnh, rotate định kỳ |
| Exp | 60 phút | Thêm refresh token + danh sách thu hồi |
| Password | Lưu chữ "demo" | Hash + salt + upgrade schema |
| Role | Chưa dùng | Thêm RBAC (role -> permissions) |

---
## 29. Tài Nguyên Tham Khảo
- FastAPI Docs: https://fastapi.tiangolo.com/
- SQLAlchemy Async: https://docs.sqlalchemy.org/en/20/orm/extensions/asyncio.html
- Pydantic: https://docs.pydantic.dev/
- JWT (RFC 7519): https://www.rfc-editor.org/rfc/rfc7519
- Alembic: https://alembic.sqlalchemy.org/

---
## 30. Kết Luận
FastAPI giúp bạn viết API sạch, nhanh và có docs ngay lập tức. Hãy bắt đầu từ model –> endpoint –> dependency –> test –> bảo mật –> triển khai Docker. Sau đó mở rộng bằng caching, WebSocket, phân tầng kiến trúc.

Chúc bạn học tốt & xây được API production đầu tiên! 🚀

---
## 31. Lộ Trình / Lịch Phát Triển Chi Tiết
### Thêm: 32. Giao Tiếp FastAPI ↔ MQTT (Publish Command)
Trong project đã có file `mqtt_pub.py` dùng `asyncio-mqtt` để publish lệnh xuống thiết bị. Ta vừa thêm endpoint:
```python
@app.post("/devices/{device_uid}/command", dependencies=[Depends(require_user)])
async def send_command(device_uid: str, body: CommandIn):
    await publish_command(device_uid, {"cmd": body.cmd, "params": body.params})
    return {"status": "sent", "device_uid": device_uid, "cmd": body.cmd}
```
Schema gửi lên (trong `schemas.py`):
```python
class CommandIn(BaseModel):
    cmd: str
    params: Dict[str, Any] | None = None
```
Topic thiết bị phải subscribe: `t0/devices/{uid}/commands`.

Luồng:
1. Client (Flutter / Postman) gọi POST `/devices/dev-01/command` kèm JWT.
2. FastAPI publish MQTT lệnh.
3. Thiết bị nhận và thực thi (ví dụ reboot, đổi interval đo).
4. (Tùy chọn) Thiết bị phản hồi kết quả lên topic khác: `t0/devices/dev-01/command_ack`.

Best practices:
| Mục | Gợi ý |
|-----|-------|
| Xác thực | Endpoint yêu cầu JWT (đã có Dependencies) |
| Kiểm soát lệnh | Danh sách cmd hợp lệ (whitelist) trước khi publish |
| Theo dõi | Lưu lệnh vào bảng `device_commands` (status: sent/ack/failed) |
| Tránh spam | Rate limit gửi lệnh (SlowAPI) |
| Retry | Nếu thiết bị không phản hồi → đẩy lại hoặc đánh dấu timeout |

Ví dụ whitelist đơn giản:
```python
ALLOWED_CMDS = {"reboot", "set_interval"}
if body.cmd not in ALLOWED_CMDS:
    raise HTTPException(status_code=400, detail="Command not allowed")
```

Nếu muốn phản hồi realtime kết quả lệnh cho client HTTP:
- Dùng WebSocket `/ws` để đẩy trạng thái ack.
- Hoặc lưu DB rồi client poll `/commands/{device_uid}`.

Nâng cấp tương lai:
- Thêm correlation id: `cmd_id` để thiết bị trả về mapping kết quả.
- Bảo mật topic commands bằng ACL (chỉ server được publish).
- Chuyển sang shared subscription khi nhiều worker cần xử lý ack.
- Log mọi lệnh để audit (ai gửi, lúc nào, nội dung). 
Mục này giúp bạn có "mục lịch" rõ ràng. Chia theo giai đoạn tăng độ phức tạp. Mỗi block có mục tiêu, hạng mục và ghi chú.

### Giai đoạn 0 – Khởi động (0–0.5 ngày)
| Mục tiêu | Hạng mục | Ghi chú |
|----------|----------|---------|
| Chạy được API cơ bản | Hello World, 1 endpoint GET | `uvicorn --reload` để dev nhanh |
| Tạo schema đơn giản | Pydantic model (LoginIn) | Validate 422 nếu sai |
| JWT tối giản | create_token + require_user | Chưa cần refresh |

### Giai đoạn 1 – Cơ sở dữ liệu (0.5–1 ngày)
| Mục tiêu | Hạng mục | Ghi chú |
|----------|----------|---------|
| Lưu user & telemetry | SQLAlchemy async models | Dùng `async with engine.begin()` tạo bảng |
| Repository tách logic | `user_repository.py` | Tránh query lặp lại trong endpoint |
| Migration | Alembic init | Tạo revision đầu tiên |

### Giai đoạn 2 – Chất lượng & Kiểm thử (1 ngày)
| Mục tiêu | Hạng mục | Ghi chú |
|----------|----------|---------|
| Unit test | pytest + TestClient | Cover login, telemetry fetch |
| Integration test | httpx AsyncClient | Setup DB test riêng (sqlite/memory hoặc container) |
| CI cơ bản | GitHub Actions workflow | Chạy test + lint tự động |

### Giai đoạn 3 – Bảo mật cơ bản (1–2 ngày)
| Mục tiêu | Hạng mục | Ghi chú |
|----------|----------|---------|
| Hash mật khẩu | bcrypt/argon2 | Không lưu plain text |
| Refresh token | /auth/refresh endpoint | Lưu blacklist khi revoke |
| Role/Permission | decorator kiểm tra role | Bảng `user_roles`, `permissions` |
| Rate limit | SlowAPI hoặc custom middleware | Bảo vệ brute-force login |

### Giai đoạn 4 – Tính năng nâng cao (2–4 ngày)
| Mục tiêu | Hạng mục | Ghi chú |
|----------|----------|---------|
| Pagination đầy đủ | Meta: total/pages | Cache trang đầu bằng Redis |
| Filtering linh hoạt | Query params (from,to,sort) | Validate param dạng ISO timestamp |
| WebSocket streaming | `/ws/telemetry` | Gửi data mới hoặc đã xử lý (average) |
| Background tasks | Gửi email, xử lý báo cáo PDF | Sử dụng Celery/RQ nếu queue lớn |

### Giai đoạn 5 – Observability (2 ngày)
| Mục tiêu | Hạng mục | Ghi chú |
|----------|----------|---------|
| Metrics | Prometheus `/metrics` | uvicorn + custom counter |
| Logging chuẩn | Structlog hoặc logging JSON | Dễ parse tập trung |
| Tracing | OpenTelemetry + collector | Trace DB + external calls |
| Healthcheck | `/healthz` đơn giản | Trả DB status, version |

### Giai đoạn 6 – Hiệu năng & Tối ưu (tùy nhu cầu)
| Mục tiêu | Hạng mục | Ghi chú |
|----------|----------|---------|
| Cache | Redis layer | TTL ngắn cho hotspot endpoints |
| Gzip/Compression | Nginx proxy | Không bật với payload nhỏ |
| orjson response | Custom JSONResponse | Nhanh hơn json stdlib |
| Connection pool tuning | SQLAlchemy params | Giảm timeout khi đồng thời cao |

### Giai đoạn 7 – Triển khai Production
| Mục tiêu | Hạng mục | Ghi chú |
|----------|----------|---------|
| Build Docker image | Multi-stage Dockerfile | Giảm kích thước layer |
| Reverse proxy | Nginx config TLS | Thêm HTTP/2 + security headers |
| Env management | `.env` + secrets store | Không commit secrets |
| Auto deploy | CI/CD pipeline | Tag image theo version semver |

### Checklist Tổng Hợp Nhanh
- [ ] Alembic migrations hoạt động
- [ ] JWT + refresh + revoke danh sách
- [ ] Test coverage > 70%
- [ ] Rate limit login
- [ ] WebSocket streaming chạy
- [ ] `/metrics` có số liệu custom
- [ ] Logging JSON
- [ ] Healthcheck OK
- [ ] Docker image nhỏ (<150MB)
- [ ] CI/CD build + test pass trước deploy

### Gợi Ý Ưu Tiên (Khi Ít Thời Gian)
1. Bảo mật cơ bản (hash password) trước.
2. Test login + telemetry (unit/integration).
3. Alembic migrations để tránh mất dữ liệu khi đổi schema.
4. Thêm rate limit để ngăn brute-force.
5. Sau đó mới WebSocket & Observability.

### Sai Lầm Thường Gặp Khi Lên Lịch
| Sai lầm | Hậu quả | Cách tránh |
|---------|---------|-----------|
| Xây nhiều tính năng trước bảo mật | Lộ dữ liệu, khó retrofit | Chốt auth + hash sớm |
| Không có migration | Mất dữ liệu khi đổi cột | Dùng Alembic ngay từ đầu |
| Thiếu test trước refactor | Gãy tính năng âm thầm | Viết test nhỏ ngay khi thêm endpoint |
| Bật reload ở prod | Performance kém, nhiều process | Tắt `--reload` ở môi trường production |
| Không giám sát | Khó debug lỗi runtime | Thêm log + metrics tối thiểu |

### Lộ Trình Dài Hạn (Sau 1–3 Tháng)
- Tách microservices (auth riêng, telemetry xử lý riêng)
- Thêm GraphQL gateway nếu cần query linh hoạt
- Sử dụng gRPC giữa services nội bộ
- Feature flag / canary deploy
- Chaos testing (mô phỏng lỗi ngẫu nhiên)

---
> Có thể copy bảng này thành file riêng `ROADMAP_FASTAPI.md` nếu muốn quản lý version.
