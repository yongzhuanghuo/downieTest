import logging

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from . import config
from .routers import delogo, download, parse, tools

# 全局日志：INFO 级别，控制台可看到解析/下载/去水印关键日志
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)-7s [%(name)s] %(message)s",
    datefmt="%H:%M:%S",
)

app = FastAPI(title="4K Downloader API", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# 下载结果 / 临时文件（上传视频、抽帧图）静态挂载，前端直接通过 URL 访问
app.mount("/files", StaticFiles(directory=str(config.DOWNLOAD_DIR)), name="files")
app.mount("/tmp", StaticFiles(directory=str(config.TEMP_DIR)), name="tmp")

app.include_router(parse.router, prefix="/api", tags=["parse"])
app.include_router(download.router, prefix="/api", tags=["download"])
app.include_router(delogo.router, prefix="/api", tags=["delogo"])
app.include_router(tools.router, prefix="/api", tags=["tools"])


@app.get("/health")
def health():
    return {"status": "ok"}
