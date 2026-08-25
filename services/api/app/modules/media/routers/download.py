import asyncio
import logging

from fastapi import APIRouter, HTTPException

from app import oss
from app.schemas import DownloadRequest, TaskResponse, TaskStatus
from app.modules.media.services import ytdlp
from app.limits import MEDIA_SEMAPHORE
from app.modules.media.tasks import create_task, get_task, run_in_background, save_task

logger = logging.getLogger("app.download")

router = APIRouter()


@router.post("/download", response_model=TaskResponse)
async def download(req: DownloadRequest):
    """提交下载任务，返回 task_id，前端轮询 /api/task/{id} 拿进度。"""
    task = await create_task("download")
    task.status = "running"
    await save_task(task)

    def hook(d: dict) -> None:
        if d.get("status") == "downloading":
            total = d.get("total_bytes") or d.get("total_bytes_estimate") or 0
            done = d.get("downloaded_bytes", 0)
            if total:
                task.progress = round(done / total * 100, 1)
        elif d.get("status") == "finished":
            task.progress = 100.0

    async def _run():
        try:
            async with MEDIA_SEMAPHORE:
                path = await asyncio.to_thread(ytdlp.download, req.url, req.format_id, hook)
            task.result_url = (await oss.upload_file(path, f"files/{path.name}")) or f"/files/{path.name}"
            task.status = "done"
            task.progress = 100.0
            await save_task(task)
        except Exception as e:  # noqa: BLE001
            logger.exception("下载失败: %s", req.url)  # 完整堆栈打到控制台
            task.error = str(e)
            task.status = "error"
            await save_task(task)

    run_in_background(_run())
    return TaskResponse(task_id=task.id)


@router.get("/task/{task_id}", response_model=TaskStatus)
async def task_status(task_id: str):
    task = await get_task(task_id)
    if not task:
        raise HTTPException(status_code=404, detail="任务不存在")
    return TaskStatus(**task.to_dict())
