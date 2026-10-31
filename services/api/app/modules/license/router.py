"""客户端授权接口（移植自 Node 版 src/routes/license.js）。

挂载方式：app.include_router(router)（无 prefix，路径自含 /api/license/*）。
响应契约与 Node 版逐字段对齐，桌面端 v2.0.0 无感。
"""
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import get_session
from app.ratelimit import InMemoryRateLimiter, client_ip

from . import service

router = APIRouter()

# 进程内限流：授权接口是最容易被枚举/爆破的入口。
_limiter = InMemoryRateLimiter()


def _rate_limit(request: Request, bucket: str, *, limit: int, window_seconds: float) -> None:
    key = f"{bucket}:{client_ip(request)}"
    if not _limiter.allow(key, limit=limit, window_seconds=window_seconds):
        raise HTTPException(
            status_code=429,
            detail={"ok": False, "error": "RATE_LIMITED", "message": "请求过于频繁，请稍后再试"},
        )


class TrialBody(BaseModel):
    device_fp: str
    device_name: Optional[str] = None
    platform: Optional[str] = None
    email: Optional[str] = None


class ActivateBody(BaseModel):
    code: str
    device_fp: str
    device_name: Optional[str] = None
    email: Optional[str] = None


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


@router.post("/api/license/trial/start")
async def trial_start(
    body: TrialBody,
    request: Request,
    session: AsyncSession = Depends(get_session),
):
    _rate_limit(request, "trial-start", limit=60, window_seconds=3600)
    try:
        return await service.start_trial(
            session,
            body.device_fp,
            body.device_name,
            body.platform,
            body.email,
        )
    except service.LicenseError as e:
        _raise(e)


@router.get("/api/license/trial/status")
async def trial_status(
    device_fp: str,
    request: Request,
    session: AsyncSession = Depends(get_session),
):
    _rate_limit(request, "trial-status", limit=120, window_seconds=60)
    try:
        return await service.trial_status(session, device_fp)
    except service.LicenseError as e:
        _raise(e)


@router.post("/api/license/activate")
async def activate(
    body: ActivateBody,
    request: Request,
    session: AsyncSession = Depends(get_session),
):
    _rate_limit(request, "activate", limit=30, window_seconds=600)
    try:
        return await service.activate(
            session,
            body.code,
            body.device_fp,
            body.device_name,
            body.email,
        )
    except service.LicenseError as e:
        _raise(e)


@router.post("/api/license/unbind")
async def unbind(
    body: UnbindBody,
    request: Request,
    session: AsyncSession = Depends(get_session),
):
    _rate_limit(request, "unbind", limit=30, window_seconds=600)
    try:
        return await service.unbind(session, body.code, body.device_fp)
    except service.LicenseError as e:
        _raise(e)


@router.get("/api/license/status")
async def status(
    code: str,
    request: Request,
    device_fp: Optional[str] = None,
    session: AsyncSession = Depends(get_session),
):
    _rate_limit(request, "status", limit=60, window_seconds=60)
    try:
        return await service.status(session, code, device_fp)
    except service.LicenseError as e:
        _raise(e)


@router.post("/api/license/heartbeat")
async def heartbeat(
    body: HeartbeatBody,
    request: Request,
    session: AsyncSession = Depends(get_session),
):
    _rate_limit(request, "heartbeat", limit=120, window_seconds=60)
    try:
        return await service.heartbeat(session, body.code, body.device_fp, body.device_name)
    except service.LicenseError as e:
        _raise(e)


@router.post("/api/license/verify")
async def verify(
    body: VerifyBody,
    request: Request,
    session: AsyncSession = Depends(get_session),
):
    _rate_limit(request, "verify", limit=120, window_seconds=60)
    try:
        return await service.verify(session, body.code, body.device_fp)
    except service.LicenseError as e:
        _raise(e)
