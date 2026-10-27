# REA 反编译 Downie 4 与完整复刻规划

- **文档状态**：可执行规划 v1
- **对标基线**：Downie 4 v4.13.3（`CFBundleVersion` 4000，`com.charliemonroe.Downie-4`）
- **当前产品**：Downie6 v2.0.26+27（Flutter，macOS + Windows）
- **更新日期**：2026-10-27
- **当前执行计划**：[downie-parity-plan.md](downie-parity-plan.md)
- **站点覆盖全表**：[site-coverage.md](site-coverage.md)
- **详细分析底稿**：`~/re/downie4/reports/`（本文是汇总版，底稿不在仓库）

---

## 0. 结论（先看这里）

1. **可以做到“功能对标”**：Downie 能下载的非 DRM 内容，我们可以用独立实现做到同类能力。
2. **做不到“源码级复刻”**：REA 目前只完成了 Mach-O、符号、字符串、资源层面的静态分析；Ghidra/Hopper 尚未安装，没有逐函数反编译，也拿不到原始 Swift 工程。
3. **不支持 DRM 正片**：Netflix / Disney+ / Prime Video 等 Widevine/FairPlay/PlayReady 内容，Downie 自己也明确拒绝下载。这不是我们没做，而是不在范围。
4. **786 个下载器类不能靠一次性交付**：正确目标是 Top 20–30 + 通用 WebView 嗅探 + 自定义集成 + yt-dlp 兜底，然后按失败率持续补站。
5. **当前进度（2026-10-26）**：Downie 风格 UI、DMG/EXE 发布链、应用内更新、抖音/B站插件、通用网页提取、14 天服务端试用、反激活、暂停/继续、优先级、批量链接、播放列表展开、系统通知、浏览器书签/Chrome 扩展均已落地；Top 30 中大部分站点仍走 yt-dlp，部分站点的原生定制仍未完成；浏览器链接/文本拖拽已支持；签名/公证按用户决定不做。

---

## 1. REA 分析结论与证据

### 1.1 实际做了什么

- 工具：REA 6.7.0 + macOS 原生工具（`nm` / `strings` / `otool` / `lipo` / `codesign`）。
- 方式：只读静态分析，没有修改、重签名或动态附加 `/Applications/Downie 4.app`。
- 限制：本机没有 Ghidra/Hopper，`rea analyze` 返回 `provider_unavailable`；`rea inspect-macho` 可用。因此当前结论来自二进制结构、符号、字符串和资源，不是伪代码级还原。
- 原始应用：`/Applications/Downie 4.app`。

### 1.2 关键数字

| 项目 | 结果 |
|---|---|
| 二进制 | 通用 Mach-O（x86_64 + arm64），Hardened Runtime + App Sandbox |
| 主程序 | 约 8.8 MB |
| `DownieCore.framework` | 约 34 MB |
| 导出符号 | 约 3200 个（Swift 符号约 2903 个） |
| 泄漏的 Swift 源文件路径 | 630 个唯一路径（只是路径，不是源码） |
| `*Downloader` 类名 | 786 个（含子类/变体） |
| 与 yt-dlp extractor 名称命中 | 305 个 |
| 已知 DRM 标记 | 2 个（Disney、Apple；Netflix 在 `_drmProtectedHosts` 中） |

### 1.3 能还原到什么程度

| 目标 | 可行性 | 说明 |
|---|---|---|
| 模块/类/方法结构 | 高 | Swift 符号未剥离，且有源文件路径 |
| 支持站点/下载器清单 | 高 | 786 个类名 + 域名 + 字符串 |
| 单站解析流程 | 中-高 | 需要 Ghidra 伪代码 + 字符串/正则 + 资源 |
| HLS/DASH/分片/合并 | 中-高 | 类结构清晰，有独立 reader/chunk/quality 模块 |
| YouTube SABR / PO Token | 中 | 动态行为多，工作量最大 |
| 动态调试（lldb） | 低 | Hardened Runtime + Sandbox 会拦 |
| 还原原始 Swift 工程 | 不可行 | Swift 没有源码级反编译，且涉及版权 |

**一句话：能拿到“完整架构 + 伪代码 + 行为报告”，拿不到“原工程源码”。**

### 1.4 下一步分析（可选）

如果要把单站逻辑做到伪代码级，下一步是在本机安装 Ghidra：

```bash
brew install ghidra
rea doctor
rea analyze "/Applications/Downie 4.app"
```

注意：REA 的分析结果会发送给模型 provider，不要把密钥或用户数据喂进去。

---

## 2. “完整复刻”的范围

这里的“完整复刻”指 **功能与操作路径对标**，不是复制 Downie 的代码、nib、图片、文案或 Paddle/Licensing 协议。

### 2.1 功能面

| 模块 | 目标能力 | 当前状态 |
|---|---|---|
| 下载管理 | 队列、历史、断点续传、失败重试、播放列表、链接过滤、下载调试器 | 队列/历史/重试/续传/暂停/优先级/播放列表（展开 200 条）已完成；链接过滤/调试器未做 |
| 站点识别 | 每站下载器、通用抓取（UGE）、引导式提取、站点管理、URL 报告 | 插件框架 + 抖音/B站 + 通用 HTML/WebView 提取已做；Top 30 其余主要走 yt-dlp，原生定制未做 |
| 媒体处理 | HLS/DASH/HTTP 分片、音视频分离、画质、字幕、ffmpeg 合并/转码、自定义后处理 | FFmpeg HLS/DASH/直链下载、MP4/MP3 后处理、字幕/封面选项已完成；原生分片调度/自定义脚本未做 |
| 登录/网络 | Cookie/登录助手、代理、本地 HTTP 服务、IP 转发 | WebView 登录 + cookie、浏览器 cookie 读取、代理、本地 8765 接收端口/书签/Chrome 扩展已完成 |
| UX | 浏览器扩展、剪贴板/拖拽、通知、外观、导入 | Downie 风格主界面、粘贴/多链接/文件导入、系统通知、Chrome 扩展/书签、原生链接/文本拖拽已完成 |
| 高级 | 自定义集成（Registry/提交/控制台/JS 执行）、快速预览 | 未开始 |
| 授权 | 14 天试用、邮箱绑定、4 设备、反激活、找回、撤销 | 14 天试用、邮箱存储、4 设备绑定、反激活已上线；邮件 OTP/自动找回/签名令牌/心跳撤销未做 |
| 发布 | macOS/Windows 安装包、更新提示、OTA/OSS | DMG + EXE + OSS + 版本接口 + 应用内下载安装已完成；签名/公证按用户决定不做；HTTPS 未做 |

### 2.2 明确不做

- 不破解 Widevine / FairPlay / PlayReady。
- 不复制 Downie 的源码、资源、nib/storyboard、文案、授权协议或密钥。
- 不承诺 786 个站点在某个时间点全部支持；这是持续维护目标。
- 不绕过付费内容或账号权限；只使用用户本人有权访问的登录态。
- **不做 macOS Developer ID 签名/公证，也不做 Windows Authenticode 代码签名**（用户 2026-10-27 明确决定）。安装时继续用右键打开 / “仍要运行”；不要再把证书、签名、公证列入发布待办。

---

## 3. 目标架构

### 3.1 共享层（Dart，macOS/Windows 复用）

- **下载引擎**：队列、并发、限速、重试、断点续传；`DownloadStrategy` 抽象（direct / HLS / DASH / chunked）。
- **站点插件**：`SitePlugin` 接口、注册表、优先级、失败回退。
- **媒体模型**：标题、画质、音轨、字幕、headers、cookies、DRM 标记。
- **媒体处理**：ffmpeg 合并/转码、字幕嵌入、自定义后处理。
- **存储**：SQLite（历史/队列）、Hive（设置）、站点 cookie。
- **授权客户端**：签名令牌、设备指纹、心跳、离线宽限。
- **扩展通信**：localhost HTTP/WebSocket + 随机 token。

### 3.2 平台层

| 能力 | macOS | Windows |
|---|---|---|
| UI | Flutter | Flutter |
| WebView 捕获 | WKWebView + JS 注入 + 资源嗅探 | WebView2 + `WebResourceRequested` + JS 注入 |
| Cookie/登录 | `WKHTTPCookieStore` | WebView2 `CookieManager` |
| 安全存储 | Keychain | DPAPI / Credential Manager |
| 本地 HTTP 服务 | Dart `HttpServer` | Dart `HttpServer` |
| 更新 | Sparkle 或自有更新器 | WinSparkle/Squirrel 或自有更新器 |
| 签名 | 不做（用户决定，保留右键打开） | 不做（用户决定，保留“仍要运行”） |
| 安装包 | DMG | Inno Setup（当前）/ NSIS |

### 3.3 解析/下载主链路

```
URL
  → 站点插件匹配（域名/短链/正则）
  → 插件解析（API / HTML / WebView / yt-dlp fallback）
  → 统一 MediaInfo（标题、封面、格式、headers、cookies、DRM）
  → DownloadStrategy
      → direct：HTTP 直链
      → HLS：m3u8 + 分片 + AES-128（非 DRM）
      → DASH：mpd + 分片 + 音视频分离
      → chunked：Range/并发/断点
  → ffmpeg 合并/转码/字幕
  → 下载历史 + 通知
```

### 3.4 当前代码映射

| 能力 | 位置 |
|---|---|
| 站点插件接口 | `apps/desktop/lib/core/sites/site_plugin.dart` |
| 插件注册表 | `apps/desktop/lib/core/sites/plugin_registry.dart` |
| 抖音插件 | `apps/desktop/lib/core/sites/plugins/douyin_plugin.dart` |
| B站插件（普通/番剧/WBI/DASH） | `apps/desktop/lib/core/sites/plugins/bilibili_plugin.dart` |
| 通用网页嗅探插件 | `apps/desktop/lib/core/sites/plugins/generic_web_plugin.dart` |
| WebView 资源捕获 | `apps/desktop/lib/features/downloads/web_capture_dialog.dart` |
| FFmpeg HLS/DASH/直链下载 | `apps/desktop/lib/core/ffmpeg/ffmpeg_runner.dart` |
| 首页解析/路由 | `apps/desktop/lib/features/home/home_page.dart`、`home_provider.dart` |
| 下载队列 | `apps/desktop/lib/features/downloads/download_provider.dart` |
| 品牌/帮助/支持 | `apps/desktop/lib/shared/branding/app_brand.dart`、`apps/desktop/lib/features/help/` |
| 发布链 | `.github/workflows/build.yml`、`apps/desktop/macos/installer/`、`apps/desktop/windows/installer/setup.iss` |

---

## 4. 站点覆盖策略

### 4.1 分层

| 层级 | 范围 | 做法 |
|---|---|---|
| Tier 1 | yt-dlp 已覆盖 | 直接走 yt-dlp，不重复造轮子 |
| Tier 2 | yt-dlp 覆盖差、Downie 有专门实现 | 自研插件：抖音、Bilibili、YouTube、Instagram、TikTok、X 等 |
| Tier 3 | 长尾站点 | WebView 通用嗅探（UGE 式）+ 自定义集成 |
| Tier 4 | DRM 站点 | 明确不支持，UI 提示原因 |

### 4.2 现实目标

- 第一阶段：Top 20–30 高频站 + 通用嗅探 + yt-dlp 兜底。
- 第二阶段：按失败率和用户反馈补站。
- 长期：插件 SDK + 站点更新流水线，把“加站”变成可运营工作。
- 786 个类名是清单上限，不是首版交付目标。

### 4.3 P0 站点（35 个，启发式第一版）

| 站点 | Downie 类 | yt-dlp | 计划 |
|---|---|---|---|
| AbemaTV | `AbemaTVDownloader` | yes | yt-dlp 优先；加密流需评估 |
| BBC | `BBCDownloader` | yes | yt-dlp 优先 |
| Bilibili | `BilibiliDownloader` | yes | **已支持：原生插件** |
| CBS | `CBSDownloader` | yes | yt-dlp 优先 |
| CCTV | `CCTVDownloader` | yes | yt-dlp 优先 |
| Disney | `DisneyDownloader` | yes | **不支持：DRM** |
| Douyin | `DouyinDownloader` | yes | **已支持：原生插件** |
| ESPN | `ESPNDownloader` | yes | yt-dlp 优先 |
| Facebook | `FacebookDownloader` | yes | yt-dlp 优先 |
| Fox | `FoxDownloader` | yes | yt-dlp 优先 |
| Instagram | `InstagramDownloader` | yes | 原生候选（登录/限流） |
| JWPlayer | `JWPlayerDownloader` |  | 通用/基础抓取 |
| Kakao | `KakaoDownloader` | yes | yt-dlp 优先 |
| Kaltura | `KalturaDownloader` |  | 通用/基础抓取 |
| MLB | `MLBDownloader` | yes | yt-dlp 优先 |
| MTV | `MTVDownloader` | yes | yt-dlp 优先 |
| Naver | `NaverDownloader` | yes | yt-dlp 优先 |
| NBC | `NBCDownloader` | yes | yt-dlp 优先 |
| Odysee | `OdyseeDownloader` |  | 通用嗅探/API 评估 |
| PBS | `PBSDownloader` | yes | yt-dlp 优先 |
| Pinterest | `PinterestDownloader` | yes | yt-dlp 优先 |
| Radiko | `RadikoDownloader` | yes | yt-dlp 优先；地区/登录 |
| Reddit | `RedditDownloader` | yes | yt-dlp 优先 |
| Rumble | `RumbleDownloader` | yes | yt-dlp 优先 |
| Soundcloud | `SoundcloudDownloader` | yes | yt-dlp 优先 |
| TikTok | `TikTokDownloader` | yes | 原生候选（去水印/登录） |
| Twitch | `TwitchDownloader` | yes | yt-dlp 优先 |
| Twitter | `TwitterDownloader` | yes | 原生候选（登录/限流） |
| Udemy | `UdemyDownloader` | yes | yt-dlp 优先；登录 |
| Vimeo | `VimeoDownloader` | yes | yt-dlp 优先 |
| Wavve | `WavveDownloader` |  | 需复核 DRM/登录 |
| Weibo | `WeiboDownloader` | yes | yt-dlp 优先 |
| WeTV | `WeTVDownloader` | yes | yt-dlp 优先；地区/登录 |
| Youku | `YoukuDownloader` | yes | yt-dlp 优先；地区/登录 |
| YouTube | `YouTubeDownloader` | yes | 原生候选（PO Token/SABR/JS Challenge） |

> 完整矩阵：`~/re/downie4/reports/site-coverage-matrix.csv`（786 行）。该矩阵是启发式结果，域名、DRM、登录方式仍需逐站复核。

### 4.4 登录与 Token

- 登录统一走 WebView（WKWebView/WebView2），保存 Netscape cookie，按站点隔离。
- 解析/下载失败出现 cookie/login/sign in/登录/验证等关键词时，触发重新登录。
- Token/挑战按站实现：
  - 抖音：`a_bogus`、`msToken`、`ttwid`（当前插件已覆盖主要路径）。
  - B站：WBI 签名（已实现）、buvid、cookie。
  - YouTube：PO Token、JS Challenge、SABR（未实现）。
  - 其他：X-Bogus、signature、时间戳/随机数、站点专用 header。
- 原则：优先用公开算法思路按行为重写；需要 DOM 的用隐藏 WebView；token 算法会变，必须监控失败率。

### 4.5 DRM 边界

Downie 二进制中的证据：

- `_drmProtectedHosts` 包含 `netflix.com`。
- 字符串：`This video is DRM protected and cannot be downloaded.`、`DASH manifest contains DRM protection:` 等。
- 结论：Netflix 正片、Disney+、Prime Video 等 DRM 内容不在复刻范围；预告片/公开花絮等非 DRM 片段不受影响。

---

## 5. 授权系统 v2

### 5.1 目标模型

- 14 天全功能试用，服务端记录，卸载重装不能重置。
- 邮箱验证 + 授权码绑定；授权码只存哈希。
- 默认 4 台活跃设备，支持反激活/设备列表/管理员重置。
- 服务端用 Ed25519 签发令牌；客户端内置公钥离线验签。
- 付费版 7 天心跳、试用 1–3 天；离线宽限付费 14 天、试用 3 天。
- 退款/共享/滥用 → 暂停或撤销，心跳下发。
- 客户端存储：macOS Keychain、Windows DPAPI；不写明文。
- 授权接口走 HTTPS，限流 + 防枚举；管理端真正校验管理员权限。

### 5.2 现状（未改）

- 现有 `/api/license/*` 是数据库卡密 + 明文 JSON；桌面端 PRO 状态在明文 Hive。
- 没有邮箱、试用、签名令牌、心跳/撤销下发；服务端不校验到期。
- `/api/license/unbind` 有事务问题；错误契约不匹配，失败常显示“网络错误”。
- 授权请求仍是明文 HTTP；移动端不发送授权头，服务端缺头放行。
- 详细设计见 `~/re/downie4/reports/licensing-v2-design.md`。

### 5.3 实施顺序

1. 服务端：邮箱验证码、试用表、授权 token、设备席位、心跳/撤销、审计；HTTPS。
2. 客户端：Keychain/DPAPI 存储、离线验签、宽限、到期/撤销 UI。
3. 管理端：设备列表、反激活、重置、延长试用、撤销。
4. 迁移：保留现有 `/api/license/*` 契约，新增 v2 接口，避免破坏已发布客户端。

---

## 6. UI / UX

- 目标：布局/信息架构/操作路径对齐 Downie 4；视觉资产由项目方提供/自研，不复制 Downie 的 nib/图片/文案。
- Downie 4 实际主窗口（来自 App 自带 Help 截图）：
  - 无侧边栏、无顶部工具栏；深色原生窗口约 600×420；空状态中央大 logo；底部状态栏显示计数和操作。
  - 下载项是全宽缩略图行，标题/URL/画质/后处理/操作都叠在行内；没有独立详情面板。
  - 偏好设置是独立「All Preferences」窗口，12 个图标分 3 行：General/Appearance/Destination/History/Browser Extensions；Postprocessing/Subtitles & Audio/Proxy Server；Supported Sites/Search Engines/Parental Controls & Privacy/Advanced。
  - 历史是独立简单列表窗口；菜单有 File > Open URLs、Window > Show History、Downie > Settings、Browser > Login Browser。
- 当前状态（2.0.7）：侧边栏 + 顶部工具栏 + Material 卡片 + 首页解析页；与 Downie 差距大，需要按第 12 节重做。
- 已完成：中文帮助/支持（17 主题，邮箱 `huoyongzhuang@qq.com`）、品牌/DMG/EXE 发布链。
- 待做：无侧边栏主窗口、全宽下载行、底部状态栏、12 图标偏好、历史/帮助浮层、菜单/快捷键、Windows 适配。
- 旧 UI 计划 `docs/downie5-ui-plan.md` 仅保留为历史参考，以第 12 节为准。

---

## 7. 分期与当前进度

| 阶段 | 内容 | 估算 | 当前状态 |
|---|---|---|---|
| Phase 0 | 架构定稿、插件接口、WebView PoC、授权 API 设计、CI/测试 | 1–2 周 | 部分完成：插件接口/发布链/测试已有；HTTPS、签名、统一 bundle id 未做 |
| Phase 1 | 下载引擎抽象 + 5–10 站 + macOS 跑通 | 3–6 周 | 部分完成：插件层 + 抖音/B站 + FFmpeg HLS/DASH；原生分片引擎未完成 |
| Phase 2 | Windows 平台层、WebView2、本地服务、扩展 | 3–5 周 | 部分完成：Windows 构建/安装包/WebView2 依赖已有；扩展/本地服务未做 |
| Phase 3 | 授权 v2（试用/邮箱/设备/撤销/管理端） | 3–6 周 | 设计完成，未实现 |
| Phase 4 | 自定义集成、字幕/后处理、Top 30、UI 打磨 | 3–6 周 | 安装体验已完成；UI 需按第 12 节重做 |
| 持续 | 站点维护、token 更新、双端兼容、签名发布 | 长期 | 进行中 |

**现实预期**：核心引擎 + 30 站 + 双端 + 授权约 **3–5 人月**；接近 Downie 全站覆盖是人年级 + 持续维护。

---

## 8. 验收标准

### 8.1 下载能力

- Top 30 非 DRM 站点：解析 + 下载端到端成功率可统计，目标 ≥ 90%（按站点单独统计）。
- 直链、HLS、DASH、分片、断点续传、音视频合并可用。
- 需要登录的站点能弹 WebView 登录并复用 cookie。
- DRM 站点明确提示“不支持 DRM”，不静默失败。
- 失败可回退 yt-dlp；仍失败时给出可读错误和日志。

### 8.2 授权

- 14 天试用、邮箱验证、授权码激活、4 设备、反激活、找回、撤销全链路可用。
- 客户端不存明文 PRO；离线宽限和服务端时间校验生效。
- 授权接口 HTTPS；错误契约与客户端一致。

### 8.3 发布

- macOS DMG 可挂载、可拖入 Applications、安装说明可打开。
- Windows 安装包可安装/卸载/升级，WebView2 缺失时能引导安装。
- 版本接口能驱动更新提示；OSS 固定文件名可下载。
- 按用户决定不做 macOS 签名/公证和 Windows 代码签名；安装说明保留右键打开/“仍要运行”步骤。

### 8.4 质量

- CI 双端构建 + 单元测试；关键插件有回归测试。
- 站点失败率/错误码可观测，便于补站。
- 代码不包含明文密钥、授权码、服务器密码。

---

## 9. 风险与应对

| 风险 | 影响 | 应对 |
|---|---|---|
| 站点改版/反爬升级 | 插件失效 | 失败率监控 + 快速补丁 + yt-dlp 兜底 |
| Token 算法变化 | 抖音/YouTube 等失效 | 按站隔离实现 + 隐藏 WebView/Node 运行时 |
| 786 站长尾 | 永远做不完 | Top 30 + 通用嗅探 + 自定义集成，不承诺全量 |
| DRM 内容 | 无法下载 | UI 明确提示，不绕过 |
| 站点 ToS/版权 | 法律风险 | 只处理用户有权访问的内容；商业上线前法务评估 |
| Windows SmartScreen/杀软 | 安装受阻 | 不做代码签名；安装说明提示“更多信息 → 仍要运行” |
| macOS Gatekeeper | 首次打开被拦 | 不做公证；安装说明给右键打开/仍要打开步骤 |
| 授权被改本地文件 | 收入损失 | 签名令牌 + Keychain/DPAPI + 服务端校验 |
| 维护成本 | 长期人力 | 插件 SDK、站点更新流水线、自动化回归 |

---

## 10. 相关文档与原始清单

- `~/re/downie4/reports/feasibility.md`：REA 可行性、二进制/符号/源路径证据
- `~/re/downie4/reports/product-plan.md`：双端 + 授权总体方案
- `~/re/downie4/reports/gap-analysis.md`：现状差距与迁移路线
- `~/re/downie4/reports/site-coverage-strategy.md`：站点覆盖策略
- `~/re/downie4/reports/site-coverage-matrix.md` / `.csv`：786 站点矩阵
- `~/re/downie4/reports/licensing-v2-design.md`：授权 v2 详细设计
- `~/re/downie4/reports/downloaders.txt`：786 个下载器类名
- `~/re/downie4/reports/source-paths.txt`：630 个 Swift 源文件路径
- `docs/downie5-ui-plan.md`：当前 UI 计划
- `docs/architecture.md`：跨端架构
- `docs/roadmap.md`：产品路线（部分内容较早，本文以当前进度为准）

---

## 11. 下一步（按优先级）

1. **授权 v2**：先做服务端 token/试用/设备，再改客户端存储和心跳；这是商业上线的前置条件。
2. **原生下载引擎**：`DownloadStrategy` + HLS/DASH/chunk 调度 + 断点续传，减少对 yt-dlp 的依赖。
3. **Top 10 站点**：在抖音/B站之外补 YouTube、Instagram、TikTok、X、快手等高频站。
4. **浏览器扩展 + 本地 HTTP 服务**：把“浏览器里看到视频 → 应用下载”的路径打通。
5. **字幕/后处理/自定义集成**：补齐 Downie 的高级功能面。
6. **站点运营**：失败率监控、插件 SDK、站点更新流水线。

> 签名/公证/代码签名已按用户决定移出路线图，不再列入待办。

---

## 12. Downie 4 高保真 UI 重做 + 14 天试用实施计划

- **状态**：2026-10-26 设计稿，待实施
- **依据**：Downie 4 v4.13.3 自带 Help Book 截图 + 主窗口/偏好设置 nib/字符串 + 当前 Flutter 代码审计
- **已确认决策**：14 天全功能试用、取消每日免费次数、前后端一起改；偏好设置做完整 12 图标网格 + 占位；设置/历史/帮助用单 OS 窗口 + 窗样式浮层。

### 12.1 参考截图（只读）

目录：`/Applications/Downie 4.app/Contents/Resources/DownieHelp.help/Contents/Resources/English.lproj/`

- `main_window.png`：空主窗口
- `processed.png`：一条下载记录
- `error.png`：错误状态
- `preferences.png`：All Preferences 图标网格
- `menu_bar_item.png`：菜单栏 popover
- `unsupported.png`：不支持链接 sheet

Downie 主窗口不是主 nib 构建的，Help Book 截图是当前最可靠的视觉参考；要像素级接近，实施第一步需运行 Downie 截 1x/2x 图并量取颜色/尺寸。

### 12.2 差距表

| 区域 | 当前 | Downie 4 | 严重度 | 改法 |
| --- | --- | --- | --- | --- |
| 主框架 | 244/224px 侧边栏 + 56px 顶栏 | 无侧边栏/无顶栏 | 高 | 删除侧边栏，改标题栏 + 内容 + 底部状态栏 |
| 窗口 | 1100×750，普通标题栏 | 约 600×420，深色原生 | 高 | 默认 640×440、最小 560×380、hidden title bar |
| 首页 | 解析表单 + PRO 横幅 | 队列主窗口 | 高 | 首页改队列；添加 URL 改 +/剪贴板/Open URLs 浮层 |
| 下载行 | 卡片 + 状态图标 + 进度条 | 全宽缩略图 + 覆盖控件 | 高 | 新 `DownloadRow`，缩略图 banner + overlay |
| 详情 | 无 | 行内控件即详情 | 中 | 不新增详情面板，画质/后处理/操作放行内 |
| 底部栏 | 无 | 状态栏 + 操作 + 计数 | 高 | 新 `StatusBar` |
| 设置 | 长滚动 Card 列表 | 12 图标网格 + 面板 | 高 | 新 Preferences 浮层 |
| 历史 | 页面列表 | 独立简单窗口 | 中 | 窗样式浮层，复用 history provider |
| 菜单/快捷键 | 基本没有 | File/Window/Browser/Help + ⌘ | 高 | PlatformMenuBar + Shortcuts/Actions |
| 帮助/支持 | 大 Modal | Help Book / 支持窗口 | 中 | 窗样式浮层，保留中文主题 |
| 授权 | PRO 横幅 + 每日 2 次 | 14 天试用 + 授权窗口 | 高 | 去每日额度；前后端 14 天试用 |
| 视觉 | Material 3 紫色/卡片 | 深色原生/系统蓝/紧凑 | 高 | 设计 token + 自定义组件，禁用 ripple/Card |

### 12.3 主窗口

- 默认 **640×440**，最小 **560×380**；标题栏 32–34px；底部状态栏 32px。
- macOS：`TitleBarStyle.hidden`，保留红黄绿交通灯；32px 拖拽区 + 居中标题；内容延伸到标题栏下方。
- Windows：自绘 32px caption（左图标/标题，右最小化/最大化/关闭）；双击最大化；Segoe UI / Microsoft YaHei UI。
- 空状态：中央 `assets/logo.png` 灰度/低透明度约 120px，不加说明文字；状态栏中间显示「暂无下载」。
- 主体：全宽下载行纵向列表；无侧边栏、无顶栏、无会员横幅。
- 底部状态栏：
  - 左：`+` 添加、打开下载目录、清空已完成；
  - 中：`N 个下载` / `暂无下载`；
  - 右：搜索/网页嗅探、用户引导提取、历史、帮助、支持；
  - 更新红点/版本收进「关于/帮助」或最右侧小入口。

### 12.4 下载行与添加链接

- 行高 140–160px（最小 120），全宽；缩略图 `BoxFit.cover`，无图用深色渐变 + 品牌水印。
- 顶部/底部黑色渐变遮罩；标题 15/600，站点/URL 11px；右上取消 ×；左下播放/暂停、后处理下拉、画质下拉、Actions、齿轮。
- 底部 2px 进度条 + 状态文字（百分比/速度/ETA/阶段）；完成显示打开文件/目录；失败显示红色错误 + 重试；后处理显示阶段进度。
- 行内下拉用深色 popup 样式，不用 Material `DropdownButtonFormField` 默认外观。
- 不新增详情面板；`DownloadTask`/`DownloadProgress` 已够用，补充 `availableFormats`/`selectedFormat`/`postprocessing`/`priority`。
- 添加链接：`+` 有剪贴板 URL 直接入队，否则打开 `AddUrlsPanel`（约 520×360 深色浮层，多行输入/粘贴/解析）；`File > Open URLs…` 同一面板；支持拖拽和 ⌘V/Ctrl+V。
- 解析后直接生成队列行，默认最佳画质，行内可改画质/后处理；不再有独立解析结果卡片。

### 12.5 偏好设置与次级页面

- Preferences 窗样式浮层约 660×400；工具栏 44px，网格图标 +「全部设置」；进入面板后返回箭头 + 标题。
- 12 图标分 3 行、带分隔线：
  - 通用 / 外观 / 下载位置 / 历史记录 / 浏览器扩展
  - 后处理 / 字幕与音频 / 代理服务器
  - 支持站点 / 搜索引擎 / 家长控制与隐私 / 高级
- 已实现面板复用 `settings_provider`：并发、自动开始、打开目录、默认画质、主题、下载目录、保留数量、站点列表、yt-dlp 更新等。
- 未实现面板显示「开发中」占位，保持 12 图标完整。
- 授权不放进 12 图标；应用菜单「授权…」打开独立授权/试用窗口。
- 历史约 600×420，简单行列表 + reveal/删除/清空/右键原始链接；帮助约 760×560，保留 17 个中文主题/搜索/支持；支持约 700×500，保留邮箱 `huoyongzhuang@qq.com`。
- 登录/网页嗅探/用户引导提取沿用现有 WebView，改成深色窗样式并适配 560×380 最小窗口。

### 12.6 菜单、Windows 与设计 token

- macOS `PlatformMenuBar` 或改 `MainMenu.xib` 接 action：
  - 应用菜单：关于、设置…（⌘,）、授权…、检查更新、退出；
  - 文件：打开链接…（⌘O）、清空已完成、关闭窗口；
  - 编辑：粘贴并添加（⌘V）、全选；
  - 浏览器：登录浏览器…、用户引导提取…；
  - 窗口：历史记录（⌘⇧H）、主窗口；
  - 帮助：帮助、报告问题。
- Windows：自绘菜单栏或 caption 下 `MenuBar`，快捷键用 Ctrl 对应；列表 Delete/Space/↑↓/⌘F 搜索队列。
- Windows：同一深色布局，自绘 caption 按钮，Segoe UI / Microsoft YaHei UI；第一版用实色，Mica/Acrylic 可选；验证 100–150% DPI。
- 新 `lib/shared/theme/design_tokens.dart`：
  - 深色：`window #1E1E1E`、`titleBar #2A2A2A`、`statusBar #181818`、`panel #242424`、`divider #3A3A3A`、`textPrimary #F5F5F5`、`textSecondary #A0A0A0`、`accent #0A84FF`、`error #FF453A`、`success #30D158`；
  - 间距 2/4/6/8/12/16/20/24/32；圆角 4/6/8/10/12；图标 14/16/18/20/24；
  - 字体 macOS `.SF Pro Text`/`PingFang SC`，Windows `Segoe UI`/`Microsoft YaHei UI`；
  - 标题 13/600、行标题 15/600、meta 11/400、状态栏 11/500、面板标题 20/600、正文 13/400；
  - 去 Card 阴影/边框、`NoSplash`、紧凑 density、自定义 hover/pressed；图标用 SF Symbols 风格（`cupertino_icons`，必要时加依赖），不复制 Downie 图标资源。

### 12.7 授权：14 天试用 + 去每日额度

**Downie 证据**：`Licensing.framework` 有 `CMTrialHeaderView`、`CMTrialProgressBar`、`%i days`、`Continue Trial`、`Enter License Code…`、`Lost License Code?`、`Deactivate License Code…`；帮助写明默认激活次数 3。只借鉴用户可见流程，不复用 Paddle 协议/密钥/授权码格式。

#### 产品规则

- 14 天全功能试用，从首次启动/设备注册开始，服务端记录；卸载重装不能重置。
- 删除客户端/服务端每日免费次数；试用期内不限下载次数。
- 试用到期禁止新下载，保留历史/设置/帮助；弹出授权窗口。
- 付费：邮箱 + 授权码，默认 4 台活跃设备；反激活/设备列表/找回/撤销；离线宽限付费 14 天、试用 3 天；服务端时间；Ed25519 签名 token；Keychain/DPAPI。

#### 客户端

- 新 `LicenseWindow`（约 480×360 窗样式浮层）：试用进度条 + 剩余天数、继续试用、邮箱 + 授权码、找回授权码、反激活、设备列表、到期文案。
- `license_provider.dart` 删除 `dailyQuota`/`todayUsed`/`todayRemaining`/`isQuotaReached`/`recordSuccess`/`acquireSlot`/`maxHeight` 配额 provider；新增 `TrialStatus`/`LicenseStatus`/`daysRemaining`/`deviceId`/`canDownload`；启动请求 trial/status，离线走缓存。
- `license_client.dart` 增加 trial/status、trial/start、activate(email)、deactivate、recover；保留旧接口。
- 引入 `flutter_secure_storage` 保存签名 token；旧 Hive 数据一次性迁移。
- 移除首页 PRO/免费次数横幅；授权入口放应用菜单/状态栏小入口。

#### 服务端

- 现有表 `licenses`/`device_bindings`/`unbind_log` 与 `/api/license/*` 契约不能破坏（老客户端在外）。
- 新增 `trial_devices`（device_fp、first_seen、trial_start、trial_end、email、status、last_seen）；`licenses.email` 或 `license_emails`；Ed25519 私钥放环境变量。
- 新接口：`GET /api/license/trial/status`、`POST /api/license/trial/start`、`POST /api/license/activate`（扩展 email）、`POST /api/license/deactivate`、`POST /api/license/recover`、`POST /api/license/heartbeat`。
- 服务端强制到期/撤销/设备上限；统一顶层 `ok/error/message`；移除每日次数；管理端试用/设备/撤销/延长试用。
- 迁移：现有付费卡密继续有效；schema 增量迁移，不重建表。

### 12.8 实施阶段

| 阶段 | 内容 | 估算 |
| --- | --- | --- |
| Phase 0 | 截 Downie 参考图并量取；`design_tokens`/主题；`WindowShell`/标题栏/状态栏；空主窗口；删侧边栏 | 2–3 天 |
| Phase 1 | `DownloadRow` 全宽行；主队列；`AddUrlsPanel`/剪贴板/拖拽/⌘V；行内画质/后处理；底部栏接线 | 4–6 天 |
| Phase 2 | Preferences 12 图标网格 + 面板 + 占位；History/Help/Support/登录/嗅探窗样式 | 3–5 天 |
| Phase 3 | 14 天试用后端 + 客户端 + LicenseWindow + 安全存储 + 删每日额度（可与 Phase 1 并行） | 1–2 周 |
| Phase 4 | 菜单/快捷键/右键；Windows caption/字体/DPI；golden/截图/CI/回归 | 3–5 天 |
| 可选 | 真正多窗口（`desktop_multi_window`） | 后续 |

### 12.9 文件级改动

| 区域 | 文件 |
| --- | --- |
| 窗口/主题 | `lib/main.dart`、`lib/app.dart`、`lib/shared/theme/app_theme.dart`、新建 `lib/shared/theme/design_tokens.dart` |
| 主框架 | `lib/shared/widgets/app_shell.dart` → 新建 `window_shell.dart`/`window_title_bar.dart`/`status_bar.dart` |
| 主队列 | `lib/features/downloads/downloads_page.dart`、新建 `widgets/download_row.dart`/`widgets/download_overlay_controls.dart` |
| 添加链接 | 新建 `lib/features/downloads/add_urls_panel.dart`；`home_provider.dart` 抽 `AddUrlsController`；`home_page.dart` 退役 |
| 模型/状态 | `lib/data/models/download_task.dart`、`lib/features/downloads/download_provider.dart` |
| 偏好 | 新建 `lib/features/preferences/preferences_window.dart`、`panes/*.dart`；复用 `settings_page.dart`/`settings_provider.dart` |
| 历史 | `lib/features/history/history_page.dart` → `history_window.dart` |
| 帮助/支持 | `lib/features/help/help_window.dart`、`support_dialog.dart` |
| 授权 | `lib/features/license/license_card.dart` → `license_window.dart`；`license_provider.dart`；`lib/core/license/license_client.dart` |
| 服务端 | `services/api/app/modules/license/{models,router,service}.py`、`sql/schema.sql`、迁移脚本 |
| 管理端 | `apps/admin-web/src/views/*`（试用/设备/撤销，可 P2） |
| 菜单 | `lib/app.dart`、新 `menus.dart`、`macos/Runner/Base.lproj/MainMenu.xib` |
| 测试 | `test/` 新增 widget/golden；现有插件/单元测试保持 |

### 12.10 验证与风险

- **视觉**：同一 640×440 截图与 `main_window.png`/`processed.png`/`preferences.png` 并排；检查无侧边栏/顶栏、底部栏、行布局、偏好网格。
- **功能回归**：URL 解析、抖音/B站插件、网页嗅探、队列/重试/取消、历史、设置、帮助/支持、更新提示。
- **授权**：首次启动 14 天；到期禁止新下载；激活/反激活/找回；离线宽限；改时钟不延长；老客户端接口不坏。
- **双端**：macOS 交通灯/拖拽区/菜单；Windows caption/最小化/最大化/关闭/DPI 100–150%。
- **自动化**：`flutter analyze`/`flutter test`（本机当前无 Flutter，用 CI）、现有插件测试、新增 widget/golden、双端 CI 构建。
- **风险**：布局接近 ≠ 复制资产；单窗口浮层不是真 NSWindow；14 天试用改造跨度大，先设计迁移；删每日额度要客户端/服务端同步；640×440 对长标题/中文需实测；Windows 自绘 caption 与 DPI 有细节差异。

---

## 附录：术语与边界

- **REA**：Reverse Engineer Anything，驱动 Ghidra/Hopper/IDA 的 MCP/CLI；本身不是反编译器。
- **Clean-room**：只根据行为、公开接口和静态结构独立实现，不复制源码/资源。
- **DRM**：Digital Rights Management；本方案不破解 Widevine/FairPlay/PlayReady。
- **Top 30**：按使用频率和维护价值选出的首批站点，不是 Downie 全量清单。
