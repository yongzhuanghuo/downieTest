"""用户管理（Pure-Admin /user /list-all-role /list-role-ids 契约）。"""
from typing import Optional

import bcrypt
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, field_validator
from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import get_session
from ..models import SysDept, SysRole, SysUser, SysUserRole
from ..serialize import now_ms, ok
from .auth import get_current_user

router = APIRouter()


class UserQuery(BaseModel):
    username: str = ""
    phone: str = ""
    status: Optional[int] = None
    deptId: Optional[int] = None
    pageSize: int = 10
    currentPage: int = 1

    @field_validator("status", "deptId", mode="before")
    @classmethod
    def _empty_to_none(cls, v):
        return None if v in ("", None) else v


class UserCreate(BaseModel):
    username: str
    password: str
    nickname: str = ""
    phone: str = ""
    email: str = ""
    sex: int = 0
    deptId: Optional[int] = None
    status: int = 1
    remark: str = ""


class UserUpdate(BaseModel):
    nickname: str = ""
    phone: str = ""
    email: str = ""
    sex: int = 0
    deptId: Optional[int] = None
    status: int = 1
    remark: str = ""


class ResetPassword(BaseModel):
    userId: int
    password: str


class AssignRole(BaseModel):
    userId: int
    roleIds: list[int] = []


class RoleIdsQuery(BaseModel):
    userId: int


async def _dept_map(session: AsyncSession) -> dict[int, str]:
    depts = list((await session.scalars(select(SysDept))).all())
    return {d.id: d.name for d in depts}


def _user_dict(u: SysUser, dept_map: dict[int, str]) -> dict:
    return {
        "id": u.id,
        "avatar": u.avatar or "",
        "username": u.username,
        "nickname": u.nickname or "",
        "sex": u.sex,
        "dept": {"id": u.dept_id, "name": dept_map.get(u.dept_id, "")} if u.dept_id else {},
        "phone": u.phone or "",
        "email": u.email or "",
        "status": u.status,
        "remark": u.remark or "",
        "createTime": u.create_time,
    }


@router.post("/user", dependencies=[Depends(get_current_user)])
async def list_users(q: UserQuery, session: AsyncSession = Depends(get_session)):
    conds = []
    if q.username:
        conds.append(SysUser.username.contains(q.username))
    if q.phone:
        conds.append(SysUser.phone == q.phone)
    if q.status is not None:
        conds.append(SysUser.status == q.status)
    if q.deptId is not None:
        conds.append(SysUser.dept_id == q.deptId)

    total = await session.scalar(select(func.count(SysUser.id)).where(*conds)) or 0
    rows = list(
        (
            await session.scalars(
                select(SysUser)
                .where(*conds)
                .order_by(SysUser.id.desc())
                .offset((q.currentPage - 1) * q.pageSize)
                .limit(q.pageSize)
            )
        ).all()
    )
    dm = await _dept_map(session)
    return ok({"list": [_user_dict(u, dm) for u in rows], "total": total, "pageSize": q.pageSize, "currentPage": q.currentPage})


@router.post("/user/create", dependencies=[Depends(get_current_user)])
async def create_user(body: UserCreate, session: AsyncSession = Depends(get_session)):
    exists = await session.scalar(select(SysUser).where(SysUser.username == body.username))
    if exists:
        raise HTTPException(status_code=400, detail={"code": 400, "message": "用户名已存在"})
    u = SysUser(
        username=body.username,
        password_hash=bcrypt.hashpw(body.password.encode(), bcrypt.gensalt()).decode(),
        nickname=body.nickname,
        phone=body.phone,
        email=body.email,
        sex=body.sex,
        dept_id=body.deptId,
        status=body.status,
        remark=body.remark,
        create_time=now_ms(),
        update_time=now_ms(),
    )
    session.add(u)
    await session.commit()
    return ok()


@router.put("/user/{user_id}", dependencies=[Depends(get_current_user)])
async def update_user(user_id: int, body: UserUpdate, session: AsyncSession = Depends(get_session)):
    u = await session.scalar(select(SysUser).where(SysUser.id == user_id))
    if not u:
        raise HTTPException(status_code=404, detail={"code": 404, "message": "用户不存在"})
    u.nickname = body.nickname
    u.phone = body.phone
    u.email = body.email
    u.sex = body.sex
    u.dept_id = body.deptId
    u.status = body.status
    u.remark = body.remark
    u.update_time = now_ms()
    await session.commit()
    return ok()


@router.delete("/user/{user_id}", dependencies=[Depends(get_current_user)])
async def delete_user(user_id: int, session: AsyncSession = Depends(get_session)):
    if user_id == 1:
        raise HTTPException(status_code=400, detail={"code": 400, "message": "超级管理员不可删除"})
    await session.execute(delete(SysUser).where(SysUser.id == user_id))
    await session.execute(delete(SysUserRole).where(SysUserRole.user_id == user_id))
    await session.commit()
    return ok()


@router.put("/user/{user_id}/status", dependencies=[Depends(get_current_user)])
async def toggle_user_status(user_id: int, body: UserUpdate, session: AsyncSession = Depends(get_session)):
    u = await session.scalar(select(SysUser).where(SysUser.id == user_id))
    if not u:
        raise HTTPException(status_code=404, detail={"code": 404, "message": "用户不存在"})
    u.status = body.status
    await session.commit()
    return ok()


@router.post("/user/reset-password", dependencies=[Depends(get_current_user)])
async def reset_password(body: ResetPassword, session: AsyncSession = Depends(get_session)):
    u = await session.scalar(select(SysUser).where(SysUser.id == body.userId))
    if not u:
        raise HTTPException(status_code=404, detail={"code": 404, "message": "用户不存在"})
    u.password_hash = bcrypt.hashpw(body.password.encode(), bcrypt.gensalt()).decode()
    u.update_time = now_ms()
    await session.commit()
    return ok()


@router.post("/user/assign-role", dependencies=[Depends(get_current_user)])
async def assign_role(body: AssignRole, session: AsyncSession = Depends(get_session)):
    await session.execute(delete(SysUserRole).where(SysUserRole.user_id == body.userId))
    for rid in body.roleIds:
        session.add(SysUserRole(user_id=body.userId, role_id=rid))
    await session.commit()
    return ok()


@router.get("/list-all-role", dependencies=[Depends(get_current_user)])
async def list_all_role(session: AsyncSession = Depends(get_session)):
    roles = list((await session.scalars(select(SysRole).order_by(SysRole.id))).all())
    return ok([{"id": r.id, "name": r.name} for r in roles])


@router.post("/list-role-ids", dependencies=[Depends(get_current_user)])
async def list_role_ids(body: RoleIdsQuery, session: AsyncSession = Depends(get_session)):
    ids = list(
        (await session.scalars(select(SysUserRole.role_id).where(SysUserRole.user_id == body.userId))).all()
    )
    return ok(ids)
