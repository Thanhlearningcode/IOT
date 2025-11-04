from fastapi import FastAPI, Depends, HTTPException, Header
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from .db import Base, engine, get_db
from .models import User, Device, Telemetry, CommandQueue
from .schemas import (
    LoginIn, TokenOut, TelemetryOut, CommandIn,
    DeviceRegisterIn, TelemetryIn, CommandQueueOut, FirmwareCheckOut
)
from .mqtt_pub import publish_command
from .auth import create_token, require_user
from typing import List

from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text

app = FastAPI(title="FastAPI + MQTT + Postgres")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # DEV ONLY: mở CORS để Flutter Web gọi đc
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.on_event("startup")
async def on_startup():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        # Đảm bảo cột device_secret tồn tại (thêm sau) – tránh lỗi UndefinedColumn
        try:
            await conn.execute(text("ALTER TABLE devices ADD COLUMN IF NOT EXISTS device_secret VARCHAR"))
        except Exception:
            pass

@app.post("/auth/login", response_model=TokenOut)
async def login(body: LoginIn, db: AsyncSession = Depends(get_db)):
    # DEMO: chấp nhận mọi email/pass, tạo user nếu chưa có
    res = await db.execute(select(User).where(User.email == body.email))
    user = res.scalar_one_or_none()
    if not user:
        user = User(email=body.email, password_hash="demo")
        db.add(user)
        await db.commit()
    return TokenOut(access_token=create_token(sub=body.email))

@app.get("/devices", dependencies=[Depends(require_user)])
async def list_devices(db: AsyncSession = Depends(get_db)):
    res = await db.execute(select(Device))
    return [
        {"device_uid": d.device_uid, "name": d.name, "tenant": d.tenant}
        for d in res.scalars().all()
    ]

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

@app.post("/devices/{device_uid}/command", dependencies=[Depends(require_user)])
async def send_command(device_uid: str, body: CommandIn):
        """Gửi lệnh xuống thiết bị qua MQTT.

        Body ví dụ:
        {
            "cmd": "reboot",
            "params": {"delay": 5}
        }

        Trả về trạng thái gửi. Thiết bị cần subscribe topic:
        t0/devices/{device_uid}/commands
        """
        await publish_command(device_uid, {"cmd": body.cmd, "params": body.params})
        return {"status": "sent", "device_uid": device_uid, "cmd": body.cmd}

# --- ESP32 oriented HTTP endpoints (demo) ---

@app.post("/devices/register", response_model=TokenOut)
async def register_device(body: DeviceRegisterIn, db: AsyncSession = Depends(get_db)):
    """Đăng ký thiết bị và trả về một token (dùng tạm làm secret).

    Thiết bị sẽ gửi token này sau đó ở header `X-Device-Secret`.
    Prod: nên tạo bảng riêng hoặc ký JWT với scope device.
    """
    res = await db.execute(select(Device).where(Device.device_uid == body.device_uid))
    d = res.scalar_one_or_none()
    if not d:
        # tạo secret đơn giản: reversed uid; có thể thay bằng uuid4
        secret = body.device_uid[::-1]
        d = Device(device_uid=body.device_uid, name=body.name or body.device_uid, device_secret=secret)
        db.add(d)
        await db.commit()
    else:
        secret = d.device_secret or d.device_uid[::-1]
        if not d.device_secret:
            d.device_secret = secret
            await db.commit()
    # dùng secret làm sub trong token để đơn giản
    return TokenOut(access_token=create_token(sub=secret))

async def _device_from_secret(db: AsyncSession, secret: str) -> Device | None:
    if not secret:
        return None
    res = await db.execute(select(Device).where(Device.device_secret == secret))
    return res.scalar_one_or_none()

def _device_secret_header(secret: str | None):
    if not secret:
        raise HTTPException(status_code=401, detail="Missing X-Device-Secret")
    return secret

@app.post("/devices/{device_uid}/telemetry", response_model=dict)
async def ingest_telemetry_http(device_uid: str, body: TelemetryIn, db: AsyncSession = Depends(get_db), secret: str = Header(None, alias="X-Device-Secret")):
    """Thiết bị gửi telemetry qua HTTP (fallback khi không dùng MQTT).

    Header yêu cầu: `X-Device-Secret: <secret>` (hiện tại token đơn giản).
    """
    secret = _device_secret_header(secret)
    # resolve secret to device
    device = await _device_from_secret(db, secret)
    if not device or device.device_uid != device_uid:
        raise HTTPException(status_code=403, detail="Invalid device secret")
    msg_id = body.msg_id or "http-" + device_uid
    row = Telemetry(device_uid=device_uid, msg_id=msg_id, payload=body.payload)
    db.add(row)
    try:
        await db.commit()
    except Exception:
        await db.rollback()  # duplicate
        return {"status": "duplicate", "msg_id": msg_id}
    return {"status": "ok", "msg_id": msg_id}

@app.post("/devices/{device_uid}/command/store", response_model=CommandQueueOut, dependencies=[Depends(require_user)])
async def queue_command(device_uid: str, body: CommandIn, db: AsyncSession = Depends(get_db)):
    """Lưu command vào hàng đợi (ngoài việc publish)."""
    cq = CommandQueue(device_uid=device_uid, cmd=body.cmd, params=body.params, status="pending")
    db.add(cq)
    await db.commit()
    await publish_command(device_uid, {"cmd": body.cmd, "params": body.params})
    cq.status = "sent"
    await db.commit()
    return CommandQueueOut(id=cq.id, cmd=cq.cmd, params=cq.params, status=cq.status, created_at=cq.created_at.isoformat() if cq.created_at else None)

@app.get("/devices/{device_uid}/commands/poll", response_model=list)
async def poll_commands(device_uid: str, db: AsyncSession = Depends(get_db), secret: str = Header(None, alias="X-Device-Secret")):
    """Thiết bị HTTP polling lấy command chưa ack.

    Header: X-Device-Secret
    """
    secret = _device_secret_header(secret)
    device = await _device_from_secret(db, secret)
    if not device or device.device_uid != device_uid:
        raise HTTPException(status_code=403, detail="Invalid device secret")
    res = await db.execute(select(CommandQueue).where(CommandQueue.device_uid == device_uid, CommandQueue.status == "sent"))
    rows = res.scalars().all()
    return [
        {"id": r.id, "cmd": r.cmd, "params": r.params, "status": r.status, "created_at": r.created_at.isoformat() if r.created_at else None}
        for r in rows
    ]

@app.post("/devices/{device_uid}/commands/{command_id}/ack", response_model=dict)
async def ack_command(device_uid: str, command_id: int, db: AsyncSession = Depends(get_db), secret: str = Header(None, alias="X-Device-Secret")):
    secret = _device_secret_header(secret)
    device = await _device_from_secret(db, secret)
    if not device or device.device_uid != device_uid:
        raise HTTPException(status_code=403, detail="Invalid device secret")
    res = await db.execute(select(CommandQueue).where(CommandQueue.id == command_id, CommandQueue.device_uid == device_uid))
    cq = res.scalar_one_or_none()
    if not cq:
        raise HTTPException(status_code=404, detail="Command not found")
    cq.status = "acked"
    await db.commit()
    return {"status": "acked", "id": cq.id}

@app.get("/devices/{device_uid}/firmware/check", response_model=FirmwareCheckOut)
async def firmware_check(device_uid: str, version: str, db: AsyncSession = Depends(get_db)):
    """Demo endpoint: luôn trả về latest giả lập nếu version khác.
    Prod: truy vấn bảng firmware.
    """
    latest = "1.0.0"
    if version != latest:
        return FirmwareCheckOut(update_available=True, current_version=version, latest_version=latest, url=f"https://example.com/fw/{device_uid}/{latest}.bin")
    return FirmwareCheckOut(update_available=False, current_version=version, latest_version=latest, url=None)
