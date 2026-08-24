import asyncio
import uuid
from pathlib import Path

import aiofiles
from fastapi import APIRouter, File, HTTPException, UploadFile

from .. import config
from ..schemas import DelogoFrameRequest, DelogoProcessRequest, TaskResponse
from ..services import delogo as delogo_svc
from ..tasks import create_task, run_in_background

router = APIRouter()

# video_id -> 上传视频本地路径（内存映射，进程重启丢失，V1 可接受）
_uploads: dict[str, Path] = {}


def _resolve_video(video_id: str) -> Path:
    p = _uploads.get(video_id)
    if not p or not p.exists():
        raise HTTPException(status_code=404, detail="视频不存在或已过期")
    return p


@router.post("/delogo/preview")
async def delogo_preview(file: UploadFile = File(...)):
    """上传视频，返回 video_id + 可 seek 的播放源 URL。"""
    ext = Path(file.filename or "video.mp4").suffix or ".mp4"
    video_id = uuid.uuid4().hex[:12]
    dest = config.TEMP_DIR / f"{video_id}{ext}"

    async with aiofiles.open(dest, "wb") as f:
        while chunk := await file.read(1024 * 1024):
            await f.write(chunk)

    _uploads[video_id] = dest
    return {"video_id": video_id, "video_url": f"/tmp/{dest.name}"}


@router.post("/delogo/frame")
async def delogo_frame(req: DelogoFrameRequest):
    """按时间戳抽一帧，返回静帧图 URL 供前端框选。"""
    video = _resolve_video(req.video_id)
    frame_name = f"{req.video_id}_{int(req.timestamp * 1000)}.jpg"
    frame_path = config.FRAME_DIR / frame_name
    await asyncio.to_thread(delogo_svc.extract_frame, video, req.timestamp, frame_path)
    return {"frame_url": f"/tmp/frames/{frame_name}"}


@router.post("/delogo/process", response_model=TaskResponse)
async def delogo_process(req: DelogoProcessRequest):
    """提交去水印任务，返回 task_id。"""
    video = _resolve_video(req.video_id)
    task = create_task("delogo")
    task.status = "running"

    out_name = f"{req.video_id}_delogo.mp4"
    out_path = config.DOWNLOAD_DIR / out_name

    async def _run():
        def _on_progress(p: float) -> None:
            task.progress = round(p, 1)

        try:
            await asyncio.to_thread(
                delogo_svc.apply_delogo, video, req.segments, out_path, _on_progress
            )
            task.result_url = f"/files/{out_name}"
            task.status = "done"
            task.progress = 100.0
        except Exception as e:  # noqa: BLE001
            task.error = str(e)
            task.status = "error"

    run_in_background(_run())
    return TaskResponse(task_id=task.id)
