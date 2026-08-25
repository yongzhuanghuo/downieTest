"""全局配置。所有路径/参数可用环境变量（.env）覆盖。

MySQL / Redis / Admin / JWT 连接串统一在这里拼装，密码、端口都在 .env 里配。
media 模块仍通过模块级常量（DOWNLOAD_DIR / TEMP_DIR / FRAME_DIR / PUBLIC_BASE_URL）
访问，保持原有 import 方式不变。
"""
import os
from pathlib import Path

from pydantic_settings import BaseSettings

# services/api/ 目录
BASE_DIR = Path(__file__).resolve().parent.parent


class Settings(BaseSettings):
    """统一配置。环境变量名与旧 Node 服务保持兼容（DB_* / ADMIN_* / JWT_SECRET）。"""

    # ---- 服务 ----
    port: int = 3000
    modules: str = "license,admin,media"  # 挂载模块，逗号分隔

    # ---- MySQL（授权）----
    db_host: str = "127.0.0.1"
    db_port: int = 3306
    db_user: str = ""
    db_password: str = ""
    db_name: str = ""

    # ---- Redis（任务队列 / 频控）----
    redis_host: str = "127.0.0.1"
    redis_port: int = 6379
    redis_password: str = ""  # 空 = 无密码
    redis_db: int = 0

    # ---- 管理后台 ----
    admin_password: str = ""  # 仅 init_db.py 首次建 admin 账号的初始密码，登录走 sys_users 表
    jwt_secret: str = ""      # 登录/刷新 token 签名密钥 + 媒体文件签名 URL 的 HMAC key

    # ---- 媒体 ----
    download_dir: str = ""
    temp_dir: str = ""
    public_base_url: str = "http://127.0.0.1:8000"
    max_upload_size: int = 2 * 1024 * 1024 * 1024
    # 签名 URL：0=关闭（老客户端兼容），1=强制 /files /tmp 需带 exp+sig
    signed_urls: bool = False
    # CORS 白名单，逗号分隔；默认 *（收紧后填真实域名）
    allowed_origins: str = "*"
    # yt-dlp 全局代理（如 http://127.0.0.1:7890）。空 = 不走代理
    ytdlp_proxy: str = ""
    # 并发媒体任务数（0 = 自动按 CPU 核数 / 2）
    media_concurrency: int = 0
    # ---- 阿里云 OSS（后端中转转存）----
    oss_endpoint: str = ""           # 如 oss-cn-hangzhou.aliyuncs.com
    oss_access_key_id: str = ""
    oss_access_key_secret: str = ""
    oss_bucket: str = ""
    oss_public_base_url: str = ""    # 直链域名（Bucket 公网域名或 CDN），拼 https 链接用

    @property
    def database_url(self) -> str:
        return (
            f"mysql+aiomysql://{self.db_user}:{self.db_password}"
            f"@{self.db_host}:{self.db_port}/{self.db_name}?charset=utf8mb4"
        )

    @property
    def redis_url(self) -> str:
        auth = f":{self.redis_password}@" if self.redis_password else ""
        return f"redis://{auth}{self.redis_host}:{self.redis_port}/{self.redis_db}"

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"
        extra = "ignore"  # 忽略 .env 里未定义的键，避免多余环境变量导致启动失败


settings = Settings()

# ---- 媒体模块路径（模块级常量，兼容既有 import 方式）----
DOWNLOAD_DIR = Path(settings.download_dir or (BASE_DIR / "downloads"))
TEMP_DIR = Path(settings.temp_dir or (BASE_DIR / "tmp"))
FRAME_DIR = TEMP_DIR / "frames"
STATIC_DIR = BASE_DIR / "static"

PUBLIC_BASE_URL = settings.public_base_url
MAX_UPLOAD_SIZE = settings.max_upload_size
ALLOWED_ORIGINS = [o.strip() for o in settings.allowed_origins.split(",") if o.strip()]

for d in (DOWNLOAD_DIR, TEMP_DIR, FRAME_DIR, STATIC_DIR):
    d.mkdir(parents=True, exist_ok=True)
