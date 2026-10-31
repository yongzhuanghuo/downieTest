"""授权业务逻辑（移植自 Node 版 src/routes/license.js）。

契约严格对齐：路径、字段名、错误码、HTTP 状态码都保持不变。
关键移植点：
  - SELECT ... FOR UPDATE 防超绑（必须与写操作在同一事务、同一连接上）
  - ON DUPLICATE KEY UPDATE 复用解绑后的旧行，避免唯一键冲突
"""
import math
import re
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any

from sqlalchemy import func, select, text, update
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.dialects.mysql import insert as mysql_insert

from .codes import normalize_code
from .models import DeviceBinding, License, TrialDevice, UnbindLog

TRIAL_DAYS = 14


class LicenseError(Exception):
    """带 HTTP 状态码的业务错误，router 层统一转成对应响应。"""

    def __init__(self, status: int, error: str, message: str = "", extra: dict | None = None):
        super().__init__(message or error)
        self.status = status
        self.error = error
        self.message = message
        self.extra = extra or {}


async def _get_license(session: AsyncSession, code: str) -> License | None:
    return await session.scalar(select(License).where(License.code == code))


def _license_payload(lic: License) -> dict:
    return {"type": lic.type, "max_devices": lic.max_devices, "expire_at": lic.expire_at}


def _device_dict(d: DeviceBinding) -> dict:
    return {
        "id": d.id,
        "code": d.code,
        "device_fp": d.device_fp,
        "device_name": d.device_name,
        "bound_at": d.bound_at.isoformat() if d.bound_at else None,
        "last_seen": d.last_seen.isoformat() if d.last_seen else None,
        "status": d.status,
    }


def _to_epoch_ms(value: datetime) -> int:
    # DB 里是 naive UTC；按 UTC 解释，避免服务器本地时区影响
    return int(value.replace(tzinfo=timezone.utc).timestamp() * 1000)


def _trial_payload(row: TrialDevice, now: datetime) -> dict[str, Any]:
    active = row.status == "active" and row.trial_end > now
    seconds = max(0.0, (row.trial_end - now).total_seconds())
    # 防止 MySQL DATETIME 秒级精度把 13d23h59m59.9s 向上取整成 15 天
    days = min(TRIAL_DAYS, max(0, math.ceil(seconds / 86400.0))) if active else 0
    return {
        "ok": True,
        "trial": {
            "status": "active" if active else row.status,
            "trial_end": _to_epoch_ms(row.trial_end),
            "days_remaining": days,
        },
        "can_download": active,
    }


async def start_trial(
    session: AsyncSession,
    device_fp: str,
    device_name: str | None = None,
    platform: str | None = None,
    email: str | None = None,
) -> dict[str, Any]:
    if not device_fp:
        raise LicenseError(400, "MISSING_PARAMS")
    now = datetime.utcnow().replace(microsecond=0)
    async with session.begin():
        row = await session.get(TrialDevice, device_fp)
        if row is None:
            row = TrialDevice(
                device_fp=device_fp,
                device_name=device_name,
                platform=platform,
                first_seen=now,
                trial_start=now,
                trial_end=now + timedelta(days=TRIAL_DAYS),
                email=email,
                status="active",
                last_seen=now,
            )
            session.add(row)
        else:
            row.last_seen = now
            if device_name:
                row.device_name = device_name
            if platform:
                row.platform = platform
            if email:
                row.email = email
            if row.status == "active" and row.trial_end <= now:
                row.status = "expired"
        payload = _trial_payload(row, now)
    return payload


async def trial_status(session: AsyncSession, device_fp: str) -> dict[str, Any]:
    if not device_fp:
        raise LicenseError(400, "MISSING_PARAMS")
    row = await session.get(TrialDevice, device_fp)
    if row is None:
        return {"ok": True, "trial": None, "can_download": False}
    now = datetime.utcnow().replace(microsecond=0)
    if row.status == "active" and row.trial_end <= now:
        row.status = "expired"
    payload = _trial_payload(row, now)
    if row.status == "expired":
        await session.commit()
    return payload


async def activate(
    session: AsyncSession,
    code: str,
    device_fp: str,
    device_name: str | None,
    email: str | None = None,
) -> dict[str, Any]:
    normalized = normalize_code(code)
    if not normalized or not device_fp:
        raise LicenseError(400, "MISSING_PARAMS")

    async with session.begin():
        lic = await session.scalar(select(License).where(License.code == normalized).with_for_update())
        if lic is None:
            raise LicenseError(400, "INVALID_CODE", "激活码无效")
        if lic.status == "revoked":
            raise LicenseError(403, "LICENSE_REVOKED", "该激活码已被吊销")
        if lic.expire_at is not None and lic.expire_at <= int(
            datetime.now(timezone.utc).timestamp() * 1000
        ):
            raise LicenseError(403, "LICENSE_EXPIRED", "该激活码已过期")

        provided_email = (email or "").strip()
        if provided_email and (
            len(provided_email) > 255
            or not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", provided_email)
        ):
            raise LicenseError(400, "INVALID_EMAIL", "邮箱格式不正确")
        bound_email = (lic.email or "").strip()
        if bound_email:
            # 2.0.0–2.0.9 客户端激活时不带 email，不能因此拒绝激活（授权契约兼容）。
            # 带了邮箱就必须与绑定一致。
            if provided_email and provided_email.lower() != bound_email.lower():
                raise LicenseError(403, "EMAIL_MISMATCH", "邮箱与激活码不匹配")
        elif provided_email:
            # 未预绑邮箱的卡密：首次激活时绑定，之后携带邮箱的激活必须一致。
            lic.email = provided_email

        bound = (
            await session.scalars(
                select(DeviceBinding).where(DeviceBinding.code == normalized, DeviceBinding.status == "active")
            )
        ).all()
        payload = _license_payload(lic)

        # 幂等：本设备已绑定，直接返回成功
        existing = next((d for d in bound if d.device_fp == device_fp), None)
        if existing is not None:
            return {
                "ok": True,
                "license": payload,
                "device": _device_dict(existing),
                "bound_count": len(bound),
                "remaining_slots": max(0, lic.max_devices - len(bound)),
            }

        # 设备数检查
        if len(bound) >= lic.max_devices:
            raise LicenseError(
                403,
                "DEVICE_LIMIT_REACHED",
                f"已绑定 {len(bound)}/{lic.max_devices} 台设备，请先解绑旧设备",
                {"bound_devices": [_device_dict(d) for d in bound]},
            )

        # 写入绑定：复用解绑后的旧行，避免唯一键冲突
        bid = str(uuid.uuid4())
        name = device_name or "Unknown"
        stmt = mysql_insert(DeviceBinding).values(
            id=bid, code=normalized, device_fp=device_fp, device_name=name, status="active"
        )
        stmt = stmt.on_duplicate_key_update(
            status="active",
            device_name=name,
            bound_at=func.now(),
            last_seen=func.now(),
        )
        await session.execute(stmt)

        await session.execute(
            update(License)
            .where(License.code == normalized, License.status == "unused")
            .values(status="activated")
        )

    return {
        "ok": True,
        "license": payload,
        "device": {"id": bid, "device_fp": device_fp, "device_name": name, "bound_at": datetime.now(timezone.utc).isoformat()},
        "bound_count": len(bound) + 1,
        "remaining_slots": max(0, lic.max_devices - len(bound) - 1),
    }


async def unbind(session: AsyncSession, code: str, device_fp: str) -> dict[str, Any]:
    normalized = normalize_code(code)
    if not normalized or not device_fp:
        raise LicenseError(400, "MISSING_PARAMS")

    async with session.begin():
        # 必须在事务内查询：SQLAlchemy 2.0 autobegin 后不能再 begin()。
        lic = await _get_license(session, normalized)
        if lic is None:
            raise LicenseError(400, "INVALID_CODE", "激活码无效")
        dev = await session.scalar(
            select(DeviceBinding).where(
                DeviceBinding.code == normalized,
                DeviceBinding.device_fp == device_fp,
                DeviceBinding.status == "active",
            )
        )
        device_name = dev.device_name if dev else "Unknown"

        await session.execute(
            update(DeviceBinding)
            .where(
                DeviceBinding.code == normalized,
                DeviceBinding.device_fp == device_fp,
                DeviceBinding.status == "active",
            )
            .values(status="unbound")
        )
        session.add(
            UnbindLog(id=str(uuid.uuid4()), code=normalized, device_fp=device_fp, device_name=device_name)
        )

    remaining = (
        await session.scalars(
            select(DeviceBinding).where(DeviceBinding.code == normalized, DeviceBinding.status == "active")
        )
    ).all()
    return {"ok": True, "message": "设备已解绑", "remaining_slots": max(0, lic.max_devices - len(remaining))}


async def status(session: AsyncSession, code: str, device_fp: str | None) -> dict[str, Any]:
    normalized = normalize_code(code)
    if not normalized:
        raise LicenseError(400, "MISSING_CODE")
    # 设备列表包含其他设备的指纹，必须由已绑定设备发起，避免仅凭泄漏的卡密枚举/解绑。
    if not device_fp:
        raise LicenseError(400, "MISSING_PARAMS")

    lic = await _get_license(session, normalized)
    if lic is None:
        raise LicenseError(404, "NOT_FOUND")

    current = await session.scalar(
        select(DeviceBinding).where(
            DeviceBinding.code == normalized,
            DeviceBinding.device_fp == device_fp,
            DeviceBinding.status == "active",
        )
    )
    if current is None:
        raise LicenseError(403, "DEVICE_NOT_BOUND")

    devices = (
        await session.scalars(
            select(DeviceBinding)
            .where(DeviceBinding.code == normalized, DeviceBinding.status == "active")
            .order_by(DeviceBinding.bound_at)
        )
    ).all()
    bound_devices = [
        {**_device_dict(d), "is_current": d.device_fp == device_fp} for d in devices
    ]
    return {
        "ok": True,
        "license": _license_payload(lic),
        "bound_devices": bound_devices,
        "remaining_slots": max(0, lic.max_devices - len(devices)),
    }


async def heartbeat(session: AsyncSession, code: str, device_fp: str, device_name: str | None) -> dict[str, Any]:
    normalized = normalize_code(code)
    if not normalized or not device_fp:
        raise LicenseError(400, "MISSING_PARAMS")

    lic = await _get_license(session, normalized)
    if lic is None:
        raise LicenseError(404, "NOT_FOUND")
    if lic.status == "revoked":
        raise LicenseError(403, "LICENSE_REVOKED", "该激活码已被吊销")
    if lic.expire_at is not None and lic.expire_at <= int(
        datetime.now(timezone.utc).timestamp() * 1000
    ):
        raise LicenseError(403, "LICENSE_EXPIRED", "该激活码已过期")

    result = await session.execute(
        update(DeviceBinding)
        .where(
            DeviceBinding.code == normalized,
            DeviceBinding.device_fp == device_fp,
            DeviceBinding.status == "active",
        )
        .values(last_seen=func.now(), device_name=device_name or "Unknown")
    )
    await session.commit()
    if result.rowcount == 0:
        raise LicenseError(404, "NOT_FOUND")
    return {"ok": True, "next_heartbeat_hours": 24}


async def verify(session: AsyncSession, code: str, device_fp: str) -> dict[str, Any]:
    normalized = normalize_code(code)
    if not normalized or not device_fp:
        raise LicenseError(400, "MISSING_PARAMS")

    lic = await _get_license(session, normalized)
    if lic is None:
        return {"ok": True, "valid": False, "reason": "INVALID_CODE"}
    if lic.expire_at is not None and lic.expire_at <= int(
        datetime.now(timezone.utc).timestamp() * 1000
    ):
        return {"ok": True, "valid": False, "reason": "LICENSE_EXPIRED"}

    bound = await session.scalar(
        select(DeviceBinding).where(
            DeviceBinding.code == normalized,
            DeviceBinding.device_fp == device_fp,
            DeviceBinding.status == "active",
        )
    )
    if bound is None:
        return {"ok": True, "valid": False, "reason": "DEVICE_NOT_BOUND"}

    valid = lic.status != "revoked"
    return {
        "ok": True,
        "valid": valid,
        "is_pro": valid,
        "device_active": True,
        "reason": None if valid else "LICENSE_REVOKED",
    }
