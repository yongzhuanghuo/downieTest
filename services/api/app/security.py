"""鉴权与签名工具。

三块：
  1. require_admin — 管理后台 JWT 认证（Bearer token，24h）
  2. require_license — 客户端授权校验（X-License-Code / X-Device-FP 头）
  3. sign_url / verify_signature — 媒体文件签名 URL（HMAC + 过期时间）

说明：require_license 是「宽松」模式 —— 没带头就放行（保证老移动端不挂），
带了头但码无效/设备未绑定则拒绝。等移动端接入后把 MEDIA_REQUIRE_LICENSE=1 改为强制。
"""
import hashlib
import hmac
import time
from typing import Optional

import jwt
from fastapi import Depends, Header, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from .config import settings
from .db import get_session
from .modules.license.models import DeviceBinding, License

_bearer = HTTPBearer(auto_error=False)


# ---------- 管理端 JWT ----------

def _unauthorized(message: str = "未登录") -> HTTPException:
    # 管理后台（Pure-Admin）读取 detail.code / detail.message 做跳转，保持该契约。
    return HTTPException(status_code=401, detail={"code": 401, "message": message})


async def require_admin(
    cred: Optional[HTTPAuthorizationCredentials] = Depends(_bearer),
    session: AsyncSession = Depends(get_session),
) -> dict:
    """管理后台接口：必须是有效 JWT 且账号具有 admin 角色。

    之前的实现只验签、不验角色，任何登录用户都能调卡密/用户管理接口。
    """
    token = cred.credentials if cred else ""
    if not token:
        raise _unauthorized()
    try:
        payload = jwt.decode(token, settings.jwt_secret, algorithms=["HS256"])
        if payload.get("type") != "access":
            raise ValueError
    except Exception:
        raise _unauthorized()

    # 延迟导入，避免 security <-> admin.models 的模块级循环依赖
    from .modules.admin.models import SysRole, SysUser, SysUserRole

    user = await session.scalar(select(SysUser).where(SysUser.id == payload.get("user_id")))
    if user is None or user.status != 1:
        raise _unauthorized()

    role_ids = list(
        (await session.scalars(select(SysUserRole.role_id).where(SysUserRole.user_id == user.id))).all()
    )
    roles = (
        list((await session.scalars(select(SysRole).where(SysRole.id.in_(role_ids)))).all())
        if role_ids
        else []
    )
    if "admin" not in [r.code for r in roles]:
        raise HTTPException(status_code=403, detail={"code": 403, "message": "无管理员权限"})

    return {"user_id": user.id, "username": user.username}


# ---------- 客户端授权 ----------

async def require_license(
    x_license_code: Optional[str] = Header(default=None),
    x_device_fp: Optional[str] = Header(default=None),
    session: AsyncSession = Depends(get_session),
) -> Optional[License]:
    """校验请求头里的激活码 + 设备指纹，返回有效 License 或抛 403。

    无头时放行（None），保证未接入授权的老客户端不挂；
    带了头但码无效/设备未绑定则拒绝。
    """
    from .modules.license.codes import normalize_code

    if not x_license_code and not x_device_fp:
        return None

    if not x_license_code or not x_device_fp:
        raise HTTPException(status_code=401, detail={"ok": False, "error": "MISSING_PARAMS"})

    normalized = normalize_code(x_license_code)
    lic = await session.scalar(select(License).where(License.code == normalized))
    if lic is None or lic.status == "revoked":
        raise HTTPException(status_code=403, detail={"ok": False, "error": "INVALID_LICENSE"})
    if lic.expire_at is not None and lic.expire_at <= int(time.time() * 1000):
        raise HTTPException(status_code=403, detail={"ok": False, "error": "LICENSE_EXPIRED"})

    bound = await session.scalar(
        select(DeviceBinding).where(
            DeviceBinding.code == normalized,
            DeviceBinding.device_fp == x_device_fp,
            DeviceBinding.status == "active",
        )
    )
    if bound is None:
        raise HTTPException(status_code=403, detail={"ok": False, "error": "DEVICE_NOT_BOUND"})

    return lic


# ---------- 签名 URL ----------

def sign_url(path: str, ttl: int = 3600) -> str:
    """给媒体文件相对路径（/files/xxx 或 /tmp/xxx）拼上 exp + sig。"""
    exp = int(time.time()) + ttl
    sig = _sign(path, exp)
    sep = "&" if "?" in path else "?"
    return f"{path}{sep}exp={exp}&sig={sig}"


def verify_signature(path: str, exp: str, sig: str) -> bool:
    try:
        exp_i = int(exp)
    except (TypeError, ValueError):
        return False
    if exp_i < int(time.time()):
        return False
    expected = _sign(path, exp_i)
    return hmac.compare_digest(expected, sig or "")


def _sign(path: str, exp: int) -> str:
    key = settings.jwt_secret.encode() if settings.jwt_secret else b""
    return hmac.new(key, f"{path}|{exp}".encode(), hashlib.sha256).hexdigest()


# FastAPI 请求头注入别名（挂依赖时写 Depends(require_license) 即可，
# FastAPI 会自动从请求头 X-License-Code / X-Device-Fp 匹配参数名）
