"""抖音专用解析：纯 requests + a_bogus 签名。

流程：短链展开拿 aweme_id → 接口拿 ttwid → UUID 模拟 msToken →
node 生成 a_bogus（douyin_sign 算法）→ 调 aweme/detail 拿视频数据 → 去水印。

不依赖浏览器（Playwright 无头浏览器会被抖音反爬拦截返回空响应）。
"""
import hashlib
import logging
import re
import uuid
from pathlib import Path
from typing import Callable, Optional
from urllib import request as urlrequest

import requests

from app import config
from app.schemas import FormatInfo, ParseResponse
from .douyin_sign import abogus

logger = logging.getLogger("app.douyin")

_DESKTOP_UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
)


def parse(url: str) -> ParseResponse:
    """解析抖音链接（含短链），返回视频信息（多清晰度 + 去水印）。"""
    aweme_id = _expand(url)
    logger.info("抖音解析: aweme_id=%s", aweme_id)

    ttwid = _get_ttwid()
    ms_token = _get_ms_token()

    # 构造 query + 生成 a_bogus（签名不含 a_bogus 本身）
    query = (
        f"device_platform=webapp&aid=6383&channel=channel_pc_web"
        f"&aweme_id={aweme_id}&msToken={ms_token}"
    )
    a_bogus = abogus.generate(query)

    params = {
        "device_platform": "webapp",
        "aid": "6383",
        "channel": "channel_pc_web",
        "aweme_id": aweme_id,
        "msToken": ms_token,
        "a_bogus": a_bogus,
    }
    headers = {
        "User-Agent": _DESKTOP_UA,
        "Referer": f"https://www.douyin.com/video/{aweme_id}",
    }
    resp = requests.get(
        "https://www.douyin.com/aweme/v1/web/aweme/detail/",
        params=params,
        headers=headers,
        cookies={"ttwid": ttwid},
        timeout=20,
    )
    data = resp.json()
    aweme = data.get("aweme_detail")
    if not aweme:
        raise RuntimeError(f"aweme/detail 响应无数据: {str(data)[:200]}")

    return _parse_aweme(aweme)


def _expand(url: str) -> str:
    """短链展开，提取 aweme_id。"""
    resp = requests.get(url, headers={"User-Agent": _DESKTOP_UA}, allow_redirects=True, timeout=15)
    final = resp.url
    m = re.search(r"/video/(\d+)", final) or re.search(r"(\d{15,})", final)
    if not m:
        raise RuntimeError("无法从链接提取 aweme_id")
    return m.group(1)


def _get_ttwid() -> str:
    """从 ttwid.bytedance.com 接口获取 ttwid。"""
    resp = requests.post(
        "https://ttwid.bytedance.com/ttwid/union/register/",
        json={
            "region": "cn",
            "aid": 1768,
            "needFid": False,
            "service": "www.ixigua.com",
            "migrate_info": {"ticket": "", "source": "node"},
            "cbUrlProtocol": "https",
            "union": True,
        },
        timeout=15,
    )
    ttwid = resp.cookies.get("ttwid")
    if not ttwid:
        raise RuntimeError("获取 ttwid 失败")
    return ttwid


def _get_ms_token() -> str:
    """msToken：抖音 web 对其校验较松，用 UUID（64 位唯一串）模拟即可。"""
    return uuid.uuid4().hex + uuid.uuid4().hex


def _parse_aweme(aweme: dict) -> ParseResponse:
    desc = aweme.get("desc") or ""
    author = (aweme.get("author") or {}).get("nickname") or ""
    duration_ms = aweme.get("duration") or 0
    video = aweme.get("video") or {}

    cover = _first_url(video.get("cover"))

    formats: list[FormatInfo] = []
    seen: set[str] = set()
    for b in video.get("bit_rate") or []:
        url = _no_watermark(_first_url(b.get("play_addr")))
        if not url or url in seen:
            continue
        seen.add(url)
        gear = b.get("gear_name") or "MP4"
        formats.append(FormatInfo(format_id=url, ext="mp4", resolution=gear, note=gear))

    play_addr = _no_watermark(_first_url(video.get("play_addr")))
    if play_addr and play_addr not in seen:
        formats.append(FormatInfo(format_id=play_addr, ext="mp4", resolution="原画", note="原画无水印"))

    duration = duration_ms // 1000 if duration_ms > 1000 else duration_ms

    logger.info("抖音解析成功: 标题=%s 作者=%s 格式数=%d", desc[:30], author, len(formats))
    return ParseResponse(
        title=desc or "抖音视频",
        cover=cover,
        author=author,
        duration=duration,
        formats=formats,
    )


def _first_url(addr) -> str:
    """从 play_addr/cover 结构里取第一个 URL（url_list[0] 或 uri）。"""
    if isinstance(addr, dict):
        url_list = addr.get("url_list") or []
        if url_list:
            return url_list[0]
        uri = addr.get("uri") or ""
        if uri:
            return uri
    return ""


def _no_watermark(url: str) -> str:
    return url.replace("/playwm/", "/play/")


def download(direct_url: str, progress_hook: Optional[Callable[[dict], None]] = None) -> Path:
    """直接下载抖音直链（带桌面 UA + Referer），返回本地路径。"""
    out_path = config.DOWNLOAD_DIR / f"douyin_{hashlib.md5(direct_url.encode()).hexdigest()[:12]}.mp4"
    req = urlrequest.Request(
        direct_url,
        headers={"User-Agent": _DESKTOP_UA, "Referer": "https://www.douyin.com/"},
    )
    with urlrequest.urlopen(req, timeout=60) as resp:
        total = int(resp.headers.get("Content-Length") or 0)
        done = 0
        with open(out_path, "wb") as f:
            while True:
                chunk = resp.read(1024 * 1024)
                if not chunk:
                    break
                f.write(chunk)
                done += len(chunk)
                if progress_hook and total:
                    progress_hook({"status": "downloading", "downloaded_bytes": done, "total_bytes": total})
    if progress_hook:
        progress_hook({"status": "finished"})
    logger.info("抖音下载完成: %s", out_path.name)
    return out_path
