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
