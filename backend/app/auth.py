from fastapi import HTTPException, Depends
from jose import jwt
from datetime import datetime, timedelta
import os

JWT_SECRET = os.getenv("JWT_SECRET", "devsecret")
ALGO = "HS256"

def create_token(sub: str, minutes: int = 60):
    now = datetime.utcnow()
    payload = {"sub": sub, "iat": now, "exp": now + timedelta(minutes=minutes)}
    return jwt.encode(payload, JWT_SECRET, algorithm=ALGO)

from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
security = HTTPBearer()

def require_user(token: HTTPAuthorizationCredentials = Depends(security)):
    try:
        data = jwt.decode(token.credentials, JWT_SECRET, algorithms=[ALGO])
        return data["sub"]
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid token")
