"""yt-dlp 封装：解析视频信息 + 下载。

yt-dlp 是主力解析引擎（1700+ 提取器，覆盖 1000+ 站点）。
抖音 / B站 / 视频号等强反爬站点后续在此层叠加专用解析器（见 CLAUDE.md「平台策略」）。
"""
import logging
import re
from functools import lru_cache
from pathlib import Path
from typing import Callable, Optional

import requests
import yt_dlp

from app import config
from app.schemas import FormatInfo, ParseResponse

logger = logging.getLogger("app.ytdlp")

# 下载时统一合并成 mp4（B站等音视频分离场景依赖 ffmpeg 合并）
_MERGE_FORMAT = "mp4"

# 抖音域名（走 Playwright 专用解析，见 douyin.py）
_DOUYIN_HOSTS = ("douyin.com", "iesdouyin.com")

# B站域名。其 WAF 对不带 buvid3 的请求返回 412，机房 IP 尤其严格（家宽通常放行）
_BILI_HOSTS = ("bilibili.com", "b23.tv")


@lru_cache(maxsize=1)
def _bili_buvid3() -> str:
    """取一个匿名 buvid3（设备指纹）。这个接口不需要登录态，也不绑定任何账号。

    ponytail: 进程内永久缓存，buvid3 有效期以月计；真过期了重启进程重取即可。
    """
    resp = requests.get("https://api.bilibili.com/x/frontend/finger/spi", timeout=10)
    resp.raise_for_status()
    return resp.json()["data"]["b_3"]

# 从分享文案提取 URL / 标题的正则（手机端复制的常带标题/话题/提示语）
_URL_RE = re.compile(r"https?://[^\s一-鿿]+")
_TAG_RE = re.compile(r"#\s*([^#\s][^#]*)")


def _extract_url(text: str) -> str:
    """从整段分享文案里提取第一个 URL。"""
    m = _URL_RE.search(text.strip())
    return m.group(0) if m else ""


def _extract_title(text: str) -> str:
    """提取 # 话题文字拼成的兜底标题（URL 及其后的提示语不计入）。"""
    m = _URL_RE.search(text)
    if m:
        text = text[: m.start()]
    return " ".join(t.strip() for t in _TAG_RE.findall(text))


def _base_opts(extra: dict, url: str = "") -> dict:
    opts = {
        "quiet": True,
        "no_warnings": True,
        "noplaylist": True,
        "socket_timeout": 30,
        "logger": logger,  # 让 yt-dlp 的错误日志进 python logging
    }
    # 代理：全局 YTDLP_PROXY 配置。境内部署想抓 YouTube 时填代理地址。
    if config.settings.ytdlp_proxy:
        opts["proxy"] = config.settings.ytdlp_proxy
    # cookies：B站等站点对机房 IP 无 cookie 的请求返回 412 风控，YTDLP_COOKIES 指向导出的 cookies.txt
    cookies = config.settings.ytdlp_cookies
    if cookies:
        if Path(cookies).is_file():
            opts["cookiefile"] = cookies
        else:  # 路径写错就静默不带 cookie，别让所有解析直接挂
            logger.warning("YTDLP_COOKIES 指向的文件不存在，已忽略: %s", cookies)
    # B站：补一个匿名 buvid3 绕过 412 风控。配了 cookiefile 就不必（里面本就带 buvid3）
    if not opts.get("cookiefile") and any(h in url for h in _BILI_HOSTS):
        try:
            opts["http_headers"] = {"Cookie": f"buvid3={_bili_buvid3()}"}
        except Exception as e:  # noqa: BLE001 取不到就照常请求，让 yt-dlp 报真实错误
            logger.warning("获取 buvid3 失败，B站可能返回 412: %s", e)
    opts.update(extra)
    return opts


def parse(text: str) -> ParseResponse:
    """解析链接（或整段分享文案），返回标题/封面/作者/时长/清晰度列表。"""
    raw = text.strip()
    url = _extract_url(raw)
    fallback_title = _extract_title(raw)
    if not url:
        raise ValueError("未识别到视频链接，请复制包含链接的分享文本")

    logger.info("解析开始: %s -> 提取URL=%s", raw[:60], url)

    if any(h in url for h in _DOUYIN_HOSTS):
        from . import douyin

        result = douyin.parse(url)
        if not result.title:
            result.title = fallback_title
        return result

    opts = _base_opts({"skip_download": True}, url)
    with yt_dlp.YoutubeDL(opts) as ydl:
        info = ydl.extract_info(url, download=False)

    formats: list[FormatInfo] = []
    seen_height: set[int] = set()
    for f in info.get("formats", []):
        if f.get("vcodec") == "none":  # 纯音频轨，跳过（单独给「仅音频」选项）
            continue
        height = f.get("height")
        if not height or height in seen_height:
            continue
        seen_height.add(height)
        formats.append(
            FormatInfo(
                format_id=f.get("format_id", ""),
                ext=f.get("ext", ""),
                resolution=f"{f.get('width', 0)}x{height}",
                height=height,
                filesize=f.get("filesize"),
                note=f.get("format_note") or f"{height}p",
            )
        )

    formats.sort(key=lambda x: x.height or 0, reverse=True)

    # 仅音频选项：挑一个纯音频轨
    audio = next(
        (
            FormatInfo(format_id=f["format_id"], ext=f.get("ext", "m4a"),
                       resolution="audio", note="仅音频")
            for f in info.get("formats", [])
            if f.get("vcodec") == "none" and f.get("acodec") != "none"
        ),
        None,
    )
    if audio:
        formats.append(audio)

    title = info.get("title") or fallback_title
    logger.info("解析成功: %s | 标题=%s | 作者=%s | 格式数=%d",
                url, title, info.get("uploader") or info.get("channel"), len(formats))

    return ParseResponse(
        title=title,
        cover=info.get("thumbnail"),
        author=info.get("uploader") or info.get("channel"),
        duration=info.get("duration"),
        formats=formats,
    )


def download(
    url: str,
    format_id: str,
    progress_hook: Optional[Callable[[dict], None]] = None,
) -> Path:
    """下载并返回本地文件路径。

    format_id 为 parse 返回的某个清晰度。若选了纯视频轨（音视频分离），
    自动追加 bestaudio 并用 ffmpeg 合并，避免得到无声视频。
    """
    url = _extract_url(url) or url  # 兼容传入完整分享文本（含标题）
    if format_id.startswith("http"):  # 抖音直链，直接下载
        from . import douyin

        return douyin.download(format_id, progress_hook)

    if format_id.startswith("bestaudio"):
        fmt = format_id
    else:
        fmt = f"{format_id}+bestaudio/{format_id}"

    logger.info("下载开始: %s format=%s", url, fmt)
    outtmpl = str(config.DOWNLOAD_DIR / "%(title).80s [%(id)s].%(ext)s")
    hooks = [progress_hook] if progress_hook else []
    opts = _base_opts(
        {
            "format": fmt,
            "outtmpl": outtmpl,
            "merge_output_format": _MERGE_FORMAT,
            "progress_hooks": hooks,
        },
        url,
    )

    with yt_dlp.YoutubeDL(opts) as ydl:
        info = ydl.extract_info(url, download=True)

    filepath = None
    if info.get("requested_downloads"):
        filepath = info["requested_downloads"][0].get("filepath")
    if not filepath:
        filepath = info.get("filepath")
    if not filepath:
        raise RuntimeError("下载完成但未找到输出文件")

    logger.info("下载完成: %s -> %s", url, filepath)
    return Path(filepath)
