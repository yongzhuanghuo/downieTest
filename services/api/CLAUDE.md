# CLAUDE.md — services/api（统一服务端）

仓库级约定见[根 CLAUDE.md](../../CLAUDE.md)。本文件只讲这个服务。

## 项目概述

FastAPI 单进程统一服务端，按 `MODULES` 环境变量挂载三个模块：

- `license` — 激活码 / 设备绑定（接口契约与历史 Node 版一致，桌面端无感）
- `admin` — 管理后台 API + 静态页（对应 `apps/admin-web`）
- `media` — 视频解析 / 下载 / 去水印 / 加水印 / 改 MD5 / 转 GIF（原 media-api）

接口清单、环境变量、快速开始见 [README.md](README.md)；怎么跑怎么排查见 [docs/项目使用助手.md](../../docs/项目使用助手.md)。

## 常用命令

**全部在本目录（`services/api/`）下执行**：

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload                 # 全模块，默认 3000
MODULES=media uvicorn app.main:app --port 8000  # 只跑媒体（不连 MySQL）
python scripts/init_db.py                     # 建表（幂等）
python scripts/generate_licenses.py -c 10 -t perpetual -o pro.csv
```

## 架构

```
app/
├── main.py          MODULES 开关 + lifespan（磁盘清理）+ 签名 URL 中间件
├── config.py        环境变量；DB/REDIS/ADMIN/JWT/媒体路径
├── db.py            SQLAlchemy async + aiomysql
├── security.py      require_admin(JWT) / require_license(头校验) / sign_url
├── limits.py        并发信号量 / 上传大小 / 磁盘清理
├── schemas.py       媒体请求/响应模型
└── modules/
    ├── license/     codes / models / service / router
    ├── admin/       router（9 接口 + JWT）
    └── media/       routers + services + tasks
```

## 非显而易见的注意点

- **授权契约不能变**。桌面端 v2.0.0 已发布在外，`/api/license/*` 的路径、字段名、错误码、状态码要保持一致。改之前先看 `apps/desktop/lib/core/license/license_client.dart` 的调用。
- **`expire_at` 是 BIGINT 毫秒时间戳**，不是 DATETIME。前端 `new Date(expire_at)` 依赖这个语义，别"顺手改成 datetime"。
- **防超绑靠 `SELECT ... FOR UPDATE`**（`modules/license/service.py` 的 `activate`）。移植成 SQLAlchemy 后必须在同一事务、同一连接上锁行；`with_for_update()` 只有 MySQL 方言下才真正行锁。
- **`/files` `/tmp` 是 StaticFiles，`Depends` 对它无效**。访问控制只能走中间件层（`main.py` 里 `SIGNED_URLS` 开关）。移动端 `uni.downloadFile` 也不可靠携带自定义头，所以媒体文件要走签名 URL，不是 header token。
- **`require_license` 是宽松模式**：没带头就放行（老移动端不挂），带了头但无效才拒绝。要强制收费再收紧。
- **media 模块资源重**：ffmpeg 重编码 + 无上限会拖垮 2C2G 机器。并发靠 `MEDIA_CONCURRENCY`（`limits.py`），上传大小靠 `stream_to_file`，磁盘靠 lifespan 里的清理循环。
- **抖音签名要起 node 子进程**（`media/services/douyin_sign/abogus.py`）。node 是未声明的系统级依赖。
- **代理**：境内部署抓 YouTube 要配 `YTDLP_PROXY`（`media/services/ytdlp.py` 的 `_base_opts` 读它）。

## 与桌面端抖音解析的重复

本目录 media 模块的抖音解析是**纯 HTTP**（a_bogus 签名，无需浏览器）；桌面端是 WebView 拦截。两套独立实现，建议后续桌面端收敛到本服务，见 [docs/architecture.md](../../docs/architecture.md)。
