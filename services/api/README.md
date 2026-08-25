# services/api — 统一服务端（FastAPI）

授权（激活码 / 设备绑定）+ 视频处理（解析 / 下载 / 去水印）+ 管理后台，一个进程按 `MODULES` 挂载。

- 单一服务端：授权（license 模块）+ 视频处理（media 模块）+ 管理后台（admin 模块），一个进程按 `MODULES` 挂载。
- 客户端授权接口 `/api/license/*` 与旧 Node 服务**逐字段兼容**，桌面端无感。

仓库级约定见[根 CLAUDE.md](../../CLAUDE.md)；操作手册见 [docs/项目使用助手.md](../../docs/项目使用助手.md)。

## 快速开始

```bash
cd services/api
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env && vim .env      # 填 DB / ADMIN / JWT / REDIS
python scripts/init_db.py             # 建表（幂等）
uvicorn app.main:app --reload         # http://127.0.0.1:3000
```

系统级依赖：**ffmpeg / ffprobe**（视频处理）、**node**（抖音 a_bogus 签名）。

## 模块

| MODULES 值 | 挂载内容 |
|---|---|
| `license` | `/api/license/*` 授权接口 |
| `admin` | `/admin/api/*` 管理后台 API + `/admin` 静态页 |
| `media` | `/api/parse` `/api/download` `/api/delogo/*` `/api/*/process` 视频处理 + `/files` `/tmp` 静态 |

默认 `MODULES=license,admin,media` 全开。境外媒体节点可 `MODULES=media`（不连 MySQL）。

## 目录结构

```
app/
├── main.py         入口 + MODULES 开关 + lifespan（磁盘清理）
├── config.py       环境变量（DB / REDIS / ADMIN / JWT / 媒体路径）
├── db.py           SQLAlchemy async engine + session
├── security.py     管理端 JWT + 客户端授权校验 + 签名 URL
├── limits.py       并发信号量 / 上传大小 / 磁盘清理
├── schemas.py      媒体请求/响应模型
└── modules/
    ├── license/    授权（models / service / router / codes）
    ├── admin/      管理后台 API（JWT）
    └── media/      视频处理（routers / services / tasks）
sql/schema.sql      授权三张表（licenses / device_bindings / unbind_log）
scripts/            init_db.py / generate_licenses.py
```

## 环境变量

全部在 `.env` 配置（模板见 `docs/项目使用助手.md` §1）：

- `DB_*`：MySQL 连接
- `REDIS_*`：Redis 连接
- `ADMIN_USERNAME` / `ADMIN_PASSWORD` / `JWT_SECRET`：管理后台
- `PUBLIC_BASE_URL` / `MAX_UPLOAD_SIZE` / `YTDLP_PROXY` / `MEDIA_CONCURRENCY` / `SIGNED_URLS`：媒体

## 已知限制

- 媒体任务队列仍为进程内存（`modules/media/tasks.py`），重启丢失；Redis 队列待接。
- `/files` `/tmp` 静态目录默认无鉴权；公网前开 `SIGNED_URLS=1`（签名 URL）并收紧 `ALLOWED_ORIGINS`。
- 抖音 / B站强反爬随平台更新会失效，需持续维护。
