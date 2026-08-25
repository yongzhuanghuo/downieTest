"""授权业务逻辑（移植自 Node 版 src/routes/license.js）。

契约严格对齐：路径、字段名、错误码、HTTP 状态码都保持不变。
关键移植点：
  - SELECT ... FOR UPDATE 防超绑（必须与写操作在同一事务、同一连接上）
  - ON DUPLICATE KEY UPDATE 复用解绑后的旧行，避免唯一键冲突
"""
import uuid
from datetime import datetime, timezone
from typing import Any

from sqlalchemy import func, select, text, update
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.dialects.mysql import insert as mysql_insert

from .codes import normalize_code
from .models import DeviceBinding, License, UnbindLog


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


async def activate(session: AsyncSession, code: str, device_fp: str, device_name: str | None) -> dict[str, Any]:
    normalized = normalize_code(code)
    if not normalized or not device_fp:
        raise LicenseError(400, "MISSING_PARAMS")

    async with session.begin():
        lic = await session.scalar(select(License).where(License.code == normalized).with_for_update())
        if lic is None:
            raise LicenseError(400, "INVALID_CODE", "激活码无效")
        if lic.status == "revoked":
            raise LicenseError(403, "LICENSE_REVOKED", "该激活码已被吊销")

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

    lic = await _get_license(session, normalized)
    if lic is None:
        raise LicenseError(400, "INVALID_CODE", "激活码无效")

    async with session.begin():
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

    lic = await _get_license(session, normalized)
    if lic is None:
        raise LicenseError(404, "NOT_FOUND")

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

    bound = await session.scalar(
        select(DeviceBinding).where(
            DeviceBinding.code == normalized,
            DeviceBinding.device_fp == device_fp,
            DeviceBinding.status == "active",
        )
    )
    if bound is None:
        return {"ok": True, "valid": False, "reason": "DEVICE_NOT_BOUND"}

    return {"ok": True, "valid": lic.status != "revoked", "is_pro": True, "device_active": True}
