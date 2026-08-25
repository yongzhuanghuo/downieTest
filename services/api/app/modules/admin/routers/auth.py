"""登录 / 刷新 token / 动态菜单（Pure-Admin 契约）。"""
import time
from typing import Optional

import bcrypt
import jwt
from fastapi import APIRouter, Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.db import get_session
from ..models import SysMenu, SysRole, SysRoleMenu, SysUser, SysUserRole
from ..serialize import build_route_tree, ok

router = APIRouter()
_bearer = HTTPBearer(auto_error=False)

ACCESS_TTL = 86400       # 24h
REFRESH_TTL = 604800     # 7d


class LoginBody(BaseModel):
    username: str
    password: str


class RefreshBody(BaseModel):
    refreshToken: str


def _make_token(payload: dict, ttl: int) -> str:
    return jwt.encode({**payload, "exp": int(time.time()) + ttl}, settings.jwt_secret, algorithm="HS256")


def _fmt_expires(ttl: int) -> str:
    return time.strftime("%Y/%m/%d %H:%M:%S", time.localtime(time.time() + ttl))


async def _load_user_auth(session: AsyncSession, user: SysUser) -> tuple[list[str], list[str], bool]:
    """返回 (角色 code 列表, 权限码列表, 是否超管)。"""
    role_ids = list(
        (await session.scalars(select(SysUserRole.role_id).where(SysUserRole.user_id == user.id))).all()
    )
    roles: list[SysRole] = []
    if role_ids:
        roles = list((await session.scalars(select(SysRole).where(SysRole.id.in_(role_ids)))).all())

    role_codes = [r.code for r in roles]
    is_admin = "admin" in role_codes

    if is_admin:
        return ["admin"], ["*:*:*"], True

    permissions: list[str] = []
    if role_ids:
        menu_ids = list(
            (await session.scalars(select(SysRoleMenu.menu_id).where(SysRoleMenu.role_id.in_(role_ids)))).all()
        )
        if menu_ids:
            menus = list(
                (await session.scalars(select(SysMenu).where(SysMenu.id.in_(menu_ids), SysMenu.menu_type == 3)))
            )
            seen = set()
            for m in menus:
                if m.auths:
                    for a in m.auths.split(","):
                        a = a.strip()
                        if a and a not in seen:
                            seen.add(a)
                            permissions.append(a)
    return role_codes, permissions, False


async def get_current_user(
    cred: Optional[HTTPAuthorizationCredentials] = Depends(_bearer),
    session: AsyncSession = Depends(get_session),
) -> dict:
    token = cred.credentials if cred else ""
    if not token:
        raise HTTPException(status_code=401, detail={"code": 401, "message": "未登录"})
    try:
        payload = jwt.decode(token, settings.jwt_secret, algorithms=["HS256"])
        if payload.get("type") != "access":
            raise ValueError
    except Exception:
        raise HTTPException(status_code=401, detail={"code": 401, "message": "登录已过期"})

    user_id = payload.get("user_id")
    user = await session.scalar(select(SysUser).where(SysUser.id == user_id))
    if not user or user.status != 1:
        raise HTTPException(status_code=401, detail={"code": 401, "message": "账号不可用"})

    role_codes, permissions, is_admin = await _load_user_auth(session, user)
    return {
        "user_id": user.id,
        "username": user.username,
        "nickname": user.nickname or user.username,
        "avatar": user.avatar or "",
        "roles": role_codes,
        "permissions": permissions,
        "is_admin": is_admin,
    }


@router.post("/login")
async def login(body: LoginBody, session: AsyncSession = Depends(get_session)):
    user = await session.scalar(select(SysUser).where(SysUser.username == body.username))
    if not user or not bcrypt.checkpw(body.password.encode(), user.password_hash.encode()):
        return {"code": 10001, "message": "用户名或密码错误", "data": None}
    if user.status != 1:
        return {"code": 10002, "message": "账号已停用", "data": None}

    roles, permissions, _ = await _load_user_auth(session, user)
    access = _make_token({"user_id": user.id, "username": user.username, "type": "access"}, ACCESS_TTL)
    refresh = _make_token({"user_id": user.id, "type": "refresh"}, REFRESH_TTL)
    return ok(
        {
            "avatar": user.avatar or "",
            "username": user.username,
            "nickname": user.nickname or user.username,
            "roles": roles,
            "permissions": permissions,
            "accessToken": access,
            "refreshToken": refresh,
            "expires": _fmt_expires(ACCESS_TTL),
        }
    )


@router.post("/refresh-token")
async def refresh_token(body: RefreshBody):
    try:
        payload = jwt.decode(body.refreshToken, settings.jwt_secret, algorithms=["HS256"])
        if payload.get("type") != "refresh":
            raise ValueError
        user_id = payload.get("user_id")
    except Exception:
        return {"code": 10001, "message": "刷新失败，请重新登录", "data": None}

    access = _make_token({"user_id": user_id, "type": "access"}, ACCESS_TTL)
    refresh = _make_token({"user_id": user_id, "type": "refresh"}, REFRESH_TTL)
    return ok({"accessToken": access, "refreshToken": refresh, "expires": _fmt_expires(ACCESS_TTL)})


@router.get("/get-async-routes")
async def get_async_routes(cur: dict = Depends(get_current_user), session: AsyncSession = Depends(get_session)):
    if cur["is_admin"]:
        menus = list(
            (await session.scalars(select(SysMenu).where(SysMenu.menu_type != 3).order_by(SysMenu.rank))).all()
        )
    else:
        role_ids = list(
            (await session.scalars(select(SysUserRole.role_id).where(SysUserRole.user_id == cur["user_id"]))).all()
        )
        menu_ids = list(
            (await session.scalars(select(SysRoleMenu.menu_id).where(SysRoleMenu.role_id.in_(role_ids)))).all()
        )
        menus = (
            list(
                (
                    await session.scalars(
                        select(SysMenu).where(SysMenu.id.in_(menu_ids), SysMenu.menu_type != 3).order_by(SysMenu.rank)
                    )
                ).all()
            )
            if menu_ids
            else []
        )
    return ok(build_route_tree(menus))
