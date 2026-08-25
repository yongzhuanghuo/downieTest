"""卡密管理（Pure-Admin 信封，数据来自授权 licenses 表）。"""
import time
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Response
from pydantic import BaseModel
from sqlalchemy import case, func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import get_session
from app.modules.license.codes import format_code, generate_code
from app.modules.license.models import DeviceBinding, License
from ..serialize import ok
from .auth import get_current_user

router = APIRouter()

_TYPE_MAP = {"free": "免费版", "perpetual": "永久版"}
_STATUS_MAP = {"unused": "未激活", "activated": "已激活", "revoked": "已吊销"}


class CardQuery(BaseModel):
    search: str = ""
    status: Optional[str] = None
    type: Optional[str] = None
    page: int = 1
    pageSize: int = 20


class CardGenerate(BaseModel):
    type: str = "perpetual"
    count: int = 10
    devices: Optional[int] = None
    expire_days: int = 0


def _fmt(v) -> str:
    from datetime import datetime

    if not v:
        return ""
    if isinstance(v, (int, float)):
        v = datetime.fromtimestamp(v / 1000)
    return v.strftime("%Y-%m-%d %H:%M:%S")


def _license_dict(lic: License, bound_count: int = 0) -> dict:
    return {
        "code": lic.code,
        "formatted": format_code(lic.code),
        "type": lic.type,
        "max_devices": lic.max_devices,
        "expire_at": lic.expire_at,
        "status": lic.status,
        "created_at": _fmt(lic.created_at),
        "bound_count": bound_count,
    }


async def _insert_one(session: AsyncSession, type_: str, max_devices: int, expire_at: Optional[int]) -> str:
    for _ in range(3):
        raw = generate_code()
        try:
            session.add(License(code=raw, type=type_, max_devices=max_devices, expire_at=expire_at))
            await session.flush()
            return raw
        except Exception as e:  # noqa: BLE001
            await session.rollback()
            errno = getattr(getattr(e, "orig", None), "args", [None])[0]
            if errno == 1062:
                continue
            raise
    raise RuntimeError("生成失败：多次撞码，请重试")


@router.post("/card/stats", dependencies=[Depends(get_current_user)])
async def card_stats(session: AsyncSession = Depends(get_session)):
    row = (
        await session.execute(
            select(
                func.count(License.code).label("total"),
                func.sum(case((License.status == "unused", 1), else_=0)).label("unused"),
                func.sum(case((License.status == "activated", 1), else_=0)).label("activated"),
                func.sum(case((License.status == "revoked", 1), else_=0)).label("revoked"),
                func.sum(case((License.type == "free", 1), else_=0)).label("free"),
                func.sum(case((License.type == "perpetual", 1), else_=0)).label("perpetual"),
            )
        )
    ).one()
    dev = await session.scalar(select(func.count(DeviceBinding.id)).where(DeviceBinding.status == "active"))
    return ok(
        {
            "total": row.total or 0,
            "unused": row.unused or 0,
            "activated": row.activated or 0,
            "revoked": row.revoked or 0,
            "free": row.free or 0,
            "perpetual": row.perpetual or 0,
            "bound_devices": dev or 0,
        }
    )


@router.post("/card/list", dependencies=[Depends(get_current_user)])
async def card_list(q: CardQuery, session: AsyncSession = Depends(get_session)):
    conds = []
    if q.search:
        conds.append(License.code.like(f"%{q.search.strip().upper()}%"))
    if q.status in ("unused", "activated", "revoked"):
        conds.append(License.status == q.status)
    if q.type in ("free", "perpetual"):
        conds.append(License.type == q.type)

    total = await session.scalar(select(func.count(License.code)).where(*conds)) or 0
    bound_sub = (
        select(func.count(DeviceBinding.id))
        .where(DeviceBinding.code == License.code, DeviceBinding.status == "active")
        .scalar_subquery()
    )
    rows = (
        await session.execute(
            select(License, bound_sub.label("bound_count"))
            .where(*conds)
            .order_by(License.created_at.desc())
            .offset((q.page - 1) * q.pageSize)
            .limit(q.pageSize)
        )
    ).all()
    return ok(
        {
            "list": [_license_dict(lic, bc or 0) for lic, bc in rows],
            "total": total,
            "page": q.page,
            "pageSize": q.pageSize,
        }
    )


@router.post("/card/generate", dependencies=[Depends(get_current_user)])
async def card_generate(body: CardGenerate, session: AsyncSession = Depends(get_session)):
    t = "free" if body.type == "free" else "perpetual"
    max_devices = body.devices if body.devices is not None else (4 if t == "perpetual" else 1)
    expire_at = None if body.expire_days <= 0 else int(time.time() * 1000) + body.expire_days * 86400 * 1000
    n = min(1000, max(1, body.count))

    raws = []
    for _ in range(n):
        raws.append(await _insert_one(session, t, max_devices, expire_at))
    await session.commit()
    return ok({"count": len(raws), "type": t, "max_devices": max_devices, "codes": [format_code(r) for r in raws]})


@router.get("/card/export", dependencies=[Depends(get_current_user)])
async def card_export(
    search: str = "",
    status: Optional[str] = None,
    type: Optional[str] = None,
    page: Optional[int] = None,
    pageSize: Optional[int] = None,
    session: AsyncSession = Depends(get_session),
):
    conds = []
    if search:
        conds.append(License.code.like(f"%{search.strip().upper()}%"))
    if status in ("unused", "activated", "revoked"):
        conds.append(License.status == status)
    if type in ("free", "perpetual"):
        conds.append(License.type == type)

    stmt = select(License).where(*conds).order_by(License.created_at.desc())
    if page and pageSize:
        stmt = stmt.offset((page - 1) * pageSize).limit(pageSize)
    rows = list((await session.scalars(stmt)).all())

    lines = ["激活码,类型,设备数,状态,过期时间,创建时间"]
    for r in rows:
        expire = _fmt(r.expire_at) if r.expire_at else "永久"
        lines.append(
            f"{format_code(r.code)},{_TYPE_MAP.get(r.type, r.type)},{r.max_devices},"
            f"{_STATUS_MAP.get(r.status, r.status)},{expire},{_fmt(r.created_at)}"
        )
    return Response(
        content="﻿" + "\n".join(lines) + "\n",
        media_type="text/csv; charset=utf-8",
        headers={"Content-Disposition": "attachment; filename=licenses.csv"},
    )


@router.get("/card/{code}", dependencies=[Depends(get_current_user)])
async def card_detail(code: str, session: AsyncSession = Depends(get_session)):
    lic = await session.scalar(select(License).where(License.code == code))
    if not lic:
        raise HTTPException(status_code=404, detail={"code": 404, "message": "卡密不存在"})
    devices = list(
        (await session.scalars(select(DeviceBinding).where(DeviceBinding.code == code).order_by(DeviceBinding.bound_at.desc()))).all()
    )
    return ok(
        {
            "license": _license_dict(lic),
            "devices": [
                {"id": d.id, "device_name": d.device_name, "device_fp": d.device_fp, "last_seen": _fmt(d.last_seen), "status": d.status}
                for d in devices
            ],
        }
    )


@router.post("/card/{code}/revoke", dependencies=[Depends(get_current_user)])
async def card_revoke(code: str, session: AsyncSession = Depends(get_session)):
    r = await session.execute(update(License).where(License.code == code).values(status="revoked"))
    await session.commit()
    if r.rowcount == 0:
        raise HTTPException(status_code=404, detail={"code": 404, "message": "卡密不存在"})
    return ok()


@router.post("/card/{code}/restore", dependencies=[Depends(get_current_user)])
async def card_restore(code: str, session: AsyncSession = Depends(get_session)):
    r = await session.execute(update(License).where(License.code == code, License.status == "revoked").values(status="unused"))
    await session.commit()
    if r.rowcount == 0:
        raise HTTPException(status_code=404, detail={"code": 404, "message": "卡密不存在或非吊销状态"})
    return ok()


