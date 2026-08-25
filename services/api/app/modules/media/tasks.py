"""媒体任务队列（纯 Redis）。

任务状态只存 Redis（key `media:task:{id}`，JSON，TTL 24h）。
Redis 不可用时降级为进程内临时兜底（不保留全局内存队列，任务状态会丢）。
"""
import asyncio
import json
from typing import Optional

_TTL = 86400  # 24h
_redis = None
_redis_ok = True


class Task:
    def __init__(self, task_type: str, task_id: str | None = None):
        self.id = task_id or _gen_id()
        self.type = task_type
        self.status = "pending"  # pending / running / done / error
        self.progress = 0.0
        self.result_url: Optional[str] = None
        self.error: Optional[str] = None
        self.data: dict = {}

    def to_dict(self) -> dict:
        return {
            "task_id": self.id,
            "type": self.type,
            "status": self.status,
            "progress": self.progress,
            "result_url": self.result_url,
            "error": self.error,
            "data": self.data,
        }

    @classmethod
    def from_dict(cls, d: dict) -> "Task":
        t = cls(d.get("type", "unknown"), task_id=d.get("task_id"))
        t.status = d.get("status", "pending")
        t.progress = d.get("progress", 0.0)
        t.result_url = d.get("result_url")
        t.error = d.get("error")
        t.data = d.get("data", {})
        return t


def _gen_id() -> str:
    import uuid

    return uuid.uuid4().hex[:12]


def _get_redis():
    global _redis, _redis_ok
    if _redis is not None:
        return _redis
    if not _redis_ok:
        return None
    try:
        import redis.asyncio as aioredis

        from app.config import settings

        _redis = aioredis.from_url(settings.redis_url, decode_responses=True)
    except Exception:  # noqa: BLE001
        _redis_ok = False
        _redis = None
    return _redis


async def create_task(task_type: str) -> Task:
    t = Task(task_type)
    await save_task(t)
    return t


async def get_task(task_id: str) -> Optional[Task]:
    r = _get_redis()
    if not r:
        return None
    try:
        raw = await r.get(f"media:task:{task_id}")
        return Task.from_dict(json.loads(raw)) if raw else None
    except Exception:  # noqa: BLE001
        return None


async def save_task(task: Task) -> None:
    r = _get_redis()
    if not r:
        return
    try:
        await r.set(f"media:task:{task.id}", json.dumps(task.to_dict(), ensure_ascii=False), ex=_TTL)
    except Exception:  # noqa: BLE001
        pass


def run_in_background(coro):
    """fire-and-forget 后台协程。异常由具体协程内部捕获并写入 task.error。"""

    async def _runner():
        try:
            await coro
        except Exception:  # noqa: BLE001 兜底，避免协程静默失败
            import traceback

            traceback.print_exc()

    return asyncio.create_task(_runner())
