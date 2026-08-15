# Downlo PRO 项目技术文档

> 网页视频下载工具 — 支持 YouTube、B站、抖音等 1000+ 网站  
> 目标平台：macOS / Windows

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
downieTest/
├── lib/                          # Flutter 应用主代码
├── downie-license-api/           # 自建授权后端（Node.js + MySQL）
├── assets/                       # 打包资源
├── macos/                        # macOS 平台配置
├── windows/                      # Windows 平台配置
├── test/                         # 测试代码
├── pubspec.yaml                  # Flutter 依赖配置
└── analysis_options.yaml         # 代码规范配置
```

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

### 2.2 downie-license-api/ — 自建授权后端（Node.js + MySQL）

```
downie-license-api/
├── src/
│   ├── index.js                  # Express 入口 + 启动（监听 3000 端口）
│   ├── config.js                 # 读 .env（端口 + MySQL 连接）
│   ├── db.js                     # mysql2 连接池 + 启动 ping 验证
│   ├── license.js                # 激活码工具（随机码生成/规范化/格式化）
│   └── routes/
│       └── license.js            # 5 个接口：激活/解绑/状态/心跳/验证
│                                  #   - activate: 查码→设备数检查(事务+FOR UPDATE)→绑定
│                                  #   - unbind: 月限2次检查→解绑→记日志
│                                  #   - status: 设备列表 + 剩余名额
│                                  #   - heartbeat: 更新 last_seen
│                                  #   - verify: 离线降级验证
├── sql/
│   └── schema.sql                # MySQL 建表语句（licenses/device_bindings/unbind_log）
├── scripts/
│   ├── init-db.js                # 建表脚本
│   └── generate-licenses.js      # 生成激活码（写库 + 导出 CSV）
├── .env.example                  # 环境变量模板（DB 连接 + PORT）
├── ecosystem.config.cjs          # pm2 启动配置
├── nginx.conf.example            # 后续 HTTPS 反向代理参考
└── package.json                  # 依赖：express / mysql2 / dotenv / cors
```

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
cd /Users/huoyz/project/downieTest

# 2. 安装依赖
flutter pub get

# 3. 运行（开发态，yt-dlp/FFmpeg 走系统 PATH）
flutter run -d macos

# 4. 代码分析
flutter analyze

# 5. 生成激活码 → 后端脚本（服务器上执行，见 DEPLOY.md）
#    node downie-license-api/scripts/generate-licenses.js -c 10 -t perpetual
```

### 5.2 打包发布

```bash
# macOS
flutter build macos --release

# Windows
flutter build windows --release
```

打包前需将 yt-dlp 和 FFmpeg 二进制放入 `assets/bin/macos/` 和 `assets/bin/windows/`，应用首次启动时自动提取到应用支持目录。

### 5.3 后端部署

```bash
# 详见 DEPLOY.md 完整步骤
cd downie-license-api
npm install
cp .env.example .env          # 填 MySQL 连接信息
npm run init-db               # 建表
npm run generate -- -c 10 -t perpetual -o pro.csv   # 生成激活码
pm2 start ecosystem.config.cjs
pm2 save && pm2 startup
```

---

## 六、开发计划与进度

### 阶段 1-3：基础视频下载功能 ✅ 已完成

> Commit: `14848ed`

- **视频解析**：通过 yt-dlp `--dump-json` 解析视频信息（标题、时长、格式列表、缩略图）
- **格式选择**：自动配对音视频流，支持手动选择画质/格式
- **视频下载**：调用 yt-dlp 子进程下载，实时解析进度输出
- **FFmpeg 合并**：独立视频流+音频流合并为 MP4（`-c:v copy -c:a aac`）
- **音频转换**：支持提取音频转 MP3
- **平台支持**：Bilibili、YouTube 均测试通过（含音频）

### 阶段 4：下载管理增强 ✅ 已完成

> Commit: `8d8f612`

- **并发下载队列**：最多 3 个任务同时下载，FIFO 调度
- **失败自动重试**：最多 3 次，指数退避（1s → 2s → 4s）
- **SQLite 持久化**：下载任务全量字段入库，应用重启后恢复
- **断点续传**：利用 yt-dlp `--continue`，`.part` 文件自动续传
- **任务状态管理**：pending / downloading / merging / completed / failed / cancelled
- **历史记录页**：查看已完成下载，打开文件/删除记录/清空历史
- **新增文件**：`app_database.dart`（SQLite FFI）、`downloads_dao.dart`（任务 CRUD）

### 阶段 5：会员授权系统 ✅ 已完成

- **激活码体系**：
  - 20 位格式 `XXXXX-XXXXX-XXXXX-XXXXX`，自定义 Base32 编码
  - HMAC-SHA256 签名验证（前 4 字节），碰撞率 ≈ 1/2³²
  - 易混字符容错映射（0/O→8, 1/I→L）
  - 激活码生成脚本 `tools/generate_licenses.dart`
- **设备绑定**：
  - 设备指纹：macOS `IOPlatformUUID`，Windows 注册表 `MachineGuid`
  - PRO 最多 4 台设备，免费版 1 台
  - 解绑功能：每月限 2 次，解绑后设备降级为免费版
- **Cloudflare Workers 后端**：
  - 纯 Web 标准 JS，零依赖
  - D1 数据库：licenses / device_bindings / unbind_log 三表
  - API：激活 / 解绑 / 状态查询 / 心跳保活 / 离线验证
  - 幂等绑定逻辑（已绑定设备重复激活直接返回成功）
- **多代理探测**：优先用户代理 `127.0.0.1:7897`，同时尝试 PROXY 和 SOCKS 协议，缓存可用代理
- **免费版限制**：
  - 每日 5 次下载配额（Hive KV 计数，按天重置）
  - 最高 1080P 画质
  - PRO 解锁 4K + 无限下载 + 4 设备

### 阶段 6：Bug 修复与优化 🔧 进行中

- **状态管理修复**：
  - 移除 `licenseRefreshProvider` 全局刷新信号，改为 `ref.invalidate` 精准刷新
  - `activatedLicenseProvider` 等 4 个 Provider 改为 `StateProvider` 直接赋值
  - `isProProvider` / `maxAllowedHeightProvider` 改为派生 Provider 自动跟随
  - `LicenseCard` 从 `ref.listen` (initState) 改为 `ref.watch` (build)
- **macOS 平台修复**：
  - 移除 Swift Package Manager 引用，回退到 CocoaPods（修复 sandbox-exec 权限错误）
  - 禁用 App Sandbox（开发阶段，修复 Hive/SQLite 写入权限 EPERM）
  - 存储路径回退机制：系统目录不可写时自动回退到 `~/.downie_test/`
  - `BinaryLocator` 加 try-catch，存储目录异常时回退到系统 PATH 查找
- **UI 修复**：
  - `_buildFormatSelector` 不再在 `build()` 中修改状态（修复 `mouse_tracker` 断言错误）
  - 格式自动选择逻辑移到 `ref.listenManual` 监听解析成功后执行
  - 设置页 `LicenseCard` 从 Card 容器中拆出，修复双重边框样式
  - 下载完成进度显示修复

### 阶段 7：打包发布 ⏳ 待开始

- **macOS 打包**：`flutter build macos --release`，生成 `.app`
- **Windows 打包**：`flutter build windows --release`，生成 `.exe`
- **二进制内嵌**：yt-dlp + FFmpeg 预编译二进制打包到 assets
- **GitHub Actions CI/CD**：自动化构建 + 发布
- **Gitee 仓库**：https://gitee.com/huoyongzhuang/downie_test.git

### 阶段 8：后端迁移到自建服务器（MySQL + Node.js）✅ 已完成

> 原阶段 5 的 Cloudflare Workers + D1 后端已废弃（`*.workers.dev` 国内无法访问）。

- **后端重写**：Cloudflare Workers + D1 → Node.js 20 + Express + MySQL 8.0
- **激活码改为数据库随机码**：服务端生成随机码入库、激活时查库；客户端不再持有 HMAC 密钥/验签逻辑，堵住「无限生成激活码」漏洞
- **并发安全**：激活用事务 + `SELECT ... FOR UPDATE` 防止设备数超绑
- **部署**：pm2 守护 + 阿里云安全组放行 3000 端口，详见 [DEPLOY.md](DEPLOY.md)
- **暂用 IP + HTTP**，后续域名备案后接 Nginx + HTTPS

### 阶段 9：二进制内嵌（yt-dlp / FFmpeg）⏳ 待开始

- 下载 yt-dlp / FFmpeg 预编译二进制，放入 `assets/bin/macos/` 和 `assets/bin/windows/`
- `BinaryInitializer` 已支持首次运行自动提取到应用目录（代码已就绪，缺二进制文件）

### 阶段 10：免费版配额 / 画质限制后端化 ⏳ 待开始

- 每日 5 次 + 1080P 限制从「客户端本地 Hive 判定」改为「服务端校验」
- 新增配额表 + `quota/check` + `quota/report` 接口；客户端下载前检查、成功后上报

### 阶段 11：版本更新（方案 A）⏳ 待开始

- 后端加版本接口（最新版本号 + 下载地址 + 更新说明）
- 客户端启动时检查，有新版本弹窗提示用户下载
