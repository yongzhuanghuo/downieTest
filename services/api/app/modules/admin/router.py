"""管理后台路由聚合（Pure-Admin 契约）。

所有接口统一响应 {code:0, message, data}。
挂载方式：app.include_router(router)，无 prefix（路径自含 /login /user 等）。
"""
from fastapi import APIRouter

from .routers import auth, cards, depts, menus, roles, tasks, users

router = APIRouter()
router.include_router(auth.router)
router.include_router(users.router)
router.include_router(roles.router)
router.include_router(menus.router)
router.include_router(depts.router)
router.include_router(cards.router)
router.include_router(tasks.router)
