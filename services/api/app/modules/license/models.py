"""授权相关 ORM 模型。

字段与 `sql/schema.sql` 严格一致（表结构不动）。
注意 expire_at 是 BIGINT 存 epoch 毫秒时间戳（前端 new Date(expire_at) 依赖这个语义），
不要改成 DATETIME。
"""
from datetime import datetime

from sqlalchemy import BigInteger, DateTime, Enum, Index, Integer, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base


class License(Base):
    __tablename__ = "licenses"

    code: Mapped[str] = mapped_column(String(20), primary_key=True)
    type: Mapped[str] = mapped_column(Enum("free", "perpetual"), nullable=False, default="perpetual")
    max_devices: Mapped[int] = mapped_column(Integer, nullable=False, default=4)
    expire_at: Mapped[int | None] = mapped_column(BigInteger, nullable=True)
    status: Mapped[str] = mapped_column(Enum("unused", "activated", "revoked"), nullable=False, default="unused")
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, server_default="CURRENT_TIMESTAMP")


class DeviceBinding(Base):
    __tablename__ = "device_bindings"
    __table_args__ = (
        UniqueConstraint("code", "device_fp", name="uq_code_fp"),
        Index("idx_code_status", "code", "status"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    code: Mapped[str] = mapped_column(String(20), nullable=False)
    device_fp: Mapped[str] = mapped_column(String(64), nullable=False)
    device_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    bound_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, server_default="CURRENT_TIMESTAMP")
    last_seen: Mapped[datetime] = mapped_column(DateTime, nullable=False, server_default="CURRENT_TIMESTAMP")
    status: Mapped[str] = mapped_column(Enum("active", "unbound"), nullable=False, default="active")


class UnbindLog(Base):
    __tablename__ = "unbind_log"
    __table_args__ = (Index("idx_code_time", "code", "unbound_at"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    code: Mapped[str] = mapped_column(String(20), nullable=False)
    device_fp: Mapped[str] = mapped_column(String(64), nullable=False)
    device_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    unbound_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, server_default="CURRENT_TIMESTAMP")
    reason: Mapped[str] = mapped_column(String(50), nullable=False, default="user_manual")
