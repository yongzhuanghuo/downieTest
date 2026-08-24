import asyncio
import logging

from fastapi import APIRouter, HTTPException

from ..schemas import ParseRequest, ParseResponse
from ..services import ytdlp

logger = logging.getLogger("app.parse")

router = APIRouter()


def _friendly_error(msg: str) -> str:
    """把技术错误转成用户能看懂的提示。"""
    m = msg.lower()
    if "unsupported" in m:
        return "不支持该链接，请确认链接是否正确"
    if "not found" in m or "404" in m:
        return "视频不存在或已被删除"
    if "private" in m or "members only" in m or "premium" in m:
        return "该视频需要会员或登录才能访问"
    if "validation error" in m or "int_from_float" in m:
        return "解析结果异常，请稍后重试"
    return f"解析失败：{msg}"


@router.post("/parse", response_model=ParseResponse)
async def parse_video(req: ParseRequest):
    """解析视频链接，返回标题/封面/作者/时长/清晰度列表。"""
    try:
        return await asyncio.to_thread(ytdlp.parse, req.url)
    except Exception as e:  # noqa: BLE001 解析失败统一 422
        logger.exception("解析失败: %s", req.url)  # 完整堆栈打到控制台
        raise HTTPException(status_code=422, detail=_friendly_error(str(e)))
