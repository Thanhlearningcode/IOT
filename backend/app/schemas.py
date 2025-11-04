from pydantic import BaseModel, EmailStr
from typing import Any, Dict

class LoginIn(BaseModel):
    email: EmailStr
    password: str

class TokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"

class TelemetryOut(BaseModel):
    device_uid: str
    payload: Dict[str, Any]
    ts: str | None

class CommandIn(BaseModel):
        """Payload gửi lệnh xuống thiết bị qua MQTT.

        Ví dụ:
        {
            "cmd": "reboot",
            "params": {"delay": 5}
        }
        """
        cmd: str
        params: Dict[str, Any] | None = None

class DeviceRegisterIn(BaseModel):
    device_uid: str
    name: str | None = None

class TelemetryIn(BaseModel):
    msg_id: str | None = None
    payload: Dict[str, Any]

class CommandQueueOut(BaseModel):
    id: int
    cmd: str
    params: Dict[str, Any] | None = None
    status: str
    created_at: str | None = None

class FirmwareCheckOut(BaseModel):
    update_available: bool
    current_version: str
    latest_version: str
    url: str | None = None
