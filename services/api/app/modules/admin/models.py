"""管理后台 RBAC ORM 模型（对接 Pure-Admin 前端字段）。

JSON 层用 camelCase，DB 层 snake_case，序列化由各 router 显式完成。
布尔/状态字段 DB 存 tinyint，序列化时转 bool/数字。
"""
from sqlalchemy import BigInteger, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base


class SysDept(Base):
    __tablename__ = "sys_depts"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    parent_id: Mapped[int] = mapped_column(BigInteger, default=0)
    name: Mapped[str] = mapped_column(String(50))
    sort: Mapped[int] = mapped_column(Integer, default=0)
    phone: Mapped[str | None] = mapped_column(String(20), nullable=True)
    principal: Mapped[str | None] = mapped_column(String(50), nullable=True)
    email: Mapped[str | None] = mapped_column(String(100), nullable=True)
    status: Mapped[int] = mapped_column(Integer, default=1)
    dept_type: Mapped[int] = mapped_column("type", Integer, default=3)
    create_time: Mapped[int] = mapped_column(BigInteger, default=0)
    remark: Mapped[str | None] = mapped_column(String(255), nullable=True)


class SysRole(Base):
    __tablename__ = "sys_roles"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(50))
    code: Mapped[str] = mapped_column(String(50))
    status: Mapped[int] = mapped_column(Integer, default=1)
    remark: Mapped[str | None] = mapped_column(String(255), nullable=True)
    create_time: Mapped[int] = mapped_column(BigInteger, default=0)
    update_time: Mapped[int] = mapped_column(BigInteger, default=0)


class SysUser(Base):
    __tablename__ = "sys_users"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    username: Mapped[str] = mapped_column(String(50))
    password_hash: Mapped[str] = mapped_column(String(255))
    nickname: Mapped[str | None] = mapped_column(String(50), nullable=True)
    avatar: Mapped[str | None] = mapped_column(String(255), nullable=True)
    sex: Mapped[int] = mapped_column(Integer, default=0)
    phone: Mapped[str | None] = mapped_column(String(20), nullable=True)
    email: Mapped[str | None] = mapped_column(String(100), nullable=True)
    status: Mapped[int] = mapped_column(Integer, default=1)
    dept_id: Mapped[int | None] = mapped_column(BigInteger, nullable=True)
    remark: Mapped[str | None] = mapped_column(String(255), nullable=True)
    create_time: Mapped[int] = mapped_column(BigInteger, default=0)
    update_time: Mapped[int] = mapped_column(BigInteger, default=0)


class SysMenu(Base):
    __tablename__ = "sys_menus"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    parent_id: Mapped[int] = mapped_column(BigInteger, default=0)
    menu_type: Mapped[int] = mapped_column(Integer, default=0)
    title: Mapped[str] = mapped_column(String(50))
    name: Mapped[str | None] = mapped_column(String(50), nullable=True)
    path: Mapped[str | None] = mapped_column(String(255), nullable=True)
    component: Mapped[str | None] = mapped_column(String(255), nullable=True)
    rank: Mapped[int] = mapped_column("rank", Integer, default=99)
    redirect: Mapped[str | None] = mapped_column(String(255), nullable=True)
    icon: Mapped[str | None] = mapped_column(String(50), nullable=True)
    extra_icon: Mapped[str | None] = mapped_column(String(50), nullable=True)
    enter_transition: Mapped[str | None] = mapped_column(String(50), nullable=True)
    leave_transition: Mapped[str | None] = mapped_column(String(50), nullable=True)
    active_path: Mapped[str | None] = mapped_column(String(255), nullable=True)
    auths: Mapped[str | None] = mapped_column(String(100), nullable=True)
    frame_src: Mapped[str | None] = mapped_column(String(255), nullable=True)
    frame_loading: Mapped[int] = mapped_column(Integer, default=1)
    keep_alive: Mapped[int] = mapped_column(Integer, default=0)
    hidden_tag: Mapped[int] = mapped_column(Integer, default=0)
    fixed_tag: Mapped[int] = mapped_column(Integer, default=0)
    show_link: Mapped[int] = mapped_column(Integer, default=1)
    show_parent: Mapped[int] = mapped_column(Integer, default=0)


class SysRoleMenu(Base):
    __tablename__ = "sys_role_menus"

    role_id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    menu_id: Mapped[int] = mapped_column(BigInteger, primary_key=True)


class SysUserRole(Base):
    __tablename__ = "sys_user_roles"

    user_id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    role_id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
