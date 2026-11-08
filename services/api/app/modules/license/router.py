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
    product: Optional[str] = None


class ActivateBody(BaseModel):
    code: str
    device_fp: str
    device_name: Optional[str] = None
    email: Optional[str] = None
    product: Optional[str] = None


class UnbindBody(BaseModel):
    code: str
    device_fp: str
    product: Optional[str] = None


class HeartbeatBody(BaseModel):
    code: str
    device_fp: str
    device_name: Optional[str] = None
    product: Optional[str] = None


class VerifyBody(BaseModel):
    code: str
    device_fp: str
    product: Optional[str] = None


class RecoverBody(BaseModel):
    email: str
    product: Optional[str] = None


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
            body.product,
        )
    except service.LicenseError as e:
        _raise(e)


@router.get("/api/license/trial/status")
async def trial_status(
    device_fp: str,
    request: Request,
    product: Optional[str] = None,
    session: AsyncSession = Depends(get_session),
):
    _rate_limit(request, "trial-status", limit=120, window_seconds=60)
    try:
        return await service.trial_status(session, device_fp, product)
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
            body.product,
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
        return await service.unbind(session, body.code, body.device_fp, body.product)
    except service.LicenseError as e:
        _raise(e)


@router.get("/api/license/status")
async def status(
    code: str,
    request: Request,
    device_fp: Optional[str] = None,
    product: Optional[str] = None,
    session: AsyncSession = Depends(get_session),
):
    _rate_limit(request, "status", limit=60, window_seconds=60)
    try:
        return await service.status(session, code, device_fp, product)
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
        return await service.heartbeat(session, body.code, body.device_fp, body.device_name, body.product)
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
        return await service.verify(session, body.code, body.device_fp, body.product)
    except service.LicenseError as e:
        _raise(e)


@router.post("/api/license/recover")
async def recover(
    body: RecoverBody,
    request: Request,
    session: AsyncSession = Depends(get_session),
):
    """按邮箱把许可证代码发到该邮箱。

    未命中时明确返回 found=false（对应 Downie 的 211「no purchase records」），
    让用户立即知道邮箱是否填错；IP/邮箱双重限流抵消枚举风险。
    """
    _rate_limit(request, "recover-ip", limit=10, window_seconds=3600)
    email = body.email.strip()
    if len(email) > 255 or "@" not in email:
        raise HTTPException(
            status_code=400,
            detail={"ok": False, "error": "INVALID_EMAIL", "message": "邮箱格式不正确"},
        )
    # 邮箱维度：每小时 3 封 + 60 秒冷却，防止把服务端当垃圾邮件出口
    key = f"recover-email:{email.lower()}"
    if not _limiter.allow(key, limit=3, window_seconds=3600) or not _limiter.allow(
        f"{key}:cooldown", limit=1, window_seconds=60
    ):
        raise HTTPException(
            status_code=429,
            detail={"ok": False, "error": "RATE_LIMITED", "message": "发送过于频繁，请稍后再试"},
        )
    try:
        found = await service.recover_by_email(session, email, body.product)
    except service.LicenseError as e:
        _raise(e)
    # 与 Downie 一致：明确告诉用户该邮箱下有没有购买记录。
    # 有 IP/邮箱双重限流，枚举成本远高于收益。
    if not found:
        return {
            "ok": True,
            "found": False,
            "message": "该邮箱下没有找到许可证，请确认是激活时填写的邮箱",
        }
    return {
        "ok": True,
        "found": True,
        "message": "许可证代码已发送到该邮箱",
        "retry_after": 60,
    }
