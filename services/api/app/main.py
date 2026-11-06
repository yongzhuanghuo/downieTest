"""统一服务端入口。

按 MODULES 环境变量挂载模块（默认全部挂载）：
  - license  激活码 / 设备绑定（对客户端）
  - admin    管理后台 API + 静态页面
  - media    视频解析 / 下载 / 去水印

用法示例：
  MODULES=license,admin,media   uvicorn app.main:app --port 3000   # 单机全开（默认）
  MODULES=media                 uvicorn app.main:app --port 8000   # 境外媒体节点，只跑媒体
"""
import asyncio
import hmac
import logging
import re
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from urllib.parse import urlparse

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
from sqlalchemy import select

from . import config, security
from .db import SessionLocal
from .modules.license.models import Product, Release

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)-7s [%(name)s] %(message)s",
    datefmt="%H:%M:%S",
)

MODULES = [m.strip() for m in config.settings.modules.split(",") if m.strip()]

# 没有 JWT_SECRET 时，管理端 token 和签名 URL 都能被伪造 —— 直接拒绝启动。
if ("admin" in MODULES or "license" in MODULES) and not config.settings.jwt_secret:
    raise RuntimeError(
        "JWT_SECRET 未配置。请在 services/api/.env 写入一段足够长的随机字符串后重启；"
        "它同时用于管理端 JWT 和媒体签名 URL。"
    )

if "media" in MODULES and not config.settings.signed_urls:
    logging.getLogger("app.security").warning(
        "/files 与 /tmp 未启用签名 URL（SIGNED_URLS=0），公网部署前请打开。"
    )
if config.settings.allowed_origins.strip() == "*":
    logging.getLogger("app.security").warning(
        "ALLOWED_ORIGINS=*：生产环境请收紧为实际域名。"
    )


@asynccontextmanager
async def lifespan(app: FastAPI):
    # 后台磁盘清理：每小时清一次 downloads/ tmp 里超过 24h 的旧文件
    async def _cleanup_loop():
        from .limits import cleanup_expired

        while True:
            await asyncio.sleep(3600)
            try:
                n = await cleanup_expired()
                if n:
                    logging.getLogger("app.cleanup").info("已清理 %d 个过期文件", n)
            except Exception as e:  # noqa: BLE001
                logging.getLogger("app.cleanup").warning("磁盘清理失败: %s", e)

    task = asyncio.create_task(_cleanup_loop())
    yield
    task.cancel()


app = FastAPI(title="4KDownle API", version="2.0.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=config.ALLOWED_ORIGINS,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
def health():
    return {"status": "ok", "modules": MODULES}


def _env_latest(platform: str) -> dict:
    """旧版本兼容：DB 没有发布记录时回退到 .env（仅 Downie6）。"""
    s = config.settings
    is_windows = platform == "windows"
    url = s.download_url_windows if is_windows else s.download_url_macos
    sha256 = s.download_sha256_windows if is_windows else s.download_sha256_macos
    return {
        "ok": True,
        "version": s.latest_version,
        "build": s.latest_build,
        "url": url,
        "sha256": sha256,
        "changelog": s.changelog,
        "force": s.force_update,
        "product": "downie6",
        "platform": platform,
        "size": 0,
        "dmg_url": url if not is_windows else "",
        "published_at": None,
    }


@app.get("/api/version/latest")
async def latest_version(
    platform: str = "macos",
    product: str = "downie6",
    channel: str = "stable",
):
    """客户端启动时查最新版本。优先读 releases 表，无数据时回退 .env。"""
    product_code = (product or "downie6").strip().lower()
    platform_code = (platform or "macos").strip().lower()
    try:
        async with SessionLocal() as session:
            p = await session.scalar(select(Product).where(Product.code == product_code))
            if p is not None:
                rel = await session.scalar(
                    select(Release)
                    .where(
                        Release.product_id == p.id,
                        Release.platform == platform_code,
                        Release.status == "published",
                    )
                    .order_by(Release.build.desc())
                    .limit(1)
                )
                if rel is not None:
                    return {
                        "ok": True,
                        "version": rel.version,
                        "build": rel.build,
                        "url": rel.artifact_url,
                        "sha256": rel.artifact_sha256,
                        "changelog": rel.changelog or "",
                        "force": bool(rel.force_update),
                        "product": p.code,
                        "platform": rel.platform,
                        "size": rel.artifact_size,
                        "dmg_url": rel.dmg_url or "",
                        "published_at": rel.published_at.isoformat() if rel.published_at else None,
                    }
    except Exception as e:  # noqa: BLE001 DB 不可用不阻断旧客户端更新
        logging.getLogger("app.version").warning("读取版本表失败，回退 .env: %s", e)

    if product_code == "downie6":
        return _env_latest(platform_code)
    return {
        "ok": True,
        "version": "",
        "build": 0,
        "url": "",
        "sha256": "",
        "changelog": "",
        "force": False,
        "product": product_code,
        "platform": platform_code,
        "size": 0,
        "dmg_url": "",
        "published_at": None,
    }


class ReleasePublishIn(BaseModel):
    product: str
    platform: str = "macos"
    version: str
    build: int
    url: str
    sha256: str
    size: int = 0
    dmg_url: str | None = None
    changelog: str = ""
    force: bool = False


@app.post("/api/internal/releases/publish")
async def publish_release(body: ReleasePublishIn, request: Request):
    """CI 发布成功后调用。用 RELEASE_TOKEN 保护，不暴露给客户端。"""
    token = request.headers.get("X-Release-Token", "")
    if not config.settings.release_token or not hmac.compare_digest(
        token, config.settings.release_token
    ):
        raise HTTPException(status_code=401, detail={"ok": False, "error": "UNAUTHORIZED"})

    product_code = body.product.strip().lower()
    platform = (body.platform or "macos").strip().lower()
    if platform not in ("macos", "windows"):
        raise HTTPException(status_code=400, detail={"ok": False, "error": "INVALID_PLATFORM"})
    if urlparse(body.url).scheme != "https":
        raise HTTPException(status_code=400, detail={"ok": False, "error": "INVALID_URL"})
    if body.dmg_url and urlparse(body.dmg_url).scheme != "https":
        raise HTTPException(status_code=400, detail={"ok": False, "error": "INVALID_DMG_URL"})
    sha = body.sha256.strip().lower()
    if not re.fullmatch(r"[0-9a-f]{64}", sha):
        raise HTTPException(status_code=400, detail={"ok": False, "error": "INVALID_SHA256"})
    if body.build <= 0 or not body.version.strip():
        raise HTTPException(status_code=400, detail={"ok": False, "error": "INVALID_VERSION"})

    async with SessionLocal() as session:
        p = await session.scalar(select(Product).where(Product.code == product_code))
        if p is None:
            raise HTTPException(status_code=404, detail={"ok": False, "error": "INVALID_PRODUCT"})
        latest = await session.scalar(
            select(Release)
            .where(
                Release.product_id == p.id,
                Release.platform == platform,
                Release.status == "published",
            )
            .order_by(Release.build.desc())
            .limit(1)
        )
        if latest is not None and body.build < latest.build:
            raise HTTPException(status_code=400, detail={"ok": False, "error": "BUILD_ROLLBACK"})

        rel = await session.scalar(
            select(Release).where(
                Release.product_id == p.id,
                Release.platform == platform,
                Release.build == body.build,
            )
        )
        if rel is None:
            rel = Release(product_id=p.id, platform=platform, version=body.version, build=body.build,
                          artifact_url=body.url, artifact_sha256=sha)
            session.add(rel)
        rel.version = body.version.strip()
        rel.artifact_url = body.url
        rel.artifact_sha256 = sha
        rel.artifact_size = max(0, body.size)
        rel.dmg_url = body.dmg_url or None
        rel.changelog = body.changelog or ""
        rel.force_update = 1 if body.force else 0
        rel.status = "published"
        rel.published_at = datetime.now(timezone.utc).replace(tzinfo=None)
        await session.commit()

    return {"ok": True, "product": product_code, "build": body.build}


# ---------- support：联系支持（不依赖 DB，所有模块组合都挂载）----------
from .modules.support import router as support_router  # noqa: E402

app.include_router(support_router.router)


# ---------- license：客户端授权 ----------
if "license" in MODULES:
    from .modules.license import router as license_router

    app.include_router(license_router.router)

# ---------- admin：管理后台 ----------
if "admin" in MODULES:
    from .modules.admin import router as admin_router

    app.include_router(admin_router.router)
    # 管理后台静态页（admin-web 构建产物），与 API 同源托管
    _admin_static = config.STATIC_DIR / "admin"
    if _admin_static.exists():
        app.mount("/admin", StaticFiles(directory=str(_admin_static), html=True), name="admin")

# ---------- media：视频处理 ----------
if "media" in MODULES:
    from .modules.media.routers import delogo, download, parse, tools

    # 下载结果 / 临时文件（上传视频、抽帧图）静态挂载，前端直接通过 URL 访问
    app.mount("/files", StaticFiles(directory=str(config.DOWNLOAD_DIR)), name="files")
    app.mount("/tmp", StaticFiles(directory=str(config.TEMP_DIR)), name="tmp")

    # 客户端授权校验：宽松模式（无头放行），接入后设 MEDIA_REQUIRE_LICENSE 收紧
    app.include_router(parse.router, prefix="/api", tags=["parse"], dependencies=[Depends(security.require_license)])
    app.include_router(download.router, prefix="/api", tags=["download"], dependencies=[Depends(security.require_license)])
    app.include_router(delogo.router, prefix="/api", tags=["delogo"], dependencies=[Depends(security.require_license)])
    app.include_router(tools.router, prefix="/api", tags=["tools"], dependencies=[Depends(security.require_license)])


# ---------- 签名 URL 校验（/files /tmp 的访问控制）----------
# StaticFiles 不参与 FastAPI 依赖注入，只能用中间件层校验。
# 由 SIGNED_URLS 开关控制：默认关闭（老客户端兼容），公网部署前打开。
if config.settings.signed_urls:
    @app.middleware("http")
    async def _signed_url_guard(request, call_next):
        path = urlparse(request.url.path).path
        if path.startswith(("/files/", "/tmp/")):
            q = dict(request.query_params)
            if not security.verify_signature(path, q.get("exp", ""), q.get("sig", "")):
                raise HTTPException(status_code=403, detail={"ok": False, "error": "FORBIDDEN"})
        return await call_next(request)
