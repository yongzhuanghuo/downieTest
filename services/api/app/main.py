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
import logging
from contextlib import asynccontextmanager
from urllib.parse import urlparse

from fastapi import Depends, FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from . import config, security

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)-7s [%(name)s] %(message)s",
    datefmt="%H:%M:%S",
)

MODULES = [m.strip() for m in config.settings.modules.split(",") if m.strip()]


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
