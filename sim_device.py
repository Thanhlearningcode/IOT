"""ESP32-like simulator.

Nâng cấp từ script ban đầu để mô phỏng thiết bị thật:
1. Đăng ký device qua HTTP để lấy secret (demo: secret = reversed uid).
2. Gửi telemetry đều đặn qua MQTT (có msg_id)
3. Publish retained status.
4. Subscribe commands topic và thực thi lệnh (led_on/led_off/reboot giả lập).
5. Poll hàng đợi command (HTTP) và ack sau khi xử lý.
6. (Tuỳ chọn) Fallback gửi telemetry qua HTTP nếu MQTT mất kết nối.

Yêu cầu thư viện: paho-mqtt, requests
pip install paho-mqtt requests
"""

import json, time, random, threading, requests, sys
from paho.mqtt import client as mqtt

# --- CONFIG ---
BROKER_HOST = 'localhost'        # Đổi sang IP host nếu chạy từ thiết bị ngoài
BROKER_PORT = 1883
API_BASE = 'http://localhost:8000'
DEVICE_UID = 'dev-01'
TENANT = 't0'
MQTT_TELEMETRY_INTERVAL = 2      # giây
COMMAND_POLL_INTERVAL = 5        # giây
USE_HTTP_FALLBACK = False        # True: gửi cả HTTP telemetry khi MQTT lỗi

LED_STATE = False
DEVICE_SECRET = None
STOP = False

# --- HTTP helper ---
def http_post(path, json_body, headers=None):
    url = API_BASE + path
    try:
        r = requests.post(url, json=json_body, headers=headers, timeout=5)
        r.raise_for_status()
        return r.json()
    except Exception as e:
        print('[HTTP] POST error', path, e)
        return None

def http_get(path, headers=None, params=None):
    url = API_BASE + path
    try:
        r = requests.get(url, headers=headers, params=params, timeout=5)
        r.raise_for_status()
        return r.json()
    except Exception as e:
        print('[HTTP] GET error', path, e)
        return None

def register_device():
    global DEVICE_SECRET
    print('[REG] registering device', DEVICE_UID)
    data = {'device_uid': DEVICE_UID, 'name': DEVICE_UID}
    resp = http_post('/devices/register', data)
    if not resp:
        print('[REG] failed')
        return False
    # secret demo = reversed uid (server dùng vậy) -> hoặc decode JWT.
    DEVICE_SECRET = DEVICE_UID[::-1]
    print('[REG] got secret (demo):', DEVICE_SECRET)
    return True

def ack_command(command_id):
    headers = {'X-Device-Secret': DEVICE_SECRET}
    resp = http_post(f'/devices/{DEVICE_UID}/commands/{command_id}/ack', {}, headers)
    if resp:
        print(f'[CMD] acked id={command_id}')

def poll_commands():
    if not DEVICE_SECRET:
        return
    headers = {'X-Device-Secret': DEVICE_SECRET}
    rows = http_get(f'/devices/{DEVICE_UID}/commands/poll', headers) or []
    for row in rows:
        cid = row.get('id')
        cmd = row.get('cmd')
        params = row.get('params') or {}
        handle_local_command(cmd, params, source=f'queue:{cid}')
        ack_command(cid)

def handle_local_command(cmd, params, source='mqtt'):  # giả lập thực thi lệnh
    global LED_STATE
    if cmd == 'led_on':
        LED_STATE = True
    elif cmd == 'led_off':
        LED_STATE = False
    elif cmd == 'reboot':
        print('[CMD] reboot simulated (sleep 2s)')
        time.sleep(2)
    print(f'[CMD] handled cmd={cmd} from={source} LED={LED_STATE}')

# --- MQTT ---
client = mqtt.Client()

def on_connect(c, userdata, flags, rc):
    if rc == 0:
        print('[MQTT] connected')
        commands_topic = f'{TENANT}/devices/{DEVICE_UID}/commands'
        c.subscribe(commands_topic, qos=1)
        print('[MQTT] subscribed', commands_topic)
        # publish retained status
        c.publish(f'{TENANT}/devices/{DEVICE_UID}/status', json.dumps({'online': True, 'ts': int(time.time())}), qos=1, retain=True)
    else:
        print('[MQTT] connect failed rc', rc)

def on_message(c, userdata, msg):
    try:
        body = json.loads(msg.payload.decode())
    except Exception:
        body = {'raw': msg.payload.decode(errors='ignore')}
    cmd = body.get('cmd')
    params = body.get('params') or {}
    if cmd:
        handle_local_command(cmd, params, source='mqtt')

client.on_connect = on_connect
client.on_message = on_message

def mqtt_connect_loop():
    while not STOP:
        try:
            client.connect(BROKER_HOST, BROKER_PORT, 60)
            client.loop_start()
            break
        except Exception as e:
            print('[MQTT] connect error, retrying in 3s', e)
            time.sleep(3)

def publish_telemetry(counter):
    payload = {
        'msg_id': f'{counter:04d}',
        'ts': int(time.time()),
        'data': {
            'temp_c': round(24 + random.random()*3, 2),
            'led': LED_STATE,
        }
    }
    topic = f'{TENANT}/devices/{DEVICE_UID}/telemetry'
    try:
        client.publish(topic, json.dumps(payload), qos=1)
        print('[TEL] sent', payload)
    except Exception as e:
        print('[TEL] mqtt publish failed', e)
        if USE_HTTP_FALLBACK and DEVICE_SECRET:
            headers = {'X-Device-Secret': DEVICE_SECRET}
            http_post(f'/devices/{DEVICE_UID}/telemetry', {'msg_id': payload['msg_id'], 'payload': payload['data']}, headers)

def telemetry_loop():
    i = 0
    while not STOP:
        publish_telemetry(i)
        i += 1
        time.sleep(MQTT_TELEMETRY_INTERVAL)

def command_poll_loop():
    while not STOP:
        poll_commands()
        time.sleep(COMMAND_POLL_INTERVAL)

def main():
    if not register_device():
        sys.exit(1)
    mqtt_connect_loop()
    threading.Thread(target=telemetry_loop, daemon=True).start()
    threading.Thread(target=command_poll_loop, daemon=True).start()
    print('[MAIN] simulator running. Press Ctrl+C to stop.')
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print('[MAIN] stopping...')
    finally:
        global STOP
        STOP = True
        client.loop_stop()
        client.disconnect()

if __name__ == '__main__':
    main()
