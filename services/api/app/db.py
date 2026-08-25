"""数据库访问层（SQLAlchemy 2.x async + aiomysql）。

提供 async engine / sessionmaker / get_session 依赖。
所有授权相关查询走这里，事务边界由调用方用 async with 控制。
"""
from collections.abc import AsyncIterator

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase

from .config import settings


class Base(DeclarativeBase):
    pass


engine = create_async_engine(
    settings.database_url,
    pool_size=10,
    max_overflow=5,
    pool_recycle=3600,
    pool_pre_ping=True,
)

SessionLocal = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)


async def get_session() -> AsyncIterator[AsyncSession]:
    async with SessionLocal() as session:
        yield session
