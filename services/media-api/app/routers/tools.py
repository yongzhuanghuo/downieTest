"""视频工具：加水印 / 改 MD5 / 转 GIF。"""
import asyncio
import logging
import uuid
from pathlib import Path

import aiofiles
from fastapi import APIRouter, File, HTTPException, UploadFile

from .. import config
from ..schemas import GifProcessRequest, Md5ProcessRequest, TaskResponse, WatermarkProcessRequest
from ..services import video_tools
from ..tasks import create_task, run_in_background

logger = logging.getLogger("app.tools")

router = APIRouter()

# 复用 delogo 的上传文件映射（video_id/image_id -> 本地路径）
from .delogo import _uploads as _files


def _resolve(fid: str) -> Path:
    p = _files.get(fid)
    if not p or not p.exists():
        raise HTTPException(status_code=404, detail="文件不存在或已过期")
    return p


@router.post("/upload/image")
async def upload_image(file: UploadFile = File(...)):
    """上传水印图片，返回 image_id。"""
    ext = Path(file.filename or "wm.png").suffix or ".png"
    img_id = uuid.uuid4().hex[:12]
    dest = config.TEMP_DIR / f"{img_id}{ext}"
    async with aiofiles.open(dest, "wb") as f:
        while chunk := await file.read(1024 * 1024):
            await f.write(chunk)
    _files[img_id] = dest
    return {"image_id": img_id, "url": f"/tmp/{dest.name}"}


@router.get("/fonts")
async def fonts():
    """返回可用的水印字体列表。"""
    return {"fonts": video_tools.list_fonts()}


@router.post("/watermark/process", response_model=TaskResponse)
async def watermark_process(req: WatermarkProcessRequest):
    video = _resolve(req.video_id)
    # 解析图片水印的 image_id -> 本地路径
    for el in req.elements:
        if el.type == "image" and el.image_id:
            el.image_path = str(_resolve(el.image_id))

    task = create_task("watermark")
    task.status = "running"
    out_name = f"{req.video_id}_wm.mp4"
    out_path = config.DOWNLOAD_DIR / out_name

    async def _run():
        try:
            await asyncio.to_thread(video_tools.add_watermark, video, out_path, req.elements)
            task.result_url = f"/files/{out_name}"
            task.status = "done"
            task.progress = 100.0
        except Exception as e:  # noqa: BLE001
            logger.exception("加水印失败")
            task.error = str(e)
            task.status = "error"

    run_in_background(_run())
    return TaskResponse(task_id=task.id)


@router.post("/md5/process", response_model=TaskResponse)
async def md5_process(req: Md5ProcessRequest):
    video = _resolve(req.video_id)
    task = create_task("md5")
    task.status = "running"
    out_name = f"{req.video_id}_md5.mp4"
    out_path = config.DOWNLOAD_DIR / out_name

    async def _run():
        try:
            before, after = await asyncio.to_thread(video_tools.change_md5, video, out_path)
            task.result_url = f"/files/{out_name}"
            task.data = {"before_md5": before, "after_md5": after}
            task.status = "done"
            task.progress = 100.0
        except Exception as e:  # noqa: BLE001
            logger.exception("改 MD5 失败")
            task.error = str(e)
            task.status = "error"

    run_in_background(_run())
    return TaskResponse(task_id=task.id)


@router.post("/gif/process", response_model=TaskResponse)
async def gif_process(req: GifProcessRequest):
    video = _resolve(req.video_id)
    task = create_task("gif")
    task.status = "running"
    out_name = f"{req.video_id}.gif"
    out_path = config.DOWNLOAD_DIR / out_name

    async def _run():
        try:
            await asyncio.to_thread(
                video_tools.to_gif, video, out_path, req.start, req.end, req.fps, req.width
            )
            task.result_url = f"/files/{out_name}"
            task.status = "done"
            task.progress = 100.0
        except Exception as e:  # noqa: BLE001
            logger.exception("转 GIF 失败")
            task.error = str(e)
            task.status = "error"

    run_in_background(_run())
    return TaskResponse(task_id=task.id)
