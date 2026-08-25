import asyncio
import uuid
from pathlib import Path

from fastapi import APIRouter, File, HTTPException, UploadFile

from app import config, oss
from app.limits import MEDIA_SEMAPHORE, UploadTooLarge, stream_to_file
from app.schemas import DelogoFrameRequest, DelogoProcessRequest, TaskResponse
from app.modules.media.services import delogo as delogo_svc
from app.modules.media.tasks import create_task, run_in_background, save_task

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

    try:
        await stream_to_file(file, dest)
    except UploadTooLarge:
        raise HTTPException(status_code=413, detail="文件超过大小限制")

    _uploads[video_id] = dest
    oss_url = await oss.upload_file(dest, f"tmp/{dest.name}")
    return {"video_id": video_id, "video_url": oss_url or f"/tmp/{dest.name}"}


@router.post("/delogo/frame")
async def delogo_frame(req: DelogoFrameRequest):
    """按时间戳抽一帧，返回静帧图 URL 供前端框选。"""
    video = _resolve_video(req.video_id)
    frame_name = f"{req.video_id}_{int(req.timestamp * 1000)}.jpg"
    frame_path = config.FRAME_DIR / frame_name
    async with MEDIA_SEMAPHORE:
        await asyncio.to_thread(delogo_svc.extract_frame, video, req.timestamp, frame_path)
    oss_url = await oss.upload_file(frame_path, f"tmp/frames/{frame_name}")
    return {"frame_url": oss_url or f"/tmp/frames/{frame_name}"}


@router.post("/delogo/process", response_model=TaskResponse)
async def delogo_process(req: DelogoProcessRequest):
    """提交去水印任务，返回 task_id。"""
    video = _resolve_video(req.video_id)
    task = await create_task("delogo")
    task.status = "running"
    await save_task(task)

    out_name = f"{req.video_id}_delogo.mp4"
    out_path = config.DOWNLOAD_DIR / out_name

    async def _run():
        def _on_progress(p: float) -> None:
            task.progress = round(p, 1)

        try:
            async with MEDIA_SEMAPHORE:
                await asyncio.to_thread(
                    delogo_svc.apply_delogo, video, req.segments, out_path, _on_progress
                )
            task.result_url = (await oss.upload_file(out_path, f"files/{out_name}")) or f"/files/{out_name}"
            task.status = "done"
            task.progress = 100.0
            await save_task(task)
        except Exception as e:  # noqa: BLE001
            task.error = str(e)
            task.status = "error"
            await save_task(task)

    run_in_background(_run())
    return TaskResponse(task_id=task.id)
