"""B站专用解析：走 api.bilibili.com，绕开被 WAF 拦的网页。

yt-dlp 的 B站 extractor 第一步是下载 www.bilibili.com 的视频页拿 __INITIAL_STATE__，
而机房 IP 请求 www 会被 WAF 直接返回 412（家宽通常放行，所以本地开发发现不了）。
api.bilibili.com 不走那层 WAF。

两个实测出来的关键点，改代码前先看清楚：

1. `try_look=1` 决定清晰度上限。不带它，未登录只给 480P；带上就有 1080P。
   这是 B站 的"未登录试看"开关，yt-dlp 也是靠它拿到 1080P 的。
2. 1080P 只存在于 dash（音视频分离，要 ffmpeg 合并）。durl 整合 MP4 封顶 720P，
   请求 qn=120 也会被降回 64，所以省不掉合并这一步。
"""
import logging
import re
import subprocess
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
# 调 API 只带 UA，千万别加 Referer：
# 实测「浏览器 UA + www Referer + 无 cookie」正是 WAF 判定伪装爬虫的特征，必 412。
# 单独带 UA 或单独带 Referer 都放行，组合才拦。默认的 python-urllib UA 也在黑名单里。
_API_HEADERS = {"User-Agent": _UA}
# 下载媒体流必须带 Referer，实测不带直接 403
_DL_HEADERS = {"User-Agent": _UA, "Referer": "https://www.bilibili.com/"}

# format_id 前缀，供 ytdlp.download 分派到这里。
# format_id 里存 视频号/cid/qn 而不是直链：直链几小时就过期，下载时重新换更可靠，
# 而且移动端要把 format_id 塞进页面跳转的 query，直链太长。
DL_PREFIX = "bili|"

# B站 qn 值 → 竖直分辨率
_QN_HEIGHT = {6: 240, 16: 360, 32: 480, 64: 720, 74: 720, 80: 1080,
              112: 1080, 116: 1080, 120: 2160, 125: 2160, 126: 2160, 127: 4320}

_BV_RE = re.compile(r"/(?:video/)?(BV[0-9A-Za-z]{10})")
_AV_RE = re.compile(r"/(?:video/)?av(\d+)", re.I)


def _video_id(url: str) -> tuple[str, str]:
    """从链接提取 (参数名, 值)，返回 ('bvid', 'BVxxx') 或 ('aid', '123')。

    b23.tv 短链只读重定向目标，不真去请求 www（那会 412）。
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


def _id_key(vid: str) -> str:
    """BV 号传 bvid，纯数字传 aid。"""
    return "bvid" if vid.upper().startswith("BV") else "aid"


def _api(path: str, params: dict) -> dict:
    """调 api.bilibili.com，返回 data 字段。"""
    resp = requests.get(f"https://api.bilibili.com{path}", params=params,
                        headers=_API_HEADERS, timeout=20)
    resp.raise_for_status()
    body = resp.json()
    if body.get("code") != 0:
        raise RuntimeError(f"B站接口 {path} 返回 {body.get('code')}: {body.get('message')}")
    return body.get("data") or {}


def _playurl(vid: str, cid: int) -> dict:
    """取 dash 播放信息。try_look=1 是拿到 1080P 的关键，别删。"""
    return _api("/x/player/playurl", {
        _id_key(vid): vid, "cid": cid, "qn": 120,
        "fnval": 4048,   # dash
        "fourk": 1,
        "try_look": 1,   # 未登录试看高清；去掉这个参数清晰度直接掉到 480P
    })


def _pick_video(dash: dict, qn: int) -> dict:
    """选指定清晰度的视频轨。同一档有 avc1/hvc1/av01 三种编码，优先 avc1 —— 兼容性最好，
    hvc1/av01 在部分安卓机和小程序里播不了。"""
    tracks = [v for v in dash.get("video") or [] if v.get("id") == qn]
    if not tracks:
        raise RuntimeError(f"该视频没有 qn={qn} 这一档，可能需要登录或大会员")
    return next((v for v in tracks if (v.get("codecs") or "").startswith("avc1")), tracks[0])


def parse(url: str) -> ParseResponse:
    """解析 B站 链接，返回标题/封面/作者/时长/清晰度列表。"""
    key, vid = _video_id(url)
    logger.info("B站解析: %s=%s", key, vid)

    info = _api("/x/web-interface/view", {key: vid})
    cid = info.get("cid")
    if not cid:
        raise RuntimeError("接口未返回 cid，可能是番剧或已下架视频")

    play = _playurl(vid, cid)
    dash = play.get("dash") or {}
    if not dash.get("video"):
        raise RuntimeError("接口未返回可用视频流，该视频可能需要大会员")

    # support_formats 是"这视频存在哪些档"，dash.video 才是"当前权限能拿到哪些"，以后者为准
    desc_of = {f["quality"]: (f.get("new_description") or f.get("display_desc") or "")
               for f in play.get("support_formats") or []}
    duration = info.get("duration") or 0

    formats: list[FormatInfo] = []
    for qn in sorted({v["id"] for v in dash["video"]}, reverse=True):
        track = _pick_video(dash, qn)
        height = track.get("height") or _QN_HEIGHT.get(qn, 0)
        # dash 不给文件大小，用码率 × 时长估算（含音频轨），前端只拿它显示个大概
        est = int((track.get("bandwidth", 0) + 130000) * duration / 8) if duration else None
        formats.append(FormatInfo(
            format_id=f"{DL_PREFIX}{vid}|{cid}|{qn}",
            ext="mp4",
            resolution=f"{track.get('width', 0)}x{height}",
            height=height,
            filesize=est,
            note=desc_of.get(qn) or f"{height}P",
        ))

    title = info.get("title") or ""
    logger.info("B站解析成功: 标题=%s | 作者=%s | 清晰度=%s",
                title, (info.get("owner") or {}).get("name"),
                [f.note for f in formats])

    return ParseResponse(
        title=title,
        cover=info.get("pic"),
        author=(info.get("owner") or {}).get("name"),
        duration=duration,
        formats=formats,
    )


def _stream(url: str, out: Path, hook, done: int, total: int) -> int:
    """流式下载单条媒体流，返回累计已下载字节（多条流共用一个总进度）。"""
    req = urlrequest.Request(url, headers=_DL_HEADERS)
    with urlrequest.urlopen(req, timeout=60) as resp, open(out, "wb") as f:
        while True:
            chunk = resp.read(1024 * 1024)
            if not chunk:
                break
            f.write(chunk)
            done += len(chunk)
            if hook and total:
                hook({"status": "downloading", "downloaded_bytes": done, "total_bytes": total})
    return done


def download(format_id: str, progress_hook: Optional[Callable[[dict], None]] = None) -> Path:
    """下载指定清晰度并合并音视频，返回本地 mp4 路径。

    format_id 形如 `bili|BV1xx|12345|80`（DL_PREFIX + 视频号 + cid + qn）。
    """
    vid, cid, qn = format_id.removeprefix(DL_PREFIX).split("|")
    cid, qn = int(cid), int(qn)

    dash = _playurl(vid, cid).get("dash") or {}
    video = _pick_video(dash, qn)
    audios = dash.get("audio") or []
    if not audios:
        raise RuntimeError("接口未返回音频流")
    audio = max(audios, key=lambda a: a.get("bandwidth", 0))

    tag = f"{vid}_{cid}_{qn}"
    vpath = config.TEMP_DIR / f"bili_{tag}.v.m4s"
    apath = config.TEMP_DIR / f"bili_{tag}.a.m4s"
    out_path = config.DOWNLOAD_DIR / f"bili_{tag}.mp4"

    total = (video.get("bandwidth", 0) + audio.get("bandwidth", 0)) // 8 * 30  # 粗估，只为进度条
    logger.info("B站下载: %s qn=%s", vid, qn)
    try:
        done = _stream(video["baseUrl"], vpath, progress_hook, 0, total)
        _stream(audio["baseUrl"], apath, progress_hook, done, total)
        # -c copy 只封装不转码，1080P 也就几秒
        subprocess.run(
            ["ffmpeg", "-y", "-i", str(vpath), "-i", str(apath), "-c", "copy", str(out_path)],
            check=True, capture_output=True, text=True,
        )
    except subprocess.CalledProcessError as e:
        raise RuntimeError(f"音视频合并失败: {e.stderr[-300:]}") from e
    finally:
        vpath.unlink(missing_ok=True)
        apath.unlink(missing_ok=True)

    if progress_hook:
        progress_hook({"status": "finished"})
    logger.info("B站下载完成: %s", out_path.name)
    return out_path


if __name__ == "__main__":  # 自检：纯逻辑部分，不联网
    assert _video_id("https://www.bilibili.com/video/BV17b8z6QEUQ/?share_source=copy_web") == ("bvid", "BV17b8z6QEUQ")
    assert _video_id("https://www.bilibili.com/video/av170001") == ("aid", "170001")
    assert _id_key("BV17b8z6QEUQ") == "bvid" and _id_key("170001") == "aid"

    # format_id 编解码往返，download() 的第一行依赖它
    fid = f"{DL_PREFIX}BV17b8z6QEUQ|41138913519|80"
    assert fid.removeprefix(DL_PREFIX).split("|") == ["BV17b8z6QEUQ", "41138913519", "80"]

    # 编码优先级：同一档必须挑中 avc1，挑错了部分安卓机播不了
    fake = {"video": [{"id": 80, "codecs": "hvc1.1.6.L150"}, {"id": 80, "codecs": "avc1.640032"},
                      {"id": 32, "codecs": "avc1.64001F"}]}
    assert _pick_video(fake, 80)["codecs"].startswith("avc1")
    try:
        _pick_video(fake, 120)
    except RuntimeError:
        pass
    else:
        raise AssertionError("不存在的清晰度应当报错")

    try:
        _video_id("https://www.bilibili.com/bangumi/play/ss12345")
    except ValueError:
        pass
    else:
        raise AssertionError("番剧链接应当报错")
    print("OK")
