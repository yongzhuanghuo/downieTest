"""全局配置。所有路径/参数可用环境变量覆盖。"""
import os
from pathlib import Path

# backend/ 目录
BASE_DIR = Path(__file__).resolve().parent.parent

# 下载结果目录（通过 /files 静态挂载对外提供下载）
DOWNLOAD_DIR = Path(os.getenv("DOWNLOAD_DIR", BASE_DIR / "downloads"))

# 临时目录：上传的视频、抽帧图片、去水印中间产物（通过 /tmp 静态挂载）
TEMP_DIR = Path(os.getenv("TEMP_DIR", BASE_DIR / "tmp"))
FRAME_DIR = TEMP_DIR / "frames"

# 拼 result_url 时用的对外 base url（部署时改成真实域名）
PUBLIC_BASE_URL = os.getenv("PUBLIC_BASE_URL", "http://127.0.0.1:8000")

# 单个视频上传大小上限（默认 2GB）
MAX_UPLOAD_SIZE = int(os.getenv("MAX_UPLOAD_SIZE", 2 * 1024 * 1024 * 1024))

for d in (DOWNLOAD_DIR, TEMP_DIR, FRAME_DIR):
    d.mkdir(parents=True, exist_ok=True)
