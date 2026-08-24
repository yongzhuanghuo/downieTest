"""Pydantic 请求/响应模型。"""
from typing import List, Optional

from pydantic import BaseModel


class ParseRequest(BaseModel):
    url: str


class FormatInfo(BaseModel):
    format_id: str
    ext: str = ""
    resolution: str = ""  # 如 "1920x1080" / "audio"
    height: Optional[int] = None
    filesize: Optional[int] = None  # bytes，可能未知
    note: str = ""  # 展示文案，如 "1080p" / "仅音频"


class ParseResponse(BaseModel):
    title: str
    cover: Optional[str] = None
    author: Optional[str] = None
    duration: Optional[float] = None  # 秒，B站等平台可能是小数（如 125.589）
    formats: List[FormatInfo] = []


class DownloadRequest(BaseModel):
    url: str
    format_id: str


class TaskResponse(BaseModel):
    task_id: str


class TaskStatus(BaseModel):
    task_id: str
    status: str  # pending / running / done / error
    progress: float  # 0-100
    result_url: Optional[str] = None
    error: Optional[str] = None


class Box(BaseModel):
    """水印框，坐标为相对预览帧的百分比 (0-1)。"""
    x: float
    y: float
    w: float
    h: float
    method: str = "delogo"  # delogo / crop / blur


class Segment(BaseModel):
    """一个时间段内的水印框集合（移动水印 = 多个 segment）。"""
    start: float  # 秒
    end: float  # 秒
    boxes: List[Box] = []


class DelogoFrameRequest(BaseModel):
    video_id: str
    timestamp: float


class DelogoProcessRequest(BaseModel):
    video_id: str
    segments: List[Segment]


class WatermarkElement(BaseModel):
    type: str = "text"  # text / image
    # 文字参数
    text: str = ""
    size: int = 24  # 字号
    color: str = "#ffffff"  # 颜色 hex
    opacity: float = 1.0  # 0-1
    font_id: int = 0
    bold: bool = False
    italic: bool = False
    shadow: bool = False
    outline: bool = False
    tile: bool = False  # 平铺
    # 通用
    x: float = 0.5  # 百分比坐标
    y: float = 0.5
    angle: float = 0.0  # 旋转角度 -180~180
    # 图片参数
    image_id: Optional[str] = None
    image_scale: float = 1.0  # 图片缩放倍数
    image_path: Optional[str] = None  # 后端解析后的图片路径


class WatermarkProcessRequest(BaseModel):
    video_id: str
    elements: List[WatermarkElement]


class Md5ProcessRequest(BaseModel):
    video_id: str


class GifProcessRequest(BaseModel):
    video_id: str
    start: float
    end: float
    fps: int = 10
    width: int = 480
