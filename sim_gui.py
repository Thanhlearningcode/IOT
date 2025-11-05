"""Simple GUI publisher for manual telemetry injection.

Usage:
    python3 sim_gui.py
Enter temperature value and click Publish.
Publishes JSON to topic: t0/devices/dev-gui-01/telemetry

No registration or secret needed (MQTT only path). Ingestor will persist.
"""
import sys

if sys.version_info < (3, 7):
        raise SystemExit("sim_gui.py requires Python 3.7+. Please run with `python3 sim_gui.py`.")

import json, time, random
import tkinter as tk
from tkinter import ttk
from paho.mqtt import client as mqtt

BROKER_HOST = 'localhost'
BROKER_PORT = 1883
TENANT = 't0'
DEVICE_UID = 'dev-gui-01'
TOPIC = f'{TENANT}/devices/{DEVICE_UID}/telemetry'

client = mqtt.Client()
msg_counter = 0
status_var = None  # sẽ khởi tạo sau khi tạo root

def connect():
    if status_var is None:
        return
    try:
        client.connect(BROKER_HOST, BROKER_PORT, 60)
        client.loop_start()
        status_var.set('Connected')
    except Exception as e:
        status_var.set(f'Connect error: {e}')


def publish(temp_val: float, led_state: bool):
    if status_var is None:
        return
    global msg_counter
    payload = {
        'msg_id': f'gui-{msg_counter:05d}',
        'ts': int(time.time()),
        'data': {
            'temp_c': temp_val,
            'led': led_state,
            'rand': round(random.random(), 3)
        }
    }
    msg_counter += 1
    try:
        client.publish(TOPIC, json.dumps(payload), qos=1)
        status_var.set(f'Published {payload["msg_id"]}')
    except Exception as e:
        status_var.set(f'Publish error: {e}')


def main():
    global status_var
    root = tk.Tk()
    root.title('Telemetry GUI Publisher')
    status_var = tk.StringVar(root, value='Disconnected')

    frame = ttk.Frame(root, padding=16)
    frame.pack(fill='both', expand=True)

    ttk.Label(frame, text=f'Topic: {TOPIC}').pack(anchor='w')
    status_label = ttk.Label(frame, textvariable=status_var, foreground='blue')
    status_label.pack(anchor='w', pady=(0,10))

    temp_var = tk.DoubleVar(value=25.0)
    led_var = tk.BooleanVar(value=False)

    temp_row = ttk.Frame(frame)
    temp_row.pack(fill='x', pady=4)
    ttk.Label(temp_row, text='Temperature (°C):').pack(side='left')
    ttk.Entry(temp_row, textvariable=temp_var, width=10).pack(side='left', padx=8)

    led_row = ttk.Frame(frame)
    led_row.pack(fill='x', pady=4)
    ttk.Checkbutton(led_row, text='LED ON', variable=led_var).pack(side='left')

    btn_row = ttk.Frame(frame)
    btn_row.pack(fill='x', pady=12)
    ttk.Button(btn_row, text='Connect MQTT', command=connect).pack(side='left')
    ttk.Button(btn_row, text='Publish', command=lambda: publish(temp_var.get(), led_var.get())).pack(side='left', padx=8)

    root.mainloop()

if __name__ == '__main__':
    main()
