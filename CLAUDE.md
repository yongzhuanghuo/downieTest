# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

Sownie Pro（拾帧）— Flutter 桌面视频下载器（macOS / Windows），通过 yt-dlp + FFmpeg 子进程做解析、下载、合并，带会员授权系统（自建 Node 后端）。详细结构和技术栈见 [README.md](README.md)（含开发计划阶段 1-19）。

## 常用命令

### Flutter 客户端（仓库根目录）
- 开发运行（macOS，指向后端）：`flutter run -d macos --dart-define=API_BASE=http://<服务器IP>:3000`
- 代码检查：`flutter analyze`
- 测试：`flutter test`（单个：`flutter test test/widget_test.dart`）
- 打包：`flutter build macos` / `flutter build windows`
- 重新生成 logo + macOS/Windows 图标：`bash tools/generate_icons.sh`（源图默认根目录 `logo.png`）

### 授权后端（`downie-license-api/`，独立部署到服务器，不参与 Flutter 构建）
- 依赖：`npm install`
- 建表：`npm run init-db`（读 `sql/schema.sql`，`CREATE TABLE IF NOT EXISTS`，幂等）
- 生成激活码：`npm run generate -- -c 10 -t perpetual -o pro.csv`
- 启动：`pm2 start ecosystem.config.cjs`（本地调试 `npm run dev`）
- 部署步骤见 [DEPLOY.md](DEPLOY.md)

## 架构（大图）

Flutter 分层（`lib/`）：

- `core/` — 引擎与基础设施
  - `engine/ytdlp_runner.dart`：yt-dlp 子进程封装（`parse()` 用 `--dump-json`，`download()` 下载 + 进度解析）
  - `ffmpeg/ffmpeg_runner.dart`：FFmpeg 子进程封装（合并音视频、MP3 转换、字幕嵌入）
  - `platform/`：二进制定位（`binary_locator.dart`）+ 首次运行从 assets 提取（`binary_initializer.dart`）
  - `storage/`：Hive 设置（`settings_storage.dart`，含 LicenseStorage 和每日配额）、SQLite 下载历史（`downloads_dao.dart`）、站点 cookie（`site_cookies.dart` + `site_registry.dart`）
  - `license/`：许可证客户端（`license_client.dart`）
- `data/models/` — 不可变数据模型（DownloadTask、VideoInfo、FormatOption 等）
- `features/` — 按业务模块：`home/`（解析/下载入口）、`downloads/`（队列/历史/站点登录弹窗）、`license/`、`settings/`、`history/`
- `shared/` — 路由（`routes/app_routes.dart`）、导航壳（`widgets/app_shell.dart`）、主题

状态用 **flutter_riverpod**（`StateNotifier` + `Provider`）；路由用 **go_router**（`ShellRoute` + 侧边栏 4 项：首页/下载/历史/设置）。

## 关键流程（跨文件）

### 下载闭环
`home_page.dart` → `parseProvider`（`home_provider.dart`）→ `YtDlpRunner.parse`（`--dump-json`）→ 选格式 → `DownloadListNotifier.startDownload`（`download_provider.dart`，并发队列 + 失败重试 + SQLite 持久化）→ `YtDlpRunner.download` → 需要合并时 `FFmpegRunner.mergeVideoAudio`。

### 授权
客户端只把 `code + device_fp` 发给后端，**信任服务端返回的负载**（客户端无本地验签/密钥）。后端用数据库随机激活码，激活用事务 + `SELECT ... FOR UPDATE` 防超绑。

### 二进制内嵌
yt-dlp / ffmpeg 放在 `assets/bin/{macos,windows}/`（被 .gitignore 忽略，不进库）。首次运行由 `BinaryInitializer` 复制到应用支持目录；`BinaryLocator` 定位（开发态回退系统 PATH）。macOS 的 ffmpeg 需合成为 universal（x86_64 + arm64，用 `lipo -create`）。

### 站点登录（cookie）
下载/解析失败且报错含 `cookie / login / sign in / bot / 登录 / 验证` 等关键词时，`site_login_prompt.dart` 的 `promptSiteLogin` 弹「需要登录 XX 站」→ `site_login_dialog.dart`（flutter_inappwebview 内置浏览器）登录 → `SiteCookies.saveCookies` 按站点写成 `cookies/<站点>.txt`（Netscape 格式）→ yt-dlp 下载/解析时把 `cookies/` 下所有文件用多个 `--cookies` 传入。

## 非显而易见的注意点

- **Git 远程**：`origin` = Gitee（服务器从此拉取，国内网络可访问）、`github` = GitHub（用于 Actions CI，常因国内网络 push 超时）。日常提交 `git push origin main`。
- **API_BASE**：客户端用 `String.fromEnvironment('API_BASE')` 覆盖后端地址，默认 `http://127.0.0.1:3000`（见 `license_client.dart` 顶部）。
- **cookie 文件格式坑**：Netscape 第二列 `includeSubdomains` 必须与域名是否以 `.` 开头一致（`.douyin.com`→`TRUE`，`www.douyin.com`→`FALSE`）。写死 `TRUE` 会触发 Python `http.cookiejar` 的 `assert domain_specified == initial_dot`，yt-dlp 报 `invalid Netscape format`。
- **macOS 无沙箱**：entitlements 里没有 `app-sandbox`，子进程可读浏览器 cookie / 写任意目录。
- **包体积**：内嵌 ffmpeg(~130MB) + yt-dlp(~38MB)，安装包超 100MB，Gitee Releases 放不下（更新包建议阿里云 OSS，见 README 阶段 16）。
