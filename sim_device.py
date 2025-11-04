import json, time, random
from paho.mqtt import client as mqtt

BROKER_HOST = 'localhost'  # nếu chạy trên máy khác: đổi sang IP LAN của host
BROKER_PORT = 1883
uid = 'dev-01'

c = mqtt.Client()
c.connect(BROKER_HOST, BROKER_PORT, 60)

# publish status retained (để app thấy ngay khi subscribe)
c.publish(f't0/devices/{uid}/status', json.dumps({'online': True, 'ts': int(time.time())}), qos=1, retain=True)

for i in range(20):
    payload = {
        'msg_id': f'{i:04d}',
        'ts': int(time.time()),
        'data': { 'temp': round(20 + random.random()*5, 2) }
    }
    c.publish(f't0/devices/{uid}/telemetry', json.dumps(payload), qos=1)
    time.sleep(1)
