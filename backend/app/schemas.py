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
