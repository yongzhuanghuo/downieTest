"""去水印：ffmpeg 抽帧 + 分段去水印（delogo / blur / crop）。

坐标约定：前端按百分比 (0-1) 传框，这里用 ffprobe 拿原视频宽高换算成像素坐标。
移动水印 = 多个 segment，每段套各自的框，最后统一重编码 + concat 合并。
"""
import json
import subprocess
import uuid
from pathlib import Path
from typing import Callable, List, Optional

from .. import config
from ..schemas import Box, Segment

# 统一重编码参数，保证 concat 时各片段编码一致
_ENCODE = ["-c:v", "libx264", "-preset", "veryfast", "-crf", "23", "-c:a", "aac"]


def _run(cmd: List[str]) -> None:
    subprocess.run(cmd, check=True, capture_output=True, text=True)


def get_video_info(video_path: Path) -> tuple[int, int, float]:
    """ffprobe 返回 (宽, 高, 时长秒)。"""
    cmd = [
        "ffprobe", "-v", "error",
        "-select_streams", "v:0",
        "-show_entries", "stream=width,height:format=duration",
        "-of", "json", str(video_path),
    ]
    out = subprocess.run(cmd, check=True, capture_output=True, text=True)
    data = json.loads(out.stdout)
    stream = data["streams"][0]
    width = int(stream["width"])
    height = int(stream["height"])
    duration = float(data["format"]["duration"])
    return width, height, duration


def extract_frame(video_path: Path, timestamp: float, output_path: Path) -> Path:
    """抽出指定时间点的一帧（精确 seek，支持任意时间戳）。"""
    cmd = [
        "ffmpeg", "-y",
        "-i", str(video_path),
        "-ss", str(timestamp),
        "-frames:v", "1",
        "-q:v", "2",
        str(output_path),
    ]
    _run(cmd)
    return output_path


def _px(box: Box, width: int, height: int) -> tuple[int, int, int, int]:
    """百分比坐标换算像素，并 clamp 到画面内。"""
    x = max(0, min(int(box.x * width), width - 1))
    y = max(0, min(int(box.y * height), height - 1))
    w = max(1, min(int(box.w * width), width - x))
    h = max(1, min(int(box.h * height), height - y))
    return x, y, w, h


def _build_filter(width: int, height: int, boxes: List[Box], method: str) -> str:
    """按处理方式构造 ffmpeg -vf 滤镜串。"""
    method = method or "delogo"
    if method == "delogo":
        parts = []
        for b in boxes:
            x, y, w, h = _px(b, width, height)
            parts.append(f"delogo=x={x}:y={y}:w={w}:h={h}")
        return ",".join(parts)

    if method == "blur":
        if len(boxes) > 1:
            raise NotImplementedError("V1 blur 仅支持单框，多框请用 delogo")
        x, y, w, h = _px(boxes[0], width, height)
        return (
            f"split=2[bg][fg];"
            f"[fg]crop={w}:{h}:{x}:{y},boxblur=20:1[bfg];"
            f"[bg][bfg]overlay={x}:{y}"
        )

    if method == "crop":
        # 裁掉水印所在边：需按框位置判断裁剪方向，V1 暂不实现
        raise NotImplementedError("V1 暂未实现 crop 裁边，请用 delogo 或 blur")

    raise ValueError(f"未知去水印方式: {method}")


def apply_delogo(
    video_path: Path,
    segments: List[Segment],
    output_path: Path,
    progress_callback: Optional[Callable[[float], None]] = None,
) -> Path:
    """分段去水印并合并输出。

    流程：把整段视频按 segments 切成若干区间，标记段套滤镜、空隙段原样，
    全部统一重编码后 concat 合并（保证编码一致）。
    progress_callback 每处理完一段回调一次进度（0-100）。
    """
    if not segments:
        raise ValueError("segments 不能为空")

    width, height, duration = get_video_info(video_path)
    segments = sorted(segments, key=lambda s: s.start)

    tmp_dir = config.TEMP_DIR

    # 先收集所有待处理段（含空隙段），用于计算进度
    jobs: List[tuple] = []
    cursor = 0.0
    for seg in segments:
        start = max(0.0, seg.start)
        end = min(duration, seg.end)
        if end <= start:
            continue
        if cursor < start:
            jobs.append((cursor, start, None))  # 空隙段：原样
        vf = _build_filter(width, height, seg.boxes, seg.boxes[0].method if seg.boxes else "delogo")
        jobs.append((start, end, vf))  # 标记段：套滤镜
        cursor = end
    if cursor < duration:
        jobs.append((cursor, duration, None))  # 末尾空隙

    if not jobs:
        raise ValueError("有效时间段为空")

    total = len(jobs)

    def _transcode(start: float, end: float, vf: str | None) -> Path:
        out = tmp_dir / f"{uuid.uuid4().hex}.mp4"
        cmd = ["ffmpeg", "-y", "-ss", str(start), "-to", str(end), "-i", str(video_path)]
        if vf:
            cmd += ["-vf", vf]
        cmd += _ENCODE + [str(out)]
        _run(cmd)
        return out

    parts: List[Path] = []
    for i, (start, end, vf) in enumerate(jobs):
        parts.append(_transcode(start, end, vf))
        if progress_callback:
            progress_callback((i + 1) / total * 90.0)  # 分段占 90%

    if len(parts) == 1:
        parts[0].replace(output_path)
        if progress_callback:
            progress_callback(100.0)
        return output_path

    # concat 合并
    concat_list = tmp_dir / f"{uuid.uuid4().hex}.txt"
    concat_list.write_text("".join(f"file '{p}'\n" for p in parts))
    cmd = ["ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", str(concat_list),
           "-c", "copy", str(output_path)]
    _run(cmd)

    for p in parts:
        p.unlink(missing_ok=True)
    concat_list.unlink(missing_ok=True)
    if progress_callback:
        progress_callback(100.0)
    return output_path
