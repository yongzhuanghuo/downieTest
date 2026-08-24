"""极简内存任务队列（V1 用，后续替换 Celery + Redis）。

任务状态放在进程内存字典里，前端轮询 GET /api/task/{id} 拿进度。
进程重启任务丢失，V1 可接受。
"""
import asyncio
from typing import Dict, Optional


class Task:
    def __init__(self, task_type: str):
        self.id = _gen_id()
        self.type = task_type
        self.status = "pending"  # pending / running / done / error
        self.progress = 0.0
        self.result_url: Optional[str] = None
        self.error: Optional[str] = None
        self.data: dict = {}  # 额外结果数据（如 md5 前后值）

    def to_dict(self) -> dict:
        return {
            "task_id": self.id,
            "status": self.status,
            "progress": self.progress,
            "result_url": self.result_url,
            "error": self.error,
            "data": self.data,
        }


_tasks: Dict[str, Task] = {}


def _gen_id() -> str:
    import uuid

    return uuid.uuid4().hex[:12]


def create_task(task_type: str) -> Task:
    t = Task(task_type)
    _tasks[t.id] = t
    return t


def get_task(task_id: str) -> Optional[Task]:
    return _tasks.get(task_id)


def run_in_background(coro):
    """fire-and-forget 后台协程。异常由具体协程内部捕获并写入 task.error。"""
    async def _runner():
        try:
            await coro
        except Exception:  # noqa: BLE001 兜底，避免协程静默失败
            import traceback

            traceback.print_exc()

    return asyncio.create_task(_runner())
