"""客户端授权接口（移植自 Node 版 src/routes/license.js）。

挂载方式：app.include_router(router)（无 prefix，路径自含 /api/license/*）。
响应契约与 Node 版逐字段对齐，桌面端 v2.0.0 无感。
"""
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import get_session

from . import service

router = APIRouter()


class ActivateBody(BaseModel):
    code: str
    device_fp: str
    device_name: Optional[str] = None


class UnbindBody(BaseModel):
    code: str
    device_fp: str


class HeartbeatBody(BaseModel):
    code: str
    device_fp: str
    device_name: Optional[str] = None


class VerifyBody(BaseModel):
    code: str
    device_fp: str


def _raise(e: service.LicenseError):
    body = {"ok": False, "error": e.error}
    if e.message:
        body["message"] = e.message
    body.update(e.extra)
    raise HTTPException(status_code=e.status, detail=body)


@router.get("/")
async def health():
    # 契约兼容：桌面端（若）探测根路径时拿到与旧服务一致的标识
    return {"service": "Downie License API", "version": "2.0.0", "status": "ok"}


@router.post("/api/license/activate")
async def activate(body: ActivateBody, session: AsyncSession = Depends(get_session)):
    try:
        return await service.activate(session, body.code, body.device_fp, body.device_name)
    except service.LicenseError as e:
        _raise(e)


@router.post("/api/license/unbind")
async def unbind(body: UnbindBody, session: AsyncSession = Depends(get_session)):
    try:
        return await service.unbind(session, body.code, body.device_fp)
    except service.LicenseError as e:
        _raise(e)


@router.get("/api/license/status")
async def status(code: str, device_fp: Optional[str] = None, session: AsyncSession = Depends(get_session)):
    try:
        return await service.status(session, code, device_fp)
    except service.LicenseError as e:
        _raise(e)


@router.post("/api/license/heartbeat")
async def heartbeat(body: HeartbeatBody, session: AsyncSession = Depends(get_session)):
    try:
        return await service.heartbeat(session, body.code, body.device_fp, body.device_name)
    except service.LicenseError as e:
        _raise(e)


@router.post("/api/license/verify")
async def verify(body: VerifyBody, session: AsyncSession = Depends(get_session)):
    try:
        return await service.verify(session, body.code, body.device_fp)
    except service.LicenseError as e:
        _raise(e)
