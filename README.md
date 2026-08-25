# 4KDownle · 水影

> 全能视频下载器 — 支持 YouTube / B站 / 抖音 / 小红书等 1000+ 网站
> Slogan：拾取全网流媒体，留存每一帧画面

多端仓库（monorepo）：桌面端、移动端、鸿蒙 PC 端 + 两个共享后端服务。

---

## 端与服务一览

| 目录 | 形态 | 技术栈 | 状态 |
|------|------|--------|------|
| [apps/desktop](apps/desktop/) | macOS / Windows 桌面应用 | Flutter + Dart | ✅ 已发布 v2.0.0 |
| [apps/mobile](apps/mobile/) | Android APK / 微信小程序 / H5 | uniapp（Vue3）+ uview-plus | 🔧 V1 功能已实现，未发布 |
| [apps/harmony-pc](apps/harmony-pc/) | 鸿蒙 PC 应用 | 待定（三条候选路线） | ⏳ 占位，未开发 |
| [services/api](services/api/) | 统一服务端（授权 + 视频处理 + 管理后台） | Python FastAPI + MySQL + Redis | 🔧 合并中 |
| [apps/admin-web](apps/admin-web/) | 管理后台前端 | Vue3 + Vite + Element Plus | 🔧 开发中 |

**两条技术路线**（重要区别）：

- **桌面端走本地**：内嵌 yt-dlp + ffmpeg 二进制，解析下载全在用户机器上跑，只在授权时联网。代价是安装包 170MB+。
- **移动端 / 鸿蒙走服务端**：手机和鸿蒙沙箱跑不了 ffmpeg/yt-dlp，全部交给 `services/api` 的 media 模块处理。

详见 [docs/architecture.md](docs/architecture.md)。

---

## 目录结构

```
4KDownle/
├── apps/                       # 客户端（按平台命名，与技术栈解耦）
│   ├── desktop/                # Flutter — macOS / Windows
│   ├── mobile/                 # uniapp — Android / 微信小程序 / H5
│   ├── harmony-pc/             # 鸿蒙 PC（占位）
│   └── admin-web/              # 管理后台前端（Vue3）
├── services/                   # 服务端（多端共享，不隶属任何客户端）
│   └── api/                    # Python FastAPI — 授权 + 解析/下载/去水印（统一）
├── docs/
│   ├── architecture.md         # 跨端架构总览 ← 先看这个
│   ├── deploy.md               # 服务器部署
│   ├── roadmap.md              # 桌面端开发进度（阶段 1-22）
│   ├── mobile-app-design.md    # 移动端产品与技术设计稿
│   └── 项目使用助手.md          # 怎么跑起来 / 怎么排查（操作手册）
├── CLAUDE.md                   # 给 Claude Code 的仓库级说明
└── CHANGELOG.md
```

**为什么没有 `packages/shared/`**：四端跨 Dart / TypeScript / Python 三种语言，代码层面共享不了，强建共享包是过度设计。跨端一致性靠 [docs/architecture.md](docs/architecture.md) 里的接口契约维持。

---

## 快速开始

### 桌面端（Flutter）

```bash
cd apps/desktop
flutter pub get
flutter run -d macos --dart-define=API_BASE=http://<服务器IP>:3000
flutter analyze                     # 代码检查
flutter build macos                 # 打包（Windows 用 flutter build windows）
```

开发态 yt-dlp / ffmpeg 走系统 PATH；打包需先把二进制放进 `apps/desktop/assets/bin/{macos,windows}/`（不进库，CI 会自动下载）。详见 [apps/desktop/README.md](apps/desktop/README.md)。

### 移动端（uniapp）

```bash
cd apps/mobile
npm install
npm run dev:h5                      # H5 调试（也有 dev:mp-weixin / dev:app）
```

需要同时起 `services/api`，否则所有功能不可用。详见 [apps/mobile/README.md](apps/mobile/README.md)。

### 统一服务端（Python FastAPI）

```bash
cd services/api
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env && vim .env    # 填 DB / REDIS / ADMIN / JWT
python scripts/init_db.py           # 建表（幂等）
uvicorn app.main:app --reload       # http://127.0.0.1:3000
```

系统级前置依赖：**ffmpeg / ffprobe**（视频处理）、**node**（抖音 a_bogus 签名要起 node 子进程）。详见 [services/api/README.md](services/api/README.md)。

### 管理后台（pure-admin-vue3）

```bash
cd apps/admin-web
pnpm install
pnpm dev               # 开发态，vite 已把 /login /user /card 等代理到 127.0.0.1:3000
pnpm build             # 产物 dist/ 复制到 services/api/static/admin/ 由后端 /admin 托管
```

系统管理（用户/角色/菜单/部门）+ 卡密管理 + 任务管理 + 会员管理（占位）都已就位。默认管理员 `admin` / `.env 的 ADMIN_PASSWORD`。

---

## 已知问题

| 位置 | 问题 |
|------|------|
| `apps/mobile/src/pages/launch/launch.vue` | 引导启动页存在但**未注册进 `pages.json`**，实际不生效 |
| `services/api` 媒体任务队列 | 仍为进程内存，重启丢失；Redis 队列待接 |
| `services/api` `/files` `/tmp` | 静态目录默认无鉴权，公网前需开 `SIGNED_URLS` + 收紧 CORS |
| 跨端 | **抖音解析有两套实现**：桌面端 Flutter WebView 拦截 `aweme/detail`，`services/api` 用 a_bogus 纯 HTTP 签名。后者方案更优，建议后续收敛，见 [architecture.md](docs/architecture.md) |
| `.github/workflows/build.yml` | 服务器 IP 硬编码在 `--dart-define=API_BASE`，建议改用 GitHub Secrets |

---

## 相关链接

- Gitee（`origin`，服务器从此拉取）：https://gitee.com/huoyongzhuang/downie_test.git
- GitHub（`github`，跑 Actions CI）
- 更新日志：[CHANGELOG.md](CHANGELOG.md)
