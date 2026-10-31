"""管理后台路由聚合（Pure-Admin 契约）。

所有接口统一响应 {code:0, message, data}。
挂载方式：app.include_router(router)，无 prefix（路径自含 /login /user 等）。
"""
from fastapi import APIRouter, Depends

from app.security import require_admin

from .routers import auth, cards, depts, menus, roles, tasks, users

router = APIRouter()
# 登录 / 刷新 / 动态菜单不要求 admin 角色（普通账号也能登录看菜单）；
# 其余管理接口统一要求有效 JWT 且具备 admin 角色。
router.include_router(auth.router)
router.include_router(users.router, dependencies=[Depends(require_admin)])
router.include_router(roles.router, dependencies=[Depends(require_admin)])
router.include_router(menus.router, dependencies=[Depends(require_admin)])
router.include_router(depts.router, dependencies=[Depends(require_admin)])
router.include_router(cards.router, dependencies=[Depends(require_admin)])
router.include_router(tasks.router, dependencies=[Depends(require_admin)])
