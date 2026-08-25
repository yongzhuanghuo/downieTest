"""任务管理：读 Redis 里的媒体任务（media:task:*）。"""
import json

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.db import get_session
from ..serialize import ok
from .auth import get_current_user

router = APIRouter()


@router.post("/task/list", dependencies=[Depends(get_current_user)])
async def task_list(session: AsyncSession = Depends(get_session)):
    tasks = []
    try:
        import redis.asyncio as aioredis

        r = aioredis.from_url(settings.redis_url, decode_responses=True)
        keys = await r.keys("media:task:*")
        for k in keys:
            raw = await r.get(k)
            if raw:
                try:
                    tasks.append(json.loads(raw))
                except json.JSONDecodeError:
                    continue
        tasks.sort(key=lambda t: t.get("task_id", ""), reverse=True)
        await r.aclose()
    except Exception:  # noqa: BLE001 Redis 不可用则返回空
        tasks = []
    return ok({"list": tasks, "total": len(tasks)})
