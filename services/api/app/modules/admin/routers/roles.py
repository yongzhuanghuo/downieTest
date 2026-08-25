"""角色管理（Pure-Admin /role /role-menu /role-menu-ids 契约）。"""
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, field_validator
from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import get_session
from ..models import SysMenu, SysRole, SysRoleMenu, SysUserRole
from ..serialize import now_ms, ok, role_menu_tree
from .auth import get_current_user

router = APIRouter()


class RoleQuery(BaseModel):
    name: str = ""
    code: str = ""
    status: Optional[int] = None
    pageSize: int = 10
    currentPage: int = 1

    @field_validator("status", mode="before")
    @classmethod
    def _empty_to_none(cls, v):
        return None if v in ("", None) else v


class RoleCreate(BaseModel):
    name: str
    code: str
    status: int = 1
    remark: str = ""


class RoleUpdate(BaseModel):
    name: str
    code: str
    status: int = 1
    remark: str = ""


class RoleMenuIds(BaseModel):
    id: int


class AssignMenu(BaseModel):
    roleId: int
    menuIds: list[int] = []


def _role_dict(r: SysRole) -> dict:
    return {
        "id": r.id,
        "name": r.name,
        "code": r.code,
        "status": r.status,
        "remark": r.remark or "",
        "createTime": r.create_time,
        "updateTime": r.update_time,
    }


@router.post("/role", dependencies=[Depends(get_current_user)])
async def list_roles(q: RoleQuery, session: AsyncSession = Depends(get_session)):
    conds = []
    if q.name:
        conds.append(SysRole.name.contains(q.name))
    if q.code:
        conds.append(SysRole.code.contains(q.code))
    if q.status is not None:
        conds.append(SysRole.status == q.status)

    total = await session.scalar(select(func.count(SysRole.id)).where(*conds)) or 0
    rows = list(
        (
            await session.scalars(
                select(SysRole)
                .where(*conds)
                .order_by(SysRole.id.desc())
                .offset((q.currentPage - 1) * q.pageSize)
                .limit(q.pageSize)
            )
        ).all()
    )
    return ok({"list": [_role_dict(r) for r in rows], "total": total, "pageSize": q.pageSize, "currentPage": q.currentPage})


@router.post("/role/create", dependencies=[Depends(get_current_user)])
async def create_role(body: RoleCreate, session: AsyncSession = Depends(get_session)):
    if await session.scalar(select(SysRole).where(SysRole.code == body.code)):
        raise HTTPException(status_code=400, detail={"code": 400, "message": "角色标识已存在"})
    r = SysRole(name=body.name, code=body.code, status=body.status, remark=body.remark, create_time=now_ms(), update_time=now_ms())
    session.add(r)
    await session.commit()
    return ok()


@router.put("/role/{role_id}", dependencies=[Depends(get_current_user)])
async def update_role(role_id: int, body: RoleUpdate, session: AsyncSession = Depends(get_session)):
    r = await session.scalar(select(SysRole).where(SysRole.id == role_id))
    if not r:
        raise HTTPException(status_code=404, detail={"code": 404, "message": "角色不存在"})
    r.name = body.name
    r.code = body.code
    r.status = body.status
    r.remark = body.remark
    r.update_time = now_ms()
    await session.commit()
    return ok()


@router.delete("/role/{role_id}", dependencies=[Depends(get_current_user)])
async def delete_role(role_id: int, session: AsyncSession = Depends(get_session)):
    r = await session.scalar(select(SysRole).where(SysRole.id == role_id))
    if r and r.code == "admin":
        raise HTTPException(status_code=400, detail={"code": 400, "message": "超级管理员角色不可删除"})
    await session.execute(delete(SysRole).where(SysRole.id == role_id))
    await session.execute(delete(SysRoleMenu).where(SysRoleMenu.role_id == role_id))
    await session.execute(delete(SysUserRole).where(SysUserRole.role_id == role_id))
    await session.commit()
    return ok()


@router.put("/role/{role_id}/status", dependencies=[Depends(get_current_user)])
async def toggle_role_status(role_id: int, body: RoleUpdate, session: AsyncSession = Depends(get_session)):
    r = await session.scalar(select(SysRole).where(SysRole.id == role_id))
    if not r:
        raise HTTPException(status_code=404, detail={"code": 404, "message": "角色不存在"})
    r.status = body.status
    await session.commit()
    return ok()


@router.post("/role-menu", dependencies=[Depends(get_current_user)])
async def role_menu(session: AsyncSession = Depends(get_session)):
    menus = list((await session.scalars(select(SysMenu).order_by(SysMenu.rank))).all())
    return ok(role_menu_tree(menus))


@router.post("/role-menu-ids", dependencies=[Depends(get_current_user)])
async def role_menu_ids(body: RoleMenuIds, session: AsyncSession = Depends(get_session)):
    ids = list((await session.scalars(select(SysRoleMenu.menu_id).where(SysRoleMenu.role_id == body.id))).all())
    return ok(ids)


@router.post("/role/assign-menu", dependencies=[Depends(get_current_user)])
async def assign_menu(body: AssignMenu, session: AsyncSession = Depends(get_session)):
    await session.execute(delete(SysRoleMenu).where(SysRoleMenu.role_id == body.roleId))
    for mid in body.menuIds:
        session.add(SysRoleMenu(role_id=body.roleId, menu_id=mid))
    await session.commit()
    return ok()
