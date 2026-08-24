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
| [services/license-api](services/license-api/) | 授权服务（激活码/设备绑定/管理后台） | Node.js + Express + MySQL | ✅ 已上线 |
| [services/media-api](services/media-api/) | 视频解析 / 下载 / 去水印服务 | Python FastAPI + yt-dlp + ffmpeg | 🔧 V1 可跑，仅本地 |

**两条技术路线**（重要区别）：

- **桌面端走本地**：内嵌 yt-dlp + ffmpeg 二进制，解析下载全在用户机器上跑，只在授权时联网。代价是安装包 170MB+。
- **移动端 / 鸿蒙走服务端**：手机和鸿蒙沙箱跑不了 ffmpeg/yt-dlp，全部交给 `services/media-api` 处理。

详见 [docs/architecture.md](docs/architecture.md)。

---

## 目录结构

```
4KDownle/
├── apps/                       # 客户端（按平台命名，与技术栈解耦）
│   ├── desktop/                # Flutter — macOS / Windows
│   ├── mobile/                 # uniapp — Android / 微信小程序 / H5
│   └── harmony-pc/             # 鸿蒙 PC（占位）
├── services/                   # 服务端（多端共享，不隶属任何客户端）
│   ├── license-api/            # Node — 授权
│   └── media-api/              # Python — 解析/下载/去水印
├── docs/
│   ├── architecture.md         # 跨端架构总览 ← 先看这个
│   ├── deploy.md               # 服务器部署
│   ├── roadmap.md              # 桌面端开发进度（阶段 1-22）
│   └── mobile-app-design.md    # 移动端产品与技术设计稿
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

需要同时起 `services/media-api`，否则所有功能不可用。详见 [apps/mobile/README.md](apps/mobile/README.md)。

### media-api（Python）

```bash
cd services/media-api
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
pip install Pillow                  # ⚠️ requirements.txt 漏了，见下方已知问题
uvicorn app.main:app --reload       # http://127.0.0.1:8000
```

系统级前置依赖：**ffmpeg / ffprobe**（视频处理）、**node**（抖音 a_bogus 签名要起 node 子进程）。

### license-api（Node）

```bash
cd services/license-api
npm install
cp .env.example .env && vim .env    # 填 DB / ADMIN_* / JWT_SECRET
npm run init-db
npm run dev
```

详见 [services/license-api/README.md](services/license-api/README.md)、[docs/deploy.md](docs/deploy.md)。

---

## 已知问题

| 位置 | 问题 |
|------|------|
| `services/media-api/requirements.txt` | 缺 **Pillow**，但 `services/video_tools.py` 用了 `from PIL import ...`，按文档装依赖会 ImportError |
| `services/media-api/app/main.py` | `CORS allow_origins=["*"]` + 无任何鉴权 + `/files` `/tmp` 静态目录全公开。**公网部署前必须加鉴权**，否则是个开放下载代理 |
| `apps/mobile/src/pages/launch/launch.vue` | 引导启动页存在但**未注册进 `pages.json`**，实际不生效 |
| `services/media-api/app/config.py` | `PUBLIC_BASE_URL`、`MAX_UPLOAD_SIZE` 已定义但代码未使用，是死配置 |
| 跨端 | **抖音解析有两套实现**：桌面端 Flutter WebView 拦截 `aweme/detail`，media-api 用 a_bogus 纯 HTTP 签名。后者方案更优，建议后续收敛，见 [architecture.md](docs/architecture.md) |
| `.github/workflows/build.yml` | 服务器 IP 硬编码在 `--dart-define=API_BASE`，建议改用 GitHub Secrets |

---

## 相关链接

- Gitee（`origin`，服务器从此拉取）：https://gitee.com/huoyongzhuang/downie_test.git
- GitHub（`github`，跑 Actions CI）
- 更新日志：[CHANGELOG.md](CHANGELOG.md)
