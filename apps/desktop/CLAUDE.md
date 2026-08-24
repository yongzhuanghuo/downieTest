# CLAUDE.md — apps/desktop（Flutter 桌面端）

仓库级约定见[根 CLAUDE.md](../../CLAUDE.md)。本文件只讲桌面端。

## 项目概述

4KDownle 桌面版（macOS / Windows）— Flutter 应用，通过 **yt-dlp + FFmpeg 子进程**做解析、下载、合并，带会员授权系统。

抖音不走 yt-dlp（其提取器未实现 `a_bogus` 签名、被抖音反爬打穿），改用内置 WebView 拦截 `aweme/detail` API 响应拿播放地址。

详细结构和技术栈见 [README.md](README.md)；开发进度见 [docs/roadmap.md](../../docs/roadmap.md)。

## 常用命令

**全部在本目录（`apps/desktop/`）下执行**，在仓库根执行会失败。

```bash
flutter run -d macos --dart-define=API_BASE=http://<服务器IP>:3000   # 开发运行
flutter analyze                                                     # 代码检查
flutter test                                                        # 测试（单个：flutter test test/widget_test.dart）
flutter build macos                                                 # 打包（Windows: flutter build windows）
bash tools/generate_icons.sh                                        # 重新生成 logo + 各平台图标（源图默认 ./logo.png）
```

## 架构（大图）

`lib/` 分层：

- `core/` — 引擎与基础设施
  - `engine/ytdlp_runner.dart`：yt-dlp 子进程封装（`parse()` 用 `--dump-json`，`download()` 下载 + 进度解析）
  - `engine/douyin_downloader.dart`：抖音 HTTP 直链下载（桌面 UA + Referer douyin.com 绕过防盗链，带进度回调）
  - `ffmpeg/ffmpeg_runner.dart`：FFmpeg 子进程封装（合并音视频、MP3 转换、字幕嵌入）
  - `platform/`：二进制定位（`binary_locator.dart`）+ 首次运行从 assets 提取（`binary_initializer.dart`）
  - `storage/`：Hive 设置（`settings_storage.dart`，含 LicenseStorage 和每日配额）、SQLite 下载历史（`downloads_dao.dart`）、站点 cookie（`site_cookies.dart` + `site_registry.dart`）
  - `license/`：许可证客户端（`license_client.dart`）
- `data/models/` — 不可变数据模型（DownloadTask、VideoInfo、FormatOption 等）
- `features/` — 按业务模块：`home/`（解析/下载入口）、`downloads/`（队列/历史/站点登录弹窗、抖音 WebView 解析 `douyin_web_dialog.dart`）、`license/`、`settings/`、`history/`
- `shared/` — 路由（`routes/app_routes.dart`）、导航壳（`widgets/app_shell.dart`）、主题

状态用 **flutter_riverpod**（`StateNotifier` + `Provider`）；路由用 **go_router**（`ShellRoute` + 侧边栏 4 项：首页/下载/历史/设置）。

## 关键流程（跨文件）

### 下载闭环

`home_page.dart` → `parseProvider`（`home_provider.dart`）→ 解析（分两条路）→ 选格式 → `DownloadListNotifier.startDownload`（`download_provider.dart`，并发队列 + 失败重试 + SQLite 持久化）→ 下载 → 需要合并时 `FFmpegRunner.mergeVideoAudio`。

解析/下载按站点分两条路：

- **抖音**（url 含 `douyin.com`）：`DouyinWebDialog`（WebView 拦截 aweme/detail）→ 下载走 `DouyinDownloader`（HTTP 直链）。全程不经过 yt-dlp。
- **其他站点**：`YtDlpRunner.parse`（`--dump-json`）→ `YtDlpRunner.download`。`download_provider.dart` 里按 `extractor=='Douyin'` 分流。

### 授权

客户端只把 `code + device_fp` 发给 `services/license-api`，**信任服务端返回的负载**（客户端无本地验签/密钥）。后端用数据库随机激活码，激活用事务 + `SELECT ... FOR UPDATE` 防超绑。

### 二进制内嵌

yt-dlp / ffmpeg 放在 `assets/bin/{macos,windows}/`（被 .gitignore 忽略，不进库，CI 构建时现下）。首次运行由 `BinaryInitializer` 复制到应用支持目录；`BinaryLocator` 定位（开发态回退系统 PATH）。macOS 的 ffmpeg 需合成为 universal（x86_64 + arm64，用 `lipo -create`）。

### 站点登录（cookie）

下载/解析失败且报错含 `cookie / login / sign in / bot / 登录 / 验证` 等关键词时，`site_login_prompt.dart` 的 `promptSiteLogin` 弹「需要登录 XX 站」→ `site_login_dialog.dart`（flutter_inappwebview 内置浏览器）登录 → `SiteCookies.saveCookies` 按站点写成 `cookies/<站点>.txt`（Netscape 格式）→ yt-dlp 下载/解析时把 `cookies/` 下所有文件用多个 `--cookies` 传入。

抖音例外：抖音解析不依赖 cookie（走 WebView 拦截 aweme/detail），登录抓 cookie 对抖音无用。但 `site_login_dialog.dart` 里仍保留「抖音登录后从 localStorage 抓 msToken 补进 cookie」的逻辑（对抖音解析无影响，保留以备将来）。

## 非显而易见的注意点

- **API_BASE**：客户端用 `String.fromEnvironment('API_BASE')` 覆盖后端地址，默认 `http://127.0.0.1:3000`（见 `lib/core/license/license_client.dart` 顶部）。
- **cookie 文件格式坑**：Netscape 第二列 `includeSubdomains` 必须与域名是否以 `.` 开头一致（`.douyin.com`→`TRUE`，`www.douyin.com`→`FALSE`）。写死 `TRUE` 会触发 Python `http.cookiejar` 的 `assert domain_specified == initial_dot`，yt-dlp 报 `invalid Netscape format`。
- **抖音解析原理**：yt-dlp 抖音提取器没实现 `a_bogus` 签名（tiktok.py 只有 TODO），且抖音 2026 年分享页 SSR 不再内嵌播放地址（播放地址由前端 JS 异步调 `aweme/detail` 拉取）。所以抖音改走 WebView：用**桌面 UA** 打开视频页，注入 JS hook（`AT_DOCUMENT_START`）拦截 `aweme/detail` 的 fetch/XHR 响应（浏览器环境自动带 a_bogus 签名 + cookie），从响应 `aweme_detail.video.play_addr` 拿播放地址，再 HTTP 直链下载。移动 UA 会停在「打开 App」引导页、不触发 API，必须用桌面 UA。
  > 注意 `services/media-api` 里有另一套抖音解析（纯 HTTP + a_bogus 签名，不需要浏览器），两套互相独立。见 [docs/architecture.md](../../docs/architecture.md)。
- **macOS 无沙箱**：entitlements 里没有 `app-sandbox`，子进程可读浏览器 cookie / 写任意目录。
- **包体积**：内嵌 ffmpeg(~130MB) + yt-dlp(~38MB)，安装包超 100MB，Gitee Releases 放不下（更新包建议阿里云 OSS，见 [docs/roadmap.md](../../docs/roadmap.md) 阶段 16）。
- **工程内路径都是自定位的**：`pubspec.yaml` 的 asset 键、`tools/generate_icons.sh`（用 `dirname $0/..`）、`windows/installer/setup.iss`（相对 .iss 自身）、Xcode 工程（`$FLUTTER_ROOT` / `$PROJECT_DIR` / `$PODS_ROOT`）。整个工程可以整体移动而不改任何内部引用。
- **IDE 工程根**：用 IDE 打开时应以 `apps/desktop/` 为工程根（不是仓库根），否则 Dart/Flutter 插件识别不到 `pubspec.yaml`。
