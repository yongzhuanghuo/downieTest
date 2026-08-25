"""部门管理（Pure-Admin /dept 契约，一维数组）。"""
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import get_session
from ..models import SysDept
from ..serialize import now_ms, ok
from .auth import get_current_user

router = APIRouter()


class DeptBody(BaseModel):
    parentId: int = 0
    name: str = ""
    sort: int = 0
    phone: str = ""
    principal: str = ""
    email: str = ""
    status: int = 1
    type: int = 3
    remark: str = ""


def _dept_dict(d: SysDept) -> dict:
    return {
        "id": d.id,
        "parentId": d.parent_id,
        "name": d.name,
        "sort": d.sort,
        "phone": d.phone or "",
        "principal": d.principal or "",
        "email": d.email or "",
        "status": d.status,
        "type": d.dept_type,
        "createTime": d.create_time,
        "remark": d.remark or "",
    }


@router.post("/dept", dependencies=[Depends(get_current_user)])
async def list_depts(session: AsyncSession = Depends(get_session)):
    depts = list((await session.scalars(select(SysDept).order_by(SysDept.sort, SysDept.id))).all())
    return ok([_dept_dict(d) for d in depts])


@router.post("/dept/create", dependencies=[Depends(get_current_user)])
async def create_dept(body: DeptBody, session: AsyncSession = Depends(get_session)):
    d = SysDept(
        parent_id=body.parentId,
        name=body.name,
        sort=body.sort,
        phone=body.phone,
        principal=body.principal,
        email=body.email,
        status=body.status,
        dept_type=body.type,
        remark=body.remark,
        create_time=now_ms(),
    )
    session.add(d)
    await session.commit()
    return ok()


@router.put("/dept/{dept_id}", dependencies=[Depends(get_current_user)])
async def update_dept(dept_id: int, body: DeptBody, session: AsyncSession = Depends(get_session)):
    d = await session.scalar(select(SysDept).where(SysDept.id == dept_id))
    if not d:
        raise HTTPException(status_code=404, detail={"code": 404, "message": "部门不存在"})
    d.parent_id = body.parentId
    d.name = body.name
    d.sort = body.sort
    d.phone = body.phone
    d.principal = body.principal
    d.email = body.email
    d.status = body.status
    d.dept_type = body.type
    d.remark = body.remark
    await session.commit()
    return ok()


@router.delete("/dept/{dept_id}", dependencies=[Depends(get_current_user)])
async def delete_dept(dept_id: int, session: AsyncSession = Depends(get_session)):
    d = await session.scalar(select(SysDept).where(SysDept.id == dept_id))
    if not d:
        raise HTTPException(status_code=404, detail={"code": 404, "message": "部门不存在"})
    await session.delete(d)
    await session.commit()
    return ok()
