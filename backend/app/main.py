from fastapi import FastAPI, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from .db import Base, engine, get_db
from .models import User, Device, Telemetry
from .schemas import LoginIn, TokenOut, TelemetryOut, CommandIn
from .mqtt_pub import publish_command
from .auth import create_token, require_user
from typing import List

from fastapi.middleware.cors import CORSMiddleware

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
