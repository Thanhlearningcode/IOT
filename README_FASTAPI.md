# Hướng Dẫn FastAPI Toàn Tập Cho Newbie (Dựa trên project hiện tại)

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
