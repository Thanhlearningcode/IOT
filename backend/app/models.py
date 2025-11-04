from sqlalchemy import Column, BigInteger, String, Text, JSON, UniqueConstraint, ForeignKey, DateTime
from sqlalchemy.sql import func
from .db import Base

class User(Base):
    __tablename__ = "users"
    id = Column(BigInteger, primary_key=True)
    email = Column(String, unique=True, nullable=False)
    password_hash = Column(Text, nullable=False)
    role = Column(String, default="user")
    created_at = Column(DateTime(timezone=True), server_default=func.now())

class Device(Base):
    __tablename__ = "devices"
    id = Column(BigInteger, primary_key=True)
    device_uid = Column(String, unique=True, nullable=False)
    name = Column(String)
    tenant = Column(String, default="t0")
    created_at = Column(DateTime(timezone=True), server_default=func.now())

class Telemetry(Base):
    __tablename__ = "telemetry"
    id = Column(BigInteger, primary_key=True)
    device_uid = Column(String, ForeignKey("devices.device_uid"), nullable=False)
    msg_id = Column(String, nullable=False)  # string để chấp nhận cả '0001' lẫn uuid
    payload = Column(JSON, nullable=False)
    ts = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    __table_args__ = (UniqueConstraint("device_uid", "msg_id", name="uq_device_msg"),)
