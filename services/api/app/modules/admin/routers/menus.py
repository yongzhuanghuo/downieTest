"""菜单管理（Pure-Admin /menu 契约，一维数组，前端 handleTree 转树）。"""
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import get_session
from ..models import SysMenu, SysRoleMenu
from ..serialize import menu_to_dict, ok
from .auth import get_current_user

router = APIRouter()


class MenuBody(BaseModel):
    parentId: int = 0
    menuType: int = 0
    title: str = ""
    name: str = ""
    path: str = ""
    component: str = ""
    rank: int = 99
    redirect: str = ""
    icon: str = ""
    extraIcon: str = ""
    enterTransition: str = ""
    leaveTransition: str = ""
    activePath: str = ""
    auths: str = ""
    frameSrc: str = ""
    frameLoading: bool = True
    keepAlive: bool = False
    hiddenTag: bool = False
    fixedTag: bool = False
    showLink: bool = True
    showParent: bool = False


def _apply(m: SysMenu, b: MenuBody):
    m.parent_id = b.parentId
    m.menu_type = b.menuType
    m.title = b.title
    m.name = b.name
    m.path = b.path
    m.component = b.component
    m.rank = b.rank
    m.redirect = b.redirect
    m.icon = b.icon
    m.extra_icon = b.extraIcon
    m.enter_transition = b.enterTransition
    m.leave_transition = b.leaveTransition
    m.active_path = b.activePath
    m.auths = b.auths
    m.frame_src = b.frameSrc
    m.frame_loading = int(b.frameLoading)
    m.keep_alive = int(b.keepAlive)
    m.hidden_tag = int(b.hiddenTag)
    m.fixed_tag = int(b.fixedTag)
    m.show_link = int(b.showLink)
    m.show_parent = int(b.showParent)


@router.post("/menu", dependencies=[Depends(get_current_user)])
async def list_menus(session: AsyncSession = Depends(get_session)):
    menus = list((await session.scalars(select(SysMenu).order_by(SysMenu.rank, SysMenu.id))).all())
    return ok([menu_to_dict(m) for m in menus])


@router.post("/menu/create", dependencies=[Depends(get_current_user)])
async def create_menu(body: MenuBody, session: AsyncSession = Depends(get_session)):
    m = SysMenu()
    _apply(m, body)
    session.add(m)
    await session.commit()
    return ok()


@router.put("/menu/{menu_id}", dependencies=[Depends(get_current_user)])
async def update_menu(menu_id: int, body: MenuBody, session: AsyncSession = Depends(get_session)):
    m = await session.scalar(select(SysMenu).where(SysMenu.id == menu_id))
    if not m:
        raise HTTPException(status_code=404, detail={"code": 404, "message": "菜单不存在"})
    _apply(m, body)
    await session.commit()
    return ok()


@router.delete("/menu/{menu_id}", dependencies=[Depends(get_current_user)])
async def delete_menu(menu_id: int, session: AsyncSession = Depends(get_session)):
    # 级联删除下级菜单
    ids = [menu_id]
    while True:
        children = list(
            (await session.scalars(select(SysMenu.id).where(SysMenu.parent_id.in_(ids)))).all()
        )
        if not children:
            break
        ids.extend(children)
    await session.execute(delete(SysRoleMenu).where(SysRoleMenu.menu_id.in_(ids)))
    await session.execute(delete(SysMenu).where(SysMenu.id.in_(ids)))
    await session.commit()
    return ok()
