# 4KDownle 桌面端（Flutter · macOS / Windows）技术文档

> 仓库总览见 [根 README](../../README.md)；跨端架构见 [docs/architecture.md](../../docs/architecture.md)；开发进度见 [docs/roadmap.md](../../docs/roadmap.md)。

---

## 一、技术栈总览

### 1. 前端（Flutter 桌面应用）

| 技术 | 版本 | 用途 |
|------|------|------|
| **Flutter** | SDK ^3.13.0 | 跨平台 UI 框架，一套 Dart 代码同时编译为 macOS / Windows 原生应用 |
| **Dart** | 随 Flutter SDK | 主开发语言，强类型、JIT+AOT 编译 |
| **flutter_riverpod** | ^2.5.1 | 状态管理框架，负责应用全局状态（下载列表、许可证状态、设置项）的响应式分发 |
| **go_router** | ^14.2.0 | 声明式路由框架，管理首页/下载/历史/设置四个页面的导航栈和侧边栏切换 |
| **window_manager** | ^0.4.2 | 桌面窗口控制，设置窗口大小（默认 1100×750）、最小尺寸（800×600）、标题栏、居中显示 |
| **hive** | ^2.2.3 | 轻量级本地 KV 存储引擎，用于持久化应用设置和许可证激活信息（二进制文件存储，无需原生依赖） |
| **path_provider** | ^2.1.3 | 获取系统标准目录路径（下载目录、应用支持目录），用于定位 Hive 存储位置和下载输出目录 |
| **sqflite_common_ffi** | ^2.3.3 | SQLite FFI 绑定库，桌面端通过 C 语言 FFI 直接操作 SQLite，无需 Java/Kotlin 中间层 |
| **sqflite** | ^2.3.3+1 | SQLite 访问接口层，提供 SQL 查询、事务、Batch 批量操作等 API |
| **path** | ^1.9.0 | 跨平台路径拼接工具，处理不同操作系统的路径分隔符差异 |
| **uuid** | ^4.4.0 | UUID v4 生成器，为每个下载任务生成唯一标识 ID |
| **http** | ^1.2.0 | HTTP 客户端库，与自建授权后端通信（激活/解绑/心跳/状态查询） |
| **file_picker** | ^8.1.2 | 原生文件/目录选择器，用于用户自定义下载保存目录 |
| **flutter_inappwebview** | ^6.1.5 | 内置浏览器（WebView），用于站点登录弹窗抓取 Cookie |
| **meta** | ^1.15.0 | Dart 核心注解库，提供 `@immutable` 等注解 |

### 2. 外部二进制引擎

| 工具 | 用途 |
|------|------|
| **yt-dlp** | 开源视频下载命令行工具，支持 1000+ 网站。应用通过子进程调用，负责视频解析（`--dump-json`）和下载（`-f formatId`），支持断点续传（`--continue`） |
| **FFmpeg** | 多媒体处理工具，用于合并独立下载的视频流和音频流为 MP4 文件（`-c:v copy -c:a aac`）、MP3 转换、字幕嵌入等后处理 |

### 3. 后端（自建服务器）

| 技术 | 用途 |
|------|------|
| **Node.js 20 LTS** | 服务端运行时，跑授权 API |
| **Express** | Web 框架，处理 HTTP 路由与 CORS |
| **MySQL 8.0** | 关系型数据库，存储激活码、设备绑定、解绑日志 |
| **mysql2** | MySQL 驱动（连接池 + 参数化 SQL） |
| **pm2** | 进程守护，崩溃自启、开机自启 |

### 4. 开发工具

| 工具 | 用途 |
|------|------|
| **flutter_lints** | ^6.0.0，Flutter 官方代码规范检查 |
| **build_runner** | ^2.4.11，Dart 代码生成器 |
| **hive_generator** | ^2.0.1，为 Hive TypeAdapter 生成序列化代码 |

---

## 二、项目结构详解

```
apps/desktop/                     # ← 本工程（Flutter 桌面端）
├── lib/                          # Flutter 应用主代码
├── assets/                       # 打包资源（logo + 内嵌 yt-dlp/ffmpeg 二进制）
├── macos/                        # macOS 平台配置
├── windows/                      # Windows 平台配置（含 Inno Setup 安装包脚本）
├── tools/                        # generate_icons.sh — 生成 logo 与各平台图标
├── test/                         # 测试代码
├── logo.png                      # 图标源图（不进库）
├── pubspec.yaml                  # Flutter 依赖配置
└── analysis_options.yaml         # 代码规范配置
```

> 授权后端已迁出到仓库的 [services/license-api/](../../services/license-api/)（多端共享，不属于桌面端）。
> 完整仓库结构见[根 README](../../README.md)。

### 2.1 lib/ — 应用主代码

按 **分层架构** 组织，分为 `core`（核心层）、`data`（数据层）、`features`（功能层）、`shared`（共享层）四个模块。

```
lib/
├── main.dart                     # 应用入口，初始化窗口管理器、本地存储、二进制引擎
├── app.dart                      # 根 Widget，配置路由、主题模式（跟随系统/浅色/深色）
│
├── core/                         # 核心层 — 引擎、存储、许可证、平台适配
│   ├── engine/
│   │   └── ytdlp_runner.dart     # yt-dlp 引擎封装
│   │                              #   - parse(): 调用 yt-dlp --dump-json 解析视频信息
│   │                              #   - download(): 调用 yt-dlp 下载视频，实时解析进度行
│   │                              #   - _parseFormats(): 从 JSON 提取格式列表，自动配对音视频流
│   │                              #   - _parseProgressLine(): 正则解析 yt-dlp 进度输出
│   │                              #   - _extractOutputPath(): 从输出日志提取最终文件路径
│   │
│   ├── ffmpeg/
│   │   └── ffmpeg_runner.dart    # FFmpeg 引擎封装
│   │                              #   - mergeVideoAudio(): 合并视频流+音频流为 MP4
│   │                              #   - convertToMp3(): 音频转 MP3 格式
│   │                              #   - embedSubtitle(): 嵌入字幕到视频
│   │                              #   - _parseFFmpegProgress(): 解析 FFmpeg 进度
│   │
│   ├── license/
│   │   ├── license.dart          # 许可证核心逻辑
│   │   │                          #   - LicenseType: 枚举（free / perpetual）
│   │   │                          #   - LicensePayload: 许可证负载（类型、设备数、过期时间）
│   │   │                          #   - ActivatedLicense: 已激活许可证（含绑定设备列表）
│   │   │                          #   - DeviceFingerprint: 设备指纹生成
│   │   │                          #     · macOS: IOPlatformUUID
│   │   │                          #     · Windows: 注册表 MachineGuid
│   │   │                          #     · 通用: hostname + home 哈希兜底
│   │   │
│   │   └── license_client.dart   # 后端 HTTP 通信客户端
│   │                              #   - activate(): 激活码激活（绑定设备）
│   │                              #   - unbind(): 解绑设备
│   │                              #   - status(): 查询设备列表和剩余名额
│   │                              #   - heartbeat(): 24小时心跳保活
│   │                              #   - 多代理自动探测：127.0.0.1:7897/7890/1087
│   │                              #     同时尝试 PROXY 和 SOCKS 协议，缓存可用代理
│   │
│   ├── platform/
│   │   ├── binary_initializer.dart # 二进制初始化器
│   │   │                          #   - 首次运行从 assets 提取 yt-dlp/FFmpeg 到应用支持目录
│   │   │                          #   - 赋予 Unix 执行权限（chmod +x）
│   │   │                          #   - 开发态 assets 为空 → 自动回退到系统 PATH
│   │   │
│   │   └── binary_locator.dart    # 二进制路径查找器
│   │                              #   - 查找顺序：应用目录 → which/where → 常见路径 → 默认
│   │                              #   - macOS 手动补 PATH（/opt/homebrew/bin 等）
│   │                              #   - _canExecute(): 通过实际执行验证可用性
│   │
│   └── storage/
│       ├── app_database.dart     # SQLite 数据库封装
│       │                          #   - sqflite_common_ffi 初始化
│       │                          #   - downloads 表：下载任务全量字段
│       │                          #   - 索引：created_at DESC, status
│       │
│       ├── downloads_dao.dart    # 下载任务 DAO（数据访问对象）
│       │                          #   - upsert(): 插入或替换任务
│       │                          #   - updateProgress(): 仅更新运行时字段
│       │                          #   - findAll/findRunning/findFinished/findHistory
│       │                          #   - deleteById/deleteFinished
│       │
│       └── settings_storage.dart  # 应用设置存储（Hive KV）
│                                   #   - AppSettings: 下载目录、并发数、字幕、主题、自启动
│                                   #   - 同时承载许可证存储和每日配额计数
│                                   #   - LicenseStorage: 激活信息读写、每日限额管理
│                                   #   - 今日下载次数：quota_YYYYMMDD 键
│
├── data/                         # 数据层 — 不可变数据模型
│   └── models/
│       ├── download_task.dart    # 下载任务模型
│       │                          #   - 状态枚举: pending/downloading/merging/completed/failed/cancelled
│       │                          #   - 字段: URL、标题、格式、进度、速度、重试次数、时间戳
│       │                          #   - SQLite 序列化: toMap() / fromMap()
│       │                          #   - 便捷属性: isRunning/isFinished/percentValue/statusText
│       │
│       ├── download_progress.dart # 下载进度模型
│       │                          #   - 字段: 已下载字节、总字节、速度、百分比、ETA
│       │                          #   - 阶段枚举: preparing/downloadingVideo/downloadingAudio/
│       │                          #     downloading/merging/postProcessing/completed/failed
│       │                          #   - 可读文本: downloadedText/speedText/etaText/percentText
│       │
│       ├── format_option.dart    # 视频格式选项
│       │                          #   - 字段: formatId("137+140")、label("1080p MP4")、height、ext
│       │                          #   - 画质标签: qualityTag(4K/2K/HD/SD/MP3)
│       │                          #   - VIP 判定: isVipQuality (>=1440p)
│       │                          #   - 文件大小: fileSizeText 可读字符串
│       │
│       └── video_info.dart       # 视频信息模型
│                                  #   - 字段: URL、标题、时长、上传者、缩略图、格式列表
│                                  #   - 推荐格式: recommendedFormat (优先1080p)
│                                  #   - 时长格式化: durationText (MM:SS / H:MM:SS)
│
├── features/                     # 功能层 — 按业务模块组织
│   ├── home/                     # 首页模块
│   │   ├── home_page.dart        #   - URL 输入 + 解析 + 格式选择 + 下载触发
│   │   │                          #   - 顶部会员状态横幅（PRO金色 / 免费版配额进度条）
│   │   │                          #   - 画质锁定：免费版 >1080p 显示锁定标记
│   │   │                          #   - 配额检查：acquireSlot() 判断今日剩余次数
│   │   │
│   │   └── home_provider.dart    #   - ParseNotifier: 视频解析状态管理
│   │                              #   - ParseState: idle/loading/success/error
│   │
│   ├── downloads/                # 下载管理模块
│   │   ├── download_provider.dart #  - DownloadListNotifier: 下载队列核心逻辑
│   │   │                          #    · 并发调度：从设置读取上限（默认3），FIFO 启动
│   │   │                          #    · 失败重试：最多3次，指数退避（1s/2s/4s）
│   │   │                          #    · 断点续传：yt-dlp --continue，.part 文件自动续传
│   │   │                          #    · 取消机制：_cancelled Set + yt-dlp SIGTERM
│   │   │                          #    · SQLite 持久化：所有状态变更实时写库
│   │   │                          #    · 应用重启恢复：downloading/merging → pending
│   │   │                          #    · 配额记录：下载成功后 recordSuccess() + state 更新
│   │   │
│   │   └── downloads_page.dart   #  - 下载队列 UI
│   │                              #    · 任务卡片：状态图标 + 进度条 + 速度 + ETA
│   │                              #    · 操作按钮：取消/重试/移除/打开文件
│   │                              #    · 清空已结束任务
│   │
│   ├── history/                  # 历史记录模块
│   │   └── history_page.dart     #   - 已完成下载列表（仅 status=completed）
│   │                              #   - HistoryNotifier: AsyncNotifier 异步加载
│   │                              #   - 操作：打开文件、删除记录、清空历史
│   │                              #   - 日期格式化：今天/昨天/N天前/年月日
│   │
│   ├── license/                  # 许可证模块
│   │   ├── license_provider.dart #   - LicenseStorage: Hive 持久化 + 每日配额
│   │   │                          #   - LicenseNotifier: 激活/解绑/同步设备列表
│   │   │                          #   - Provider: activatedLicenseProvider, isProProvider,
│   │   │                          #     maxAllowedHeightProvider, todayUsedProvider,
│   │   │                          #     todayRemainingProvider, isQuotaReachedProvider
│   │   │
│   │   └── license_card.dart     #   - LicenseCard: 许可证信息展示 + 设备管理
│   │                              #   - showProUpgradeDialog(): PRO 升级对话框
│   │                              #     · 功能对比表（画质/配额/设备/并发等）
│   │                              #     · 激活码输入 + 激活按钮（加载状态防重复点击）
│   │                              #   - 设备列表：同步/解绑（含确认对话框）
│   │
│   └── settings/                 # 设置模块
│       ├── settings_page.dart    #   - 下载设置：目录选择、并发数滑块、字幕开关
│       │                          #   - 外观：主题模式（系统/浅色/深色）
│       │                          #   - 系统：开机自启动
│       │                          #   - 关于：版本号 + LicenseCard
│       │
│       └── settings_provider.dart #  - SettingsNotifier: 设置读写 + 即时持久化
│                                  #  - themeModeProvider: 主题模式响应式 Provider
│
└── shared/                       # 共享层 — 路由、主题、通用组件
    ├── routes/
    │   └── app_routes.dart       #   - GoRouter 路由配置（ShellRoute + 侧边栏）
    │                              #   - 导航项：首页/下载/历史/设置
    │                              #   - selectedNavIndexProvider: 当前选中索引
    │
    ├── theme/
    │   ├── app_theme.dart        #   - Material 3 主题（亮色/暗色）
    │   │                          #   - 种子色：深蓝 #1565C0
    │   │                          #   - 卡片/按钮/输入框统一样式
    │   │
    │   └── app_colors.dart       #   - 补充颜色常量（下载状态色、VIP金色）
    │
    └── widgets/
        └── app_shell.dart        #   - 应用主框架：侧边导航栏 + 主体内容
                                   #   - 220px 宽侧边栏，Logo + 导航项 + 版本号
```

### 2.2 授权后端（已迁出）

授权后端是**多端共享服务**，不属于桌面端，已迁到 [services/license-api/](../../services/license-api/)。
结构与接口说明见 [services/license-api/README.md](../../services/license-api/README.md)。

桌面端只通过 [lib/core/license/license_client.dart](lib/core/license/license_client.dart) 调它的 HTTP 接口。

### 2.3 平台配置

```
macos/
├── Runner/
│   ├── DebugProfile.entitlements  # Debug 沙盒权限（允许 JIT、网络服务端+客户端）
│   └── Release.entitlements       # Release 沙盒权限（仅网络客户端）
│                                   #   · com.apple.security.network.client = true
│                                   #   · com.apple.security.app-sandbox = true
└── Podfile                        # CocoaPods 依赖配置

windows/
├── runner/                         # Windows 原生窗口代码
│   ├── main.cpp                   #   - WinMain 入口
│   ├── flutter_window.cpp         #   - Flutter 窗口承载
│   └── win32_window.cpp           #   - Win32 窗口管理
└── CMakeLists.txt                 # CMake 构建配置
```

---

## 三、核心架构设计

### 3.1 分层架构

```
┌──────────────────────────────────────────────┐
│              UI 层 (features/*/page.dart)      │
│         ConsumerWidget / ConsumerStatefulWidget │
├──────────────────────────────────────────────┤
│          状态管理层 (features/*/provider.dart)   │
│    Riverpod StateNotifier / AsyncNotifier      │
├──────────────────────────────────────────────┤
│           核心层 (core/)                        │
│   引擎封装 │ 存储DAO │ 许可证 │ 平台适配         │
├──────────────────────────────────────────────┤
│           数据层 (data/models/)                │
│         不可变数据模型 + 序列化                  │
├──────────────────────────────────────────────┤
│           外部依赖                              │
│   yt-dlp │ FFmpeg │ SQLite │ Hive │ HTTP       │
└──────────────────────────────────────────────┘
```

### 3.2 状态管理（Riverpod）

```
Provider 依赖关系:

activatedLicenseProvider (许可证状态)
  ├── isProProvider (是否PRO)
  ├── maxAllowedHeightProvider (最大画质)
  ├── todayUsedProvider (今日已用次数)
  ├── todayRemainingProvider (今日剩余次数)
  └── isQuotaReachedProvider (是否达限额)

downloadListProvider (下载列表)
  └── pendingCountProvider (进行中数量)

settingsProvider (应用设置)
  └── themeModeProvider (主题模式)

parseProvider (视频解析状态)

licenseNotifierProvider (激活/解绑操作)
```

### 3.3 下载流程

```
用户粘贴URL → ParseNotifier.parse()
  → YtDlpRunner.parse() (子进程 yt-dlp --dump-json)
  → 返回 VideoInfo (标题/格式列表/缩略图)

用户选择格式 → 点击下载
  → 配额检查 (acquireSlot)
  → 画质检查 (maxHeight)
  → DownloadListNotifier.startDownload()
  → 写入 SQLite + 触发调度器
  → _executeTask() (并发控制 + 重试循环)
    → YtDlpRunner.download() (子进程 yt-dlp)
      → 实时解析进度行 → onProgress 回调
      → 需要合并时验证 FFmpeg
    → 成功: recordSuccess() + 更新配额 Provider state
    → 失败: 指数退避重试 (1s/2s/4s, 最多3次)
```

### 3.4 许可证验证流程

```
客户端:

用户输入激活码 → LicenseNotifier.activate()
  1. 获取设备指纹: DeviceFingerprint.get()
     → macOS: ioreg IOPlatformUUID
     → Windows: reg query MachineGuid
  2. 请求后端绑定: LicenseClient.activate()
     → 多代理探测 (7897/7890/1087, PROXY+SOCKS)
     → 成功后缓存可用代理
  3. 信任服务端返回的负载 (type/max_devices/expire_at)
  4. 保存到本地 Hive: LicenseStorage.save()
  5. 更新 StateProvider.state 刷新 UI

后端 (Node.js + MySQL):

POST /api/license/activate
  1. 规范化激活码 → 查 licenses 表
  2. 检查码状态（revoked → 拒绝）
  3. 查已绑设备: SELECT FROM device_bindings WHERE status='active'
  4. 幂等检查: 设备已绑定 → 直接返回成功
  5. 设备数检查: bound.length >= max_devices → 返回设备列表
  6. 事务 + SELECT ... FOR UPDATE 串行化，防止并发超绑
  7. 写入绑定 + 更新码状态为 activated
```

### 3.5 数据持久化

```
Hive KV 存储:
  ├── downlo_license box
  │   ├── 'license' → ActivatedLicense (激活码/类型/设备列表)
  │   └── 'quota_YYYYMMDD' → int (每日下载次数)
  │
  └── downlo_settings box
      └── 'settings' → AppSettings (下载目录/并发数/主题/字幕等)

SQLite 数据库 (downlo_pro.db):
  └── downloads 表
      ├── 主键: id (UUID)
      ├── 内容: url, title, format_id, ext
      ├── 状态: status, progress, speed, downloaded_bytes
      ├── 时间: created_at, started_at, completed_at
      └── 索引: created_at DESC, status

MySQL 数据库 (downie_license):
  ├── licenses 表 (激活码：code/type/max_devices/expire_at/status)
  ├── device_bindings 表 (设备绑定，code+device_fp 唯一)
  └── unbind_log 表 (解绑日志，月限2次)
```

---

## 四、安全设计

### 4.1 激活码体系

- **格式**: `XXXXX-XXXXX-XXXXX-XXXXX`（20位，5位一组）
- **生成**: 服务端用 `crypto.randomBytes` 从 32 字符字母表（`ABCDEFGHJKLMNPQRSTUVWXYZ23456789`，去除 0/1/I/O）随机生成，约 100 bit 熵
- **存储**: 激活码直接写入 MySQL `licenses` 表，激活时查库命中才算有效
- **生命周期**: `unused`（未用）→ `activated`（已激活）→ `revoked`（已吊销）
- **过期**: `expire_at`（毫秒时间戳，NULL=永久）；永久版默认 NULL
- **防伪**: 客户端不持有任何密钥/签名逻辑，无法离线伪造激活码

### 4.2 设备绑定

- **指纹**: macOS 用 `IOPlatformUUID`，Windows 用注册表 `MachineGuid`
- **限制**: PRO 最多 4 台设备，免费版 1 台
- **解绑**: 每月限 2 次，解绑后设备降级为免费版
- **心跳**: 每 24 小时向后端发送心跳保活

### 4.3 网络安全

- 激活码由服务端生成、数据库校验，客户端不持有任何密钥/签名逻辑，无法离线伪造
- HTTP 客户端支持多代理自动探测（用户代理 7897 优先）
- 后端 CORS 开放（`Access-Control-Allow-Origin: *`）
- 暂用 IP + HTTP，后续接入域名 + HTTPS（Nginx + Let's Encrypt）后改为加密传输

---

## 五、构建与部署

### 5.1 开发环境

```bash
# 1. 进入项目根目录
cd /Users/huoyz/project/4KDownle/apps/desktop

# 2. 安装依赖
flutter pub get

# 3. 运行（开发态，yt-dlp/FFmpeg 走系统 PATH）
flutter run -d macos

# 4. 代码分析
flutter analyze

# 5. 生成激活码 → 后端脚本（服务器上执行，见 [docs/deploy.md](../../docs/deploy.md)）
#    node services/license-api/scripts/generate-licenses.js -c 10 -t perpetual
```

### 5.2 打包发布

```bash
# macOS
flutter build macos --release

# Windows
flutter build windows --release
```

打包前需将 yt-dlp 和 FFmpeg 二进制放入 `assets/bin/macos/` 和 `assets/bin/windows/`，应用首次启动时自动提取到应用支持目录。

#### macOS 二进制架构说明（universal binary）

- macOS 有两种 CPU 架构：Intel（`x86_64`）和 Apple Silicon（`arm64`，M1/M2/M3 芯片）。
- **Universal（通用）二进制** = 一个文件同时包含 `x86_64` + `arm64` 两套机器码，运行时 macOS 自动选对应架构，无需用户装 Rosetta。
- yt-dlp 官方 `yt-dlp_macos` 本身就是 universal；ffmpeg 需要自己合成。

**合成 universal ffmpeg（用 `lipo`）**：

```bash
# 分别下载 x86_64 和 arm64 两个版本（同一版本号），解压得到两个单架构二进制
lipo -create ffmpeg-x86_64 ffmpeg-arm64 -output ffmpeg

# 验证：应显示 "universal binary with 2 architectures: [x86_64] [arm64]"
file ffmpeg
lipo -info ffmpeg   # 输出 Architectures ... x86_64 arm64
```

> 判断标准：`file` / `lipo -info` 显示 `x86_64 arm64` 两个架构就是 universal；只显示一个架构则不支持另一种 CPU。

### 5.3 后端部署

```bash
# 详见 [docs/deploy.md](../../docs/deploy.md) 完整步骤
cd services/license-api
npm install
cp .env.example .env          # 填 MySQL 连接信息
npm run init-db               # 建表
pm2 start ecosystem.config.cjs
pm2 save && pm2 startup
```

**pm2 常用命令**（后端日常维护，都在 `services/license-api/` 目录下执行）：

```bash
pm2 status                            # 看所有进程状态
pm2 start ecosystem.config.cjs        # 启动
pm2 restart downie-license-api        # 重启（改了代码或改了 .env 后必须执行）
pm2 logs downie-license-api           # 实时跟踪日志（Ctrl+C 退出）
pm2 logs downie-license-api --lines 50  # 看最近 50 行日志（不实时）
pm2 stop downie-license-api           # 停止
pm2 delete downie-license-api         # 删除进程（重新 start 前用）
```

**`.env` 里除了 MySQL 连接，还要配管理后台登录信息**：

```ini
ADMIN_USERNAME=admin              # 管理后台登录用户名（默认 admin）
ADMIN_PASSWORD=你的强密码          # 管理后台登录密码
JWT_SECRET=一段长随机字符串        # JWT 签名密钥（管理后台 token 用）
```

**激活码管理后台**（Web 页面，和 API 同一个进程，`pm2 restart` 即可生效）：

- 访问地址：`http://服务器IP:3000/admin/`，用上面的 ADMIN_USERNAME / ADMIN_PASSWORD 登录
- 功能：
  - 统计卡片：总数 / 未激活 / 已激活 / 已吊销 / 免费版 / 永久版
  - 生成卡密：选类型（永久/免费）、数量、设备数、过期天数，一键复制 + 下载 CSV
  - 卡密列表：搜索 / 按状态·类型筛选 / 分页
  - 卡密详情：查看绑定的设备列表
  - 吊销 / 恢复卡密（软删除，可恢复，不物理删除）
  - 导出 CSV（按当前筛选条件）
- 生成卡密不再需要跑命令行 `npm run generate`，页面里点几下就行（命令行脚本仍保留可用）
- ⚠️ 当前是 HTTP 明文，管理密码明文传输，正式使用前建议套 nginx + HTTPS（见阶段 16）

### 5.4 查看日志

日志用 `debugPrint` 输出到标准输出，带 `[...]` 前缀便于搜索：

| 前缀 | 来源 |
|------|------|
| `[解析]` | 视频解析（含原始技术报错） |
| `[YtDlp]` | yt-dlp 下载引擎 |
| `[DownloadList]` | 下载队列 / 任务 |
| `[Engine]` | 启动时的引擎初始化 |
| `[BinaryLocator]` / `[BinaryInit]` | yt-dlp / FFmpeg 二进制定位 |
| `[Settings]` | 设置存储 |

**开发态**：跑 `flutter run -d macos` 时，日志直接打印在**启动它的那个终端窗口**里（VS Code 则在 Debug Console / OUTPUT 面板）。

**打包态（release .app）**：`debugPrint` 仍会输出到 stdout，但双击启动的 GUI 应用没有终端，日志会丢失。要在打包版排查问题，两种方式：

1. 从终端启动（能看到 stdout）：
   `./build/macos/Build/Products/Release/4KDownle.app/Contents/MacOS/4KDownle`
2. 后续加「写日志文件」功能，把日志同时落到本地文件（暂未实现，需要时再加）

> 界面上的报错已做友好化，只显示用户能看懂的提示；原始技术报错只在终端日志里能看到。

---
