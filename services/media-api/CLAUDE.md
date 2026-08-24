# CLAUDE.md — services/media-api（Python 视频服务）

仓库级约定见[根 CLAUDE.md](../../CLAUDE.md)。本文件只讲这个服务。

## 项目概述

FastAPI 异步服务，负责**视频解析 / 下载 / 去水印 / 加水印 / 改 MD5 / 转 GIF**。

存在的理由：手机和鸿蒙沙箱起不了 `yt-dlp` / `ffmpeg` 子进程，所以 [apps/mobile](../../apps/mobile/) 和未来的 [apps/harmony-pc](../../apps/harmony-pc/) 把这些活全交给它。桌面端不用它（本地内嵌二进制自己跑）。

接口清单与环境变量见 [README.md](README.md)。

## 常用命令

**全部在本目录（`services/media-api/`）下执行**：

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
pip install Pillow                 # ⚠️ requirements.txt 漏了，见下
uvicorn app.main:app --reload      # http://127.0.0.1:8000
curl localhost:8000/health         # 健康检查
```

## 架构

```
app/
├── main.py        FastAPI 入口：CORS + 静态挂载 + 注册 4 个 router + /health
├── config.py      路径与配置（import 时自动 mkdir 三个目录）
├── schemas.py     Pydantic 模型
├── tasks.py       内存任务队列
├── routers/       parse / download / delogo / tools
└── services/
    ├── ytdlp.py         yt-dlp 封装（主力引擎）
    ├── douyin.py        抖音专用解析（a_bogus 签名）
    ├── delogo.py        ffmpeg 抽帧 / 去水印
    ├── video_tools.py   加水印 / 改 MD5 / 转 GIF
    └── douyin_sign/     a_bogus 签名算法（JS，约 3200 行）
```

静态挂载：`/files` → `downloads/`，`/tmp` → `tmp/`。前端直接用 URL 取结果文件。

## 非显而易见的注意点

- **🔴 无鉴权，别暴露公网**。`main.py` 里 `CORS allow_origins=["*"]`，所有接口无 token 校验，`/files` 和 `/tmp` 两个静态目录完全公开。当前状态部署到公网 = 开放下载代理 + 任意文件浏览。加鉴权前只在本地/内网跑。
- **`requirements.txt` 缺 Pillow**。`services/video_tools.py` 顶部 `from PIL import Image, ImageDraw, ImageFont`，但依赖清单没列。按文档装依赖会 ImportError。
- **抖音签名要起 node 子进程**。`services/douyin_sign/abogus.py` 用 `subprocess.run(["node", ...])` 跑 `abogus.js`。**node 是未声明的系统级运行时依赖**，部署环境没装 node 抖音解析就废。
- **`downloads/` 和 `tmp/` 删了不影响启动**。`config.py` 在 import 时就 `mkdir(parents=True, exist_ok=True)`，且早于 `main.py` 的 `StaticFiles` 挂载，所以目录会自动重建。这两个目录已在 `.gitignore` 里，产物不进库。
- **任务队列在内存里**，`tasks.py` 是纯内存字典，**进程重启任务全丢**。设计稿里写的 Celery + Redis 还没上。
- **`PUBLIC_BASE_URL` 和 `MAX_UPLOAD_SIZE` 是死配置**。`config.py` 里定义了，但代码没用 —— result_url 拼的是相对路径（`/files/...`），由前端 `fullUrl` 再拼 base；上传大小也没做实际校验。改这两个值不会有任何效果。
- **系统级前置依赖**：`ffmpeg` / `ffprobe`（去水印、抽帧、合并）、`node`（抖音签名）。两个都不在 `requirements.txt` 里。

## 与桌面端抖音解析的重复

这里的抖音解析是**纯 HTTP**（短链展开 + ttwid cookie + a_bogus 签名 + Referer），不需要浏览器。
桌面端 [apps/desktop](../../apps/desktop/) 走的是另一套 —— WebView 拦截 `aweme/detail` 响应。

两套独立实现、独立维护。本目录这套方案更优（无需 WebView、可服务端批量跑），**建议后续桌面端收敛过来**。详见 [docs/architecture.md](../../docs/architecture.md)。
