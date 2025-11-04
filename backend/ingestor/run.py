import os, json, uuid, asyncio
from asyncio_mqtt import Client, MqttError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.db import SessionLocal
from app.models import Telemetry, Device

MQTT_HOST = os.getenv("MQTT__HOST", "emqx")
MQTT_PORT = int(os.getenv("MQTT__PORT", "1883"))
TOPIC = os.getenv("MQTT__TOPIC", "t0/devices/+/telemetry")

async def ensure_device(db: AsyncSession, device_uid: str):
    res = await db.execute(select(Device).where(Device.device_uid == device_uid))
    d = res.scalar_one_or_none()
    if not d:
        db.add(Device(device_uid=device_uid, name=device_uid))
        await db.commit()

async def handle_message(topic: str, payload: bytes):
    parts = topic.split("/")  # t0 devices {uid} telemetry
    # defensive check
    if len(parts) < 4:
        return
    device_uid = parts[2]
    try:
        body = json.loads(payload.decode())
    except Exception:
        body = {"raw": payload.decode(errors="ignore")}
    msg_id = body.get("msg_id") or str(uuid.uuid4())

    async with SessionLocal() as db:
        await ensure_device(db, device_uid)
        db.add(Telemetry(device_uid=device_uid, msg_id=msg_id, payload=body))
        try:
            await db.commit()
        except Exception:
            await db.rollback()  # duplicate? bỏ qua trong demo

async def main():
    reconnect_delay = 3
    while True:
        try:
            async with Client(MQTT_HOST, MQTT_PORT) as client:
                await client.subscribe(TOPIC, qos=1)
                async with client.unfiltered_messages() as messages:
                    async for m in messages:
                        await handle_message(m.topic, m.payload)
        except MqttError:
            await asyncio.sleep(reconnect_delay)

if __name__ == "__main__":
    asyncio.run(main())
