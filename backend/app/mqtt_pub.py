import os, json
from asyncio_mqtt import Client

MQTT_HOST = os.getenv("MQTT__HOST", "emqx")
MQTT_PORT = int(os.getenv("MQTT__PORT", "1883"))

async def publish_command(device_uid: str, payload: dict):
    topic = f"t0/devices/{device_uid}/commands"
    async with Client(MQTT_HOST, MQTT_PORT) as client:
        await client.publish(topic, json.dumps(payload), qos=1)
