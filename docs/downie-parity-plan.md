# Downie 4 功能 1:1 复刻执行计划

- **基线**：Downie 4 v4.13.3（`com.charliemonroe.Downie-4`，build 4000）
- **当前产品**：Downie6 2.0.26+27（Flutter，macOS + Windows）
- **分析方式**：REA + Mach-O 符号 / 字符串 / Swift 元数据 / 内置 Help Book / Localizable.strings；不做源码复制
- **站点全量表**：[site-coverage.md](site-coverage.md)（786 行） / [site-coverage.csv](site-coverage.csv)
- **更新日期**：2026-10-27

---

## 0. 先说清楚三件事

### 0.1 “786 个站点”不是 786 个独立页面

DownieCore 里有 786 个 `*Downloader` 类/变体，包含：

- 基类/抽象类（`Base`、`Configuration`）
- 同站变体（直播/音频/番剧/嵌入/短链/旧版）
- 需要登录、地区、Token 的站点
- DRM 站点（Downie 自己也会拒绝）

所以“复刻”分两个指标，不能混：

| 指标 | 含义 | 当前 |
|---|---|---|
| **功能可用** | 用户给一个链接，能解析、选画质、下载、合并 | 原生 9 + yt-dlp 299（待逐站验证）+ 通用资源检测 472（兜底） |
| **代码原生复刻** | 我们自己的插件按站点行为实现，不依赖 yt-dlp | 5 个引擎：抖音、B 站（普通/嵌入/番剧整季）、TikTok、快手、微博 |

### 0.2 为什么不把 786 个下载器逐个抄一遍

- Downie 是编译后的 Swift，没有源码可抄；只能按符号/字符串/行为重写。
- 786 个类里大量是变体和基类，不是 786 份独立解析逻辑。
- 站点改版频繁；原生代码越多，维护成本越高。能由 yt-dlp 稳定覆盖的站点，重复造轮子反而更容易坏。
- 正确目标是：**每个非 DRM 站点至少有一个可验证的下载引擎**；对 yt-dlp 覆盖差、登录/Token 关键、体验不达标的站点做原生复刻。

### 0.3 “他们能下，我们也能下”的落地方式

每个非 DRM 站点按以下顺序路由：

```
原生插件（最优，行为可控）
  → yt-dlp 站点提取器（覆盖长尾）
  → 通用 HTML 提取（og:video / JSON-LD / <video>）
  → 自动资源检测（WebView 抓 m3u8/mpd/mp4，2.0.18 新增）
  → 自定义集成（后续，JS 规则）
```

任何一层成功即可下载；失败时 UI 必须告诉用户失败在哪一层，而不是只报“不支持”。

---

## 1. 站点覆盖现状（全量见 site-coverage.md）

### 1.1 统计

| 状态 | 数量 | 含义 | 是否算“复刻完成” |
|---|---:|---|---|
| 原生插件 | 9 | 抖音、B 站普通视频、B 站嵌入播放器、B 站番剧（ep 单集 / ss 整季）、iesdouyin、TikTok、快手、微博/H5 | 部分已验证 |
| yt-dlp | 299 | 由 yt-dlp 负责；功能可用但未逐站验证 | 否（功能覆盖） |
| 通用资源检测（未复刻） | 472 | 没有原生/已知 yt-dlp 提取器；靠自动嗅探 | 否 |
| DRM（不支持） | 6 | Disney/Apple 等 DRM 正片 | 不适用（Downie 也不下） |

> 表里的 `yt-dlp` 是“功能覆盖”，不是“代码复刻”。我们要的是前者先达标，再按优先级把关键站点升级为后者。

### 1.2 已原生复刻

| 站点 | 覆盖链接 | 实现 | 状态 |
|---|---|---|---|
| 抖音 | `douyin.com/video`、`iesdouyin.com/share/video`、短链 | WebView 持续捕获 `aweme/detail` + media 分轨兜底 | 2.0.17 已验证可下载 |
| B 站普通视频 | `bilibili.com/video/BV/av`、`b23.tv` | WBI 签名 + DASH + ffmpeg 合并；2.0.22 支持多 P 展开 | 已实现，待样本回归 |
| B 站嵌入播放器 | `player.bilibili.com?bvid=/aid=` | 归一化为普通视频链接 | 2.0.19 已实现，待样本回归 |
| B 站番剧 | `/bangumi/play/ep`、`/bangumi/play/ss` | PGC 接口；ss 默认第一集，展开播放列表时整季逐集入队 | 2.0.20 已实现整季展开，待真实下载回归 |
| TikTok | `tiktok.com/@user/video`、`vm/vt.tiktok.com` 短链 | 页面 hydration + 无水印 bitrateInfo + 桌面 UA/Referer | 2.0.19 原生实现，单测通过，待真实下载回归 |
| 快手 | `kuaishou.com/short-video/<id>`、`v.kuaishou.com` 短链 | `__APOLLO_STATE__` 的 VisionVideoDetailPhoto 节点 | 2.0.20 原生实现，单测通过，待真实下载回归 |
| 微博 | `weibo.com/tv/show/<fid>`、`h5.video.weibo.com/show/<fid>`、正文链接 | `ajax/statuses/show` + media_info/stream_url；需要登录 cookie | 2.0.20 原生实现，单测通过，待真实登录回归 |

### 1.3 P0 站点（35 个）状态

完整表见 [site-coverage.md](site-coverage.md) 的 P0 段。摘要：

- 原生：Bilibili（普通/嵌入/番剧）、Douyin、TikTok、Kuaishou、Weibo
- yt-dlp：其余 P0 大部分
- 需要重点验证：YouTube（PO Token/SABR）、Instagram、TikTok、X、Twitch、Facebook、Weibo、Youku、WeTV、Udemy（登录/限流/地区）

### 1.4 我们明确不做的

- Netflix / Disney+ / Prime Video / Hulu 等 DRM 正片（Downie 也拒绝）
- 复制 Downie 的源码、nib、图片、文案、Paddle/授权协议
- 绕过付费内容或账号权限
- 承诺某个日期前 786 个全部原生复刻；这是持续维护项目

---

## 2. 站点覆盖执行计划

### S0 — 可见的覆盖矩阵 + 自动嗅探（本批，2.0.18）

- [x] 全量 786 行站点表：`docs/site-coverage.md` / `.csv`
- [x] 生成脚本：`apps/desktop/tools/generate_site_coverage.py`
- [x] 应用内「设置 → 支持站点」：搜索、按状态筛选、显示原生/yt-dlp/未复刻/DRM
- [x] 自动资源检测：无法解析时用 WebView 抓 m3u8/mpd/mp4，自动选最佳地址并下载
- [x] 通用捕获增强：`<video>` / `<source>` / og:video / JSON-LD / performance / 播放触发
- [x] 样本链接验证工具：`apps/desktop/tools/verify_site_samples.py`（样本 CSV 由 S1 逐站补）
- [ ] 失败率记录：按站点记录“解析失败 / 下载失败 / 登录失效”，作为下一批原生站的依据

**验收**：`设置 → 支持站点` 能看到 786 行；搜索 `douyin`/`youtube` 有结果；状态筛选正确；自动检测能对一个 yt-dlp 不支持的测试页抓到媒体并下载。

### S1 — P0 35 站逐站验证 + 修复（2.0.19–2.0.21）

按以下顺序，每个站点必须有：

1. 一个可复现的样本链接（用户提供或从 Downie 测试串提取）
2. 解析成功、格式列表、下载前 10 秒/完整小文件、合并成功
3. 记录在 `site-coverage.csv` 的 `verified` + `notes`

分组：

| 批次 | 站点 | 重点 |
|---|---|---|
| S1-a | YouTube、TikTok、Instagram、X、Facebook | 登录、PO Token、限流；yt-dlp 失败时做原生/隐藏 WebView |
| S1-b | Twitch、Vimeo、Reddit、Soundcloud、Bandcamp | 直链/HLS；验证 yt-dlp 与 cookie |
| S1-c | Weibo、Youku、WeTV、iQiyi、Youku、CCTV、CBS、NBC、PBS、BBC、ESPN、Fox、MLB | 地区/登录/DRM 边界 |
| S1-d | Udemy、Kakao、Naver、AbemaTV、Radiko、Rumble、Pinterest、Odysee、Kaltura、JWPlayer | 课程/直播/地区/嵌入 |
| S1-e | 抖音/B 站回归 | 番剧选集、B 站音频、抖音直播/音乐 |

**验收**：35 个 P0 每个都有 `verified=yes/no` 和原因；`yes` 的下载闭环通过。

### S2 — P1 分批（每批 20–30 站）

- 先跑 yt-dlp，失败率高的站点进入原生候选。
- 优先做有共同技术模式的站点：Brightcove、Kaltura、JWPlayer、ThePlatform、Anvato、Ooyala 等“平台型”下载器，一次覆盖多站。
- 每批产出：状态表更新 + 至少 1 个回归测试/样本。
- 目标：每个版本把 `generic` 数量往下压，且不把 `ytdlp` 误报成 `verified`。

### S3 — 自定义集成与运营能力

Downie 的关键长尾能力是 **Custom Integrations**（社区 JS 规则） + **Report a Link**：

- 自定义集成：本地 JS/JSON 规则、注册表、导入/导出、控制台、启用/禁用
- Report a Link：内置反馈表单，带站点/链接/错误；我们已有支持邮件，后续做结构化上报
- 站点开关：允许用户禁用某站插件/yt-dlp 提取器
- 失败率看板：按站点/引擎/版本统计

### S4 — 长尾持续维护

- 每次发版更新 `site-coverage.md`，标注新增/修复/失效站点
- 站点更新流水线：样本链接 → 自动解析测试 → 失败告警 → 原生/通用修复

---

## 3. 非站点功能差距（按优先级）

| # | 模块 | Downie 4 | 当前 | 优先级 | 计划 |
|---|---|---|---|---|---|
| 1 | 画质选择 | 多画质时自动/询问/限制 360p–4K；Prefer/Force MP4 | 2.0.19 自动/询问/限制/优先 MP4；2.0.20 强制 MP4 | P0 | 已完成，待逐站回归 |
| 2 | 队列 | 暂停全部/重试全部/重置队列/清空未激活/排序 | 2.0.19 已实现全部命令 + 排序 | P0 | 已完成 |
| 3 | 重复下载 | 检测已下载并询问 | 2.0.19 已实现 URL 去重询问 | P0 | 已完成 |
| 4 | 限速/连接数 | 每任务限速、每任务连接数、分块下载 | 2.0.19 全局限速/连接数；2.0.20 每任务限速/连接数；2.0.21 HTTP 分块 | P1 | 已完成 |
| 5 | 下载提示音 | 成功/失败多种提示音 | 2.0.19 已实现系统提示音开关 | P1 | 多音效待做 |
| 6 | 完成后行为 | 退出程序/打开文件夹/加入 Apple Media | 2.0.19 完成后退出/打开文件夹/通知；2.0.24 Apple Music/TV 导入 | P1 | 已完成（AppleScript 导入） |
| 7 | 菜单栏图标 | 菜单栏 popover 控制队列 | 2.0.19 已实现托盘菜单 | P1 | 已完成 |
| 8 | Quick Look | 空格预览下载文件 | 2.0.19 已实现 qlmanage 预览 | P1 | 已完成 |
| 9 | 下载调试器 | 单任务调试窗口/日志/报告 | 2.0.19 轻量调试信息；2.0.24 yt-dlp 任务日志；2.0.25 原生插件请求/结果/错误日志 | P1 | 已完成 |
| 10 | 搜索/热门下载 | 主窗口搜索 + Top Downloads | 队列搜索面板 | P2 | 搜索已做；Top 需服务端，暂不做 |
| 11 | 导入 | CSV/XML、阅读列表、文件导入 | 2.0.19 文本导入；2.0.21 CSV/XML 结构化导入（url/title/path） | P1 | 阅读列表待做 |
| 12 | 任务菜单 | 复制下载链接/浏览器打开/报告链接 | 2.0.19 已实现 | P1 | 已完成 |
| 13 | 后处理 | 无/MP4/仅音频/Permute/自定义脚本；保留原文件 | 无/MP4/MP3/自定义脚本（2.0.20）+ 转换后删原文件 | P1 | Permute 为第三方应用集成，暂不做 |
| 14 | 字幕/音频 | 首选语言列表、单/多字幕、自动生成字幕、SRT 转换、音轨选择 | 2.0.19 单/多语言与自动生成字幕；2.0.20 SRT 转换；2.0.22 首选音轨匹配 | P1 | 已完成（按 yt-dlp 元数据匹配） |
| 15 | 目的地 | 确认每次、JSON 元数据、缩略图 JPEG、原文件名、按站点/播放列表分文件夹 | 目录/模板/分站点/缩略图/元数据 JSON；2.0.20 询问保存位置与 `{original}`；2.0.21 按播放列表分文件夹（DB v8） | P1 | 已完成 |
| 16 | 高级 | 连接数、分块、原生 HLS、强制重编码、保留失败文件、代理 WebView | 2.0.19 连接数/限速/原生 HLS/强制重编码/自检；2.0.21 分块；2.0.26 失败文件清理 | P1 | 已完成（WebView 代理与 Downie 一样不生效） |
| 17 | 浏览器扩展 | 安装向导/多浏览器/关闭标签页 | 导出扩展/书签/token/cookie 导入；2.0.21 安装向导；2.0.27 Firefox 临时载入 | P2 | Safari/关闭标签页待做 |
| 18 | 授权 | 14 天试用、邮箱、4 设备、签名令牌、心跳、Keychain | 14 天试用、设备/反激活；明文 Hive/HTTP | P1 | v2 见 rea 文档第 5 节 |
| 19 | 自定义集成 | 注册表/提交/控制台/JS 执行 | 无 | P2 | S3 |
| 20 | 多窗口 | 历史/调试/UGE/Quick Look 独立窗 | 单窗口浮层 | P2 | 用户已接受浮层，暂不做真多窗 |
| 21 | 菜单/快捷键 | File/Edit/Browser/Window/Help + 快捷键 | 2.0.20 原生菜单栏（文件/窗口/帮助）+ 托盘菜单；2.0.21 浏览器菜单 | P1 | 编辑菜单、完整快捷键待做 |
| 22 | 自动化/AppleScript | URL scheme、Services、Intents、自动化模式 | 2.0.22 `downie6://`、open -a/命令行、自动化模式 | P2 | AppleScript/Services/Intents 待做 |
| 23 | iCloud 历史 | 同步历史 | 无 | P3 | 不做（跨端复杂度高） |

真正还未完成、且会影响使用体验的只剩：授权 v2（安全加固，不是下载功能）、自定义集成（JS 沙箱）、Top Downloads（需要服务端）、编辑菜单/完整快捷键、多浏览器扩展、AppleScript Services/Intents。多窗口、iCloud、Permute、签名/公证已明确不做。下载、队列、画质、后处理、字幕/音轨、目的地、调试、自动化主链路均已落地。

---

## 4. 本批（2.0.18）交付清单

### 已在本批实现

1. **站点覆盖矩阵**
   - `docs/data/downie-site-matrix.csv`（786 行，来自 REA）
   - `docs/data/yt-dlp-extractors.txt`（1752 个提取器）
   - `docs/site-coverage.md/.csv`（按状态分组的全量表）
   - `apps/desktop/tools/generate_site_coverage.py`（可重复生成）
2. **设置 → 支持站点**
   - 搜索站点/域名/yt-dlp 提取器
   - 按原生/部分/yt-dlp/未复刻/DRM 筛选
   - 显示总数、优先级、是否已验证
3. **自动资源检测**
   - 无法解析时（开启“不支持的链接自动用用户自定义提取”），WebView 自动抓 m3u8/mpd/mp4
   - 第一个候选后等 4 秒，按 HLS > DASH > 直链自动选择；18 秒无候选退回手动
   - 捕获 `<video>/<source>/og:video/JSON-LD/performance`，并自动尝试播放
   - 自动过滤音频分轨和 `.m4s/.ts` 分片

### 本批不做（下一批）

- P0 35 站逐站验证（需要样本链接/用户反馈；S1）
- YouTube/TikTok/Instagram/X 原生插件（S1-a）
- 限速/连接数/Quick Look/菜单栏图标（P1）

---

## 5. 验证与发布

- CI：`flutter test` + macOS/Windows 构建（现有 GitHub Actions）
- 站点验证：每个 `verified=yes` 必须有样本链接和一次完整下载记录
- 文档：每次发版更新 `site-coverage.md` 统计和变更
- 发布：2.0.18 上传 OSS，更新版本接口；用户可在应用内更新

---

## 6. 非目标

- 不做 DRM 绕过（Widevine/FairPlay/PlayReady）
- 不复制 Downie 源码/资源/文案/授权协议
- 不承诺 786 个全部原生复刻；承诺“每个非 DRM 站点至少一个可验证引擎”并持续提高覆盖率
- 不做 macOS 签名/公证、Windows 代码签名（用户已明确决定）
