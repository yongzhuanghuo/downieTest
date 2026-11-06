"""授权相关 ORM 模型。

字段与 `sql/schema.sql` 严格一致（表结构不动）。
注意 expire_at 是 BIGINT 存 epoch 毫秒时间戳（前端 new Date(expire_at) 依赖这个语义），
不要改成 DATETIME。
"""
from datetime import datetime

from sqlalchemy import BigInteger, DateTime, Enum, Index, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base


class Product(Base):
    __tablename__ = "products"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    code: Mapped[str] = mapped_column(String(32), nullable=False, unique=True)
    name: Mapped[str] = mapped_column(String(64), nullable=False)
    trial_days: Mapped[int] = mapped_column(Integer, nullable=False, default=14)
    default_max_devices: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    purchase_url: Mapped[str] = mapped_column(String(512), nullable=False, default="")
    support_email: Mapped[str] = mapped_column(String(255), nullable=False, default="")
    status: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, server_default="CURRENT_TIMESTAMP")


class License(Base):
    __tablename__ = "licenses"
    __table_args__ = (Index("idx_licenses_product_status", "product_id", "status"),)

    code: Mapped[str] = mapped_column(String(20), primary_key=True)
    product_id: Mapped[int] = mapped_column(BigInteger, nullable=False, default=1, server_default="1")
    type: Mapped[str] = mapped_column(Enum("free", "perpetual"), nullable=False, default="perpetual")
    max_devices: Mapped[int] = mapped_column(Integer, nullable=False, default=4)
    email: Mapped[str | None] = mapped_column(String(255), nullable=True)
    expire_at: Mapped[int | None] = mapped_column(BigInteger, nullable=True)
    status: Mapped[str] = mapped_column(Enum("unused", "activated", "revoked"), nullable=False, default="unused")
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, server_default="CURRENT_TIMESTAMP")


class DeviceBinding(Base):
    __tablename__ = "device_bindings"
    __table_args__ = (
        UniqueConstraint("code", "device_fp", name="uq_code_fp"),
        Index("idx_code_status", "code", "status"),
        Index("idx_dev_product_fp", "product_id", "device_fp"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    code: Mapped[str] = mapped_column(String(20), nullable=False)
    product_id: Mapped[int] = mapped_column(BigInteger, nullable=False, default=1, server_default="1")
    device_fp: Mapped[str] = mapped_column(String(64), nullable=False)
    device_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    bound_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, server_default="CURRENT_TIMESTAMP")
    last_seen: Mapped[datetime] = mapped_column(DateTime, nullable=False, server_default="CURRENT_TIMESTAMP")
    status: Mapped[str] = mapped_column(Enum("active", "unbound"), nullable=False, default="active")


class TrialDevice(Base):
    __tablename__ = "trial_devices"

    device_fp: Mapped[str] = mapped_column(String(64), primary_key=True)
    device_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    platform: Mapped[str | None] = mapped_column(String(20), nullable=True)
    first_seen: Mapped[datetime] = mapped_column(DateTime, nullable=False, server_default="CURRENT_TIMESTAMP")
    trial_start: Mapped[datetime] = mapped_column(DateTime, nullable=False, server_default="CURRENT_TIMESTAMP")
    trial_end: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    email: Mapped[str | None] = mapped_column(String(255), nullable=True)
    status: Mapped[str] = mapped_column(
        Enum("active", "expired", "converted", "revoked"),
        nullable=False,
        default="active",
    )
    last_seen: Mapped[datetime] = mapped_column(DateTime, nullable=False, server_default="CURRENT_TIMESTAMP")


class UnbindLog(Base):
    __tablename__ = "unbind_log"
    __table_args__ = (Index("idx_code_time", "code", "unbound_at"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    code: Mapped[str] = mapped_column(String(20), nullable=False)
    device_fp: Mapped[str] = mapped_column(String(64), nullable=False)
    device_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    unbound_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, server_default="CURRENT_TIMESTAMP")
    reason: Mapped[str] = mapped_column(String(50), nullable=False, default="user_manual")


class Trial(Base):
    __tablename__ = "trials"
    __table_args__ = (
        UniqueConstraint("product_id", "device_fp", name="uq_trial_product_device"),
        Index("idx_trial_product_status_end", "product_id", "status", "trial_end"),
    )

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    product_id: Mapped[int] = mapped_column(BigInteger, nullable=False)
    device_fp: Mapped[str] = mapped_column(String(64), nullable=False)
    device_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    platform: Mapped[str | None] = mapped_column(String(20), nullable=True)
    first_seen: Mapped[datetime] = mapped_column(DateTime, nullable=False, server_default="CURRENT_TIMESTAMP")
    trial_start: Mapped[datetime] = mapped_column(DateTime, nullable=False, server_default="CURRENT_TIMESTAMP")
    trial_end: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    email: Mapped[str | None] = mapped_column(String(255), nullable=True)
    status: Mapped[str] = mapped_column(
        Enum("active", "expired", "converted", "revoked"),
        nullable=False,
        default="active",
    )
    last_seen: Mapped[datetime] = mapped_column(DateTime, nullable=False, server_default="CURRENT_TIMESTAMP")


class Release(Base):
    __tablename__ = "releases"
    __table_args__ = (
        UniqueConstraint("product_id", "platform", "build", name="uq_release_build"),
        Index("idx_release_latest", "product_id", "platform", "status", "build"),
    )

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    product_id: Mapped[int] = mapped_column(BigInteger, nullable=False)
    platform: Mapped[str] = mapped_column(String(20), nullable=False, default="macos")
    version: Mapped[str] = mapped_column(String(32), nullable=False)
    build: Mapped[int] = mapped_column(Integer, nullable=False)
    artifact_url: Mapped[str] = mapped_column(String(1024), nullable=False)
    artifact_sha256: Mapped[str] = mapped_column(String(64), nullable=False, default="")
    artifact_size: Mapped[int] = mapped_column(BigInteger, nullable=False, default=0)
    dmg_url: Mapped[str | None] = mapped_column(String(1024), nullable=True)
    changelog: Mapped[str | None] = mapped_column(Text, nullable=True)
    force_update: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    status: Mapped[str] = mapped_column(Enum("draft", "published", "revoked"), nullable=False, default="published")
    published_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, server_default="CURRENT_TIMESTAMP")
