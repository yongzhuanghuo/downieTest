# REA 反编译 Downie 4 与完整复刻规划

- **文档状态**：可执行规划 v1
- **对标基线**：Downie 4 v4.13.3（`CFBundleVersion` 4000，`com.charliemonroe.Downie-4`）
- **当前产品**：Downie6 v2.0.7+8（Flutter，macOS + Windows）
- **更新日期**：2026-10-24
- **详细分析底稿**：`~/re/downie4/reports/`（本文是汇总版，底稿不在仓库）

---

## 0. 结论（先看这里）

1. **可以做到“功能对标”**：Downie 能下载的非 DRM 内容，我们可以用独立实现做到同类能力。
2. **做不到“源码级复刻”**：REA 目前只完成了 Mach-O、符号、字符串、资源层面的静态分析；Ghidra/Hopper 尚未安装，没有逐函数反编译，也拿不到原始 Swift 工程。
3. **不支持 DRM 正片**：Netflix / Disney+ / Prime Video 等 Widevine/FairPlay/PlayReady 内容，Downie 自己也明确拒绝下载。这不是我们没做，而是不在范围。
4. **786 个下载器类不能靠一次性交付**：正确目标是 Top 20–30 + 通用 WebView 嗅探 + 自定义集成 + yt-dlp 兜底，然后按失败率持续补站。
5. **当前进度**：Downie 风格 UI、DMG/EXE 发布链、抖音/B站插件、通用网页嗅探已完成；原生下载引擎只完成了一部分；授权 v2、浏览器扩展、自定义集成、Top 30 站点覆盖仍未完成。

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
| 下载管理 | 队列、历史、断点续传、失败重试、播放列表、链接过滤、下载调试器 | 部分：队列/历史/重试/续传已有；播放列表/过滤/调试器未做 |
| 站点识别 | 每站下载器、通用抓取（UGE）、引导式提取、站点管理、URL 报告 | 部分：插件框架 + 抖音/B站 + 通用嗅探；Top 30 未覆盖 |
| 媒体处理 | HLS/DASH/HTTP 分片、音视频分离、画质、字幕、ffmpeg 合并/转码、自定义后处理 | 部分：FFmpeg HLS/DASH/直链下载；原生分片调度、字幕、后处理未完成 |
| 登录/网络 | Cookie/登录助手、代理、本地 HTTP 服务、IP 转发 | 部分：WebView 登录 + cookie；扩展/本地服务/代理未做 |
| UX | 浏览器扩展、剪贴板/拖拽、通知、外观、导入 | 部分：Downie 风格主界面 + 中文帮助/支持；扩展/拖拽/通知未做 |
| 高级 | 自定义集成（Registry/提交/控制台/JS 执行）、快速预览 | 未开始 |
| 授权 | 15 天试用、邮箱绑定、4 设备、反激活、找回、撤销 | 设计完成，未实现；线上仍是旧授权 |
| 发布 | macOS/Windows 安装包、更新提示、OTA/OSS | 已完成 DMG + EXE + OSS + 版本接口；签名/公证未做 |

### 2.2 明确不做

- 不破解 Widevine / FairPlay / PlayReady。
- 不复制 Downie 的源码、资源、nib/storyboard、文案、授权协议或密钥。
- 不承诺 786 个站点在某个时间点全部支持；这是持续维护目标。
- 不绕过付费内容或账号权限；只使用用户本人有权访问的登录态。

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
| 签名 | Developer ID + notarization | Authenticode（建议 EV） |
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

- 15 天全功能试用，服务端记录，卸载重装不能重置。
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

- 目标：对齐 Downie 的信息架构和操作路径，视觉资产由项目方提供/自研，不复制 Downie 的 nib/图片/文案。
- 已完成：
  - Downie 风格主框架：侧边栏 + 顶部工具栏 + 内容区。
  - 中文帮助窗口（17 个主题）+ 搜索。
  - 支持/报告窗口，收件邮箱 `huoyongzhuang@qq.com`。
  - 设置页「帮助与支持」；品牌名/图标集中配置。
  - DMG 安装窗口：左侧安装说明，右侧应用，双击说明查看步骤。
- 待做：
  - 主下载列表 + 详情面板的最终布局。
  - 偏好设置分类页、授权/设备管理页。
  - Windows 菜单栏、快捷键、通知。
  - 浏览器扩展/拖拽导入/剪贴板监听。
- UI 计划详见 `docs/downie5-ui-plan.md`。

---

## 7. 分期与当前进度

| 阶段 | 内容 | 估算 | 当前状态 |
|---|---|---|---|
| Phase 0 | 架构定稿、插件接口、WebView PoC、授权 API 设计、CI/测试 | 1–2 周 | 部分完成：插件接口/发布链/测试已有；HTTPS、签名、统一 bundle id 未做 |
| Phase 1 | 下载引擎抽象 + 5–10 站 + macOS 跑通 | 3–6 周 | 部分完成：插件层 + 抖音/B站 + FFmpeg HLS/DASH；原生分片引擎未完成 |
| Phase 2 | Windows 平台层、WebView2、本地服务、扩展 | 3–5 周 | 部分完成：Windows 构建/安装包/WebView2 依赖已有；扩展/本地服务未做 |
| Phase 3 | 授权 v2（试用/邮箱/设备/撤销/管理端） | 3–6 周 | 设计完成，未实现 |
| Phase 4 | 自定义集成、字幕/后处理、Top 30、UI 打磨 | 3–6 周 | UI 框架/安装体验已完成；其余未做 |
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

- 15 天试用、邮箱验证、授权码激活、4 设备、反激活、找回、撤销全链路可用。
- 客户端不存明文 PRO；离线宽限和服务端时间校验生效。
- 授权接口 HTTPS；错误契约与客户端一致。

### 8.3 发布

- macOS DMG 可挂载、可拖入 Applications、安装说明可打开。
- Windows 安装包可安装/卸载/升级，WebView2 缺失时能引导安装。
- 版本接口能驱动更新提示；OSS 固定文件名可下载。
- macOS Developer ID + notarization；Windows Authenticode（上线前）。

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
| Windows SmartScreen/杀软 | 安装受阻 | 代码签名、避免加壳、建立下载信誉 |
| macOS Gatekeeper | 首次打开被拦 | Developer ID + notarization；安装说明给右键打开步骤 |
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
6. **签名与公证**：macOS notarization、Windows Authenticode，解决 Gatekeeper/SmartScreen。
7. **站点运营**：失败率监控、插件 SDK、站点更新流水线。

---

## 附录：术语与边界

- **REA**：Reverse Engineer Anything，驱动 Ghidra/Hopper/IDA 的 MCP/CLI；本身不是反编译器。
- **Clean-room**：只根据行为、公开接口和静态结构独立实现，不复制源码/资源。
- **DRM**：Digital Rights Management；本方案不破解 Widevine/FairPlay/PlayReady。
- **Top 30**：按使用频率和维护价值选出的首批站点，不是 Downie 全量清单。
