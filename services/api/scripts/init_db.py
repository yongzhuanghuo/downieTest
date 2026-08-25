"""建表 + 种子数据脚本（幂等）。

1. 读 sql/schema.sql 逐条执行（CREATE TABLE IF NOT EXISTS，可重复跑）。
2. 写入默认 RBAC 数据：超级管理员角色、菜单树、默认账号 admin。

用法：python scripts/init_db.py
前提：MySQL 已建库、.env 已配 DB_*；默认账号密码取 .env 的 ADMIN_PASSWORD（缺省 admin123）。
"""
import asyncio
import time
from pathlib import Path

import bcrypt
from sqlalchemy import select

from app.config import settings
from app.db import SessionLocal, engine
from app.modules.admin.models import SysMenu, SysRole, SysRoleMenu, SysUser, SysUserRole

SCHEMA_PATH = Path(__file__).resolve().parent.parent / "sql" / "schema.sql"

# (path, title, name, component, icon, rank, parent_path)
MENUS = [
    ("/system", "系统管理", "", "", "ri:settings-3-line", 1, None),
    ("/system/user", "用户管理", "SystemUser", "system/user/index", "ri:admin-line", 1, "/system"),
    ("/system/role", "角色管理", "SystemRole", "system/role/index", "ri:admin-fill", 2, "/system"),
    ("/system/menu", "菜单管理", "SystemMenu", "system/menu/index", "ep:menu", 3, "/system"),
    ("/system/dept", "部门管理", "SystemDept", "system/dept/index", "ri:git-branch-line", 4, "/system"),
    ("/card", "卡密管理", "Card", "card/index", "ri:coupon-3-line", 2, None),
    ("/task", "任务管理", "Task", "task/index", "ri:list-check-2", 3, None),
    ("/member", "会员管理", "Member", "member/index", "ri:vip-crown-line", 4, None),
]


async def _run():
    schema = SCHEMA_PATH.read_text(encoding="utf-8")
    statements = [s.strip() for s in schema.split(";") if s.strip()]
    async with engine.begin() as conn:
        for stmt in statements:
            await conn.exec_driver_sql(stmt)
    print(f"✅ 数据表已创建/更新（{len(statements)} 条语句）")

    async with SessionLocal() as session:
        # 1. 超级管理员角色
        role = await session.scalar(select(SysRole).where(SysRole.code == "admin"))
        if not role:
            role = SysRole(name="超级管理员", code="admin", status=1, remark="内置超管角色", create_time=now_ms(), update_time=now_ms())
            session.add(role)
            await session.flush()

        # 2. 菜单树
        menu_ids: dict[str, int] = {}
        for path, title, name, component, icon, rank, parent_path in MENUS:
            m = await session.scalar(select(SysMenu).where(SysMenu.path == path))
            if not m:
                m = SysMenu(
                    parent_id=menu_ids.get(parent_path, 0) if parent_path else 0,
                    menu_type=0,
                    title=title,
                    name=name,
                    path=path,
                    component=component,
                    rank=rank,
                    icon=icon,
                )
                session.add(m)
                await session.flush()
            menu_ids[path] = m.id

        # 3. 角色-菜单全量授权
        existing = set((await session.scalars(select(SysRoleMenu.menu_id).where(SysRoleMenu.role_id == role.id))).all())
        for mid in menu_ids.values():
            if mid not in existing:
                session.add(SysRoleMenu(role_id=role.id, menu_id=mid))

        # 4. 默认账号 admin
        user = await session.scalar(select(SysUser).where(SysUser.username == "admin"))
        if not user:
            password = settings.admin_password or "admin123"
            user = SysUser(
                username="admin",
                password_hash=bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode(),
                nickname="管理员",
                sex=0,
                status=1,
                create_time=now_ms(),
                update_time=now_ms(),
            )
            session.add(user)
            await session.flush()

        # 5. admin -> 超管角色
        has_ur = await session.scalar(select(SysUserRole).where(SysUserRole.user_id == user.id, SysUserRole.role_id == role.id))
        if not has_ur:
            session.add(SysUserRole(user_id=user.id, role_id=role.id))

        await session.commit()
    print("✅ 种子数据已写入（超级管理员角色 + 菜单树 + 默认账号 admin）")


def now_ms() -> int:
    return int(time.time() * 1000)


if __name__ == "__main__":
    asyncio.run(_run())
