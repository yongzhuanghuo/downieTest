"""B站专用解析：走 api.bilibili.com，绕开被 WAF 拦的网页。

yt-dlp 的 B站 extractor 第一步是下载 www.bilibili.com 的视频页拿 __INITIAL_STATE__，
而机房 IP 请求 www 会被 WAF 直接返回 412（家宽通常放行，所以本地开发发现不了）。
api.bilibili.com 不走那层 WAF，元信息和播放地址都能从这里拿到。

清晰度受账号限制，与走不走 API 无关：未登录最高 480P，要 1080P 得配 YTDLP_COOKIES。
"""
import hashlib
import logging
import re
from pathlib import Path
from typing import Callable, Optional
from urllib import request as urlrequest

import requests

from app import config
from app.schemas import FormatInfo, ParseResponse

logger = logging.getLogger("app.bilibili")

_UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36"
)
# 调 API 时只带 UA，千万别加 Referer：
# 实测「浏览器 UA + www Referer + 无 cookie」正是 B站 WAF 判定伪装爬虫的特征，必 412。
# 单独带 UA 或单独带 Referer 都放行，组合才拦。默认的 python-urllib UA 也在黑名单里。
_API_HEADERS = {"User-Agent": _UA}
# 下载直链必须带 Referer，实测不带直接 403
_DL_HEADERS = {"User-Agent": _UA, "Referer": "https://www.bilibili.com/"}

# format_id 前缀，供 ytdlp.download 分派到这里。
# 不能靠域名判断：直链在 *.bilivideo.com 和第三方 PCDN（*.edge.mountaintoys.cn）之间随机漂。
DL_PREFIX = "bili|"

# B站 qn 值 → 竖直分辨率，用于前端排序和展示
_QN_HEIGHT = {6: 240, 16: 360, 32: 480, 64: 720, 74: 720, 80: 1080,
              112: 1080, 116: 1080, 120: 2160, 125: 2160, 126: 2160, 127: 4320}

_BV_RE = re.compile(r"/(?:video/)?(BV[0-9A-Za-z]{10})")
_AV_RE = re.compile(r"/(?:video/)?av(\d+)", re.I)


def _video_id(url: str) -> tuple[str, str]:
    """从链接提取 (参数名, 值)，返回 ('bvid', 'BVxxx') 或 ('aid', '123')。

    b23.tv 短链先解析出 Location，只读重定向目标，不真去请求 www（那会 412）。
    """
    if "b23.tv" in url:
        resp = requests.head(url, headers=_API_HEADERS, allow_redirects=False, timeout=15)
        url = resp.headers.get("Location") or url

    m = _BV_RE.search(url)
    if m:
        return "bvid", m.group(1)
    m = _AV_RE.search(url)
    if m:
        return "aid", m.group(1)
    raise ValueError("链接里没有找到 BV 号或 av 号")


def _api(path: str, params: dict) -> dict:
    """调 api.bilibili.com，返回 data 字段。"""
    resp = requests.get(f"https://api.bilibili.com{path}", params=params,
                        headers=_API_HEADERS, timeout=20)
    resp.raise_for_status()
    body = resp.json()
    if body.get("code") != 0:
        raise RuntimeError(f"B站接口 {path} 返回 {body.get('code')}: {body.get('message')}")
    return body.get("data") or {}


def parse(url: str) -> ParseResponse:
    """解析 B站 链接，返回标题/封面/作者/时长/清晰度列表。"""
    key, vid = _video_id(url)
    logger.info("B站解析: %s=%s", key, vid)

    info = _api("/x/web-interface/view", {key: vid})
    cid = info.get("cid")
    if not cid:
        raise RuntimeError("接口未返回 cid，可能是番剧或已下架视频")

    # qn=80 是"尽量给到 1080P"，B站按账号权限降级返回。fnval=1 拿整合 mp4，省掉 ffmpeg 合并
    # ponytail: 只取当前权限下的最高一档；要让用户挑清晰度就对 accept_quality 逐个请求
    play = _api("/x/player/playurl",
                {key: vid, "cid": cid, "qn": 80, "fnval": 1, "fourk": 1})
    durl = play.get("durl") or []
    if not durl:
        raise RuntimeError("接口未返回播放地址，该视频可能需要大会员")

    qn = play.get("quality") or 32
    height = _QN_HEIGHT.get(qn, 480)
    desc = next((f.get("new_description") or f.get("display_desc")
                 for f in play.get("support_formats") or [] if f.get("quality") == qn),
                f"{height}P")

    formats = [FormatInfo(
        format_id=DL_PREFIX + durl[0]["url"],
        ext="mp4",
        resolution=f"{height}p",
        height=height,
        filesize=durl[0].get("size"),
        note=desc,
    )]

    title = info.get("title") or ""
    logger.info("B站解析成功: 标题=%s | 作者=%s | 清晰度=%s",
                title, (info.get("owner") or {}).get("name"), desc)

    return ParseResponse(
        title=title,
        cover=info.get("pic"),
        author=(info.get("owner") or {}).get("name"),
        duration=info.get("duration"),
        formats=formats,
    )


def download(direct_url: str, progress_hook: Optional[Callable[[dict], None]] = None) -> Path:
    """下载 B站 直链（防盗链要求带 Referer），返回本地路径。接受带不带 DL_PREFIX 都行。"""
    direct_url = direct_url.removeprefix(DL_PREFIX)
    out_path = config.DOWNLOAD_DIR / f"bili_{hashlib.md5(direct_url.encode()).hexdigest()[:12]}.mp4"
    req = urlrequest.Request(direct_url, headers=_DL_HEADERS)
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
    logger.info("B站下载完成: %s", out_path.name)
    return out_path


if __name__ == "__main__":  # 自检：URL 提取是这里唯一容易写错的纯逻辑
    assert _video_id("https://www.bilibili.com/video/BV17b8z6QEUQ/?share_source=copy_web") == ("bvid", "BV17b8z6QEUQ")
    assert _video_id("https://www.bilibili.com/video/av170001") == ("aid", "170001")
    assert _QN_HEIGHT[80] == 1080
    # format_id 加了前缀，download() 必须能剥回原始直链
    assert (DL_PREFIX + "https://x.cn/a.mp4").removeprefix(DL_PREFIX) == "https://x.cn/a.mp4"
    try:
        _video_id("https://www.bilibili.com/bangumi/play/ss12345")
    except ValueError:
        pass
    else:
        raise AssertionError("番剧链接应当报错")
    print("OK")
