# 开发计划与进度

> 桌面端（Flutter）的阶段性开发记录。移动端计划见 [mobile-app-design.md](mobile-app-design.md) 第七章。

---


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
- **部署**：pm2 守护 + 阿里云安全组放行 3000 端口，详见 [deploy.md](deploy.md)
- **暂用 IP + HTTP**，后续域名备案后接 Nginx + HTTPS

### 阶段 9：二进制内嵌（yt-dlp / FFmpeg）✅ 已完成

- yt-dlp / FFmpeg 二进制已放入 `assets/bin/macos/` 和 `assets/bin/windows/`（yt-dlp + ffmpeg 均合成了 universal，支持 Intel / Apple Silicon）
- `BinaryInitializer` 支持首次运行自动提取到应用目录
- 附 `scripts/download-binaries.sh` 脚本用于以后更新二进制

### 阶段 10：免费版配额后端化 ⏳ 后期再开发

- 原「每日 5 次」方案已被阶段 15 的「14 天试用」取代
- 1080P 画质限制仍为客户端本地判定，服务端强制留待后期

### 阶段 11：版本更新（方案 A）→ 已并入阶段 16

### 阶段 12：MP3 音频下载 🔧 进行中

- 修复现有「MP3 纯音频」bug（当前下的是 m4a 改后缀，非真 MP3）
- yt-dlp 加 `-x --audio-format mp3` 一步转码出真 MP3

### 阶段 13：字幕功能（下载时勾选下载字幕）✅ 已完成

- 下载视频时勾选「同时下载字幕」，yt-dlp `--write-subs --write-auto-subs` 下载全部可用字幕
- 下载时勾选「同时下载封面」，yt-dlp `--write-thumbnail --convert-thumbnails jpg` 下载封面图（只下载最高清一张，转成 jpg）
- 上传视频 / 音频提取字幕 → 已取消（归入阶段 18 后期）

### 阶段 14：去水印工具 ❌ 已移除

- 曾实现时间轴 + 多段框选 + FFmpeg `delogo`，但效果不理想，整功能已移除
- 若以后重做，考虑换更强的去水印算法（如目标检测定位水印），而非纯 delogo

### 阶段 15：14 天试用 ⏳ 后期再开发（暂缓）

- 原「14 天试用」暂缓，当前免费额度为「每日 2 个视频」（客户端本地配额）
- 服务端试用记录留待后期

### 阶段 16：版本推送（方案 A）⏳ 暂缓（已设计，未实现）

> 设计已确定，暂缓开发。实现时按下面方案。

**目标**：用户打开旧版软件 → 软件自动查服务器有无新版 → 有就弹窗提示更新。

**整体链路**：
1. 打包（.dmg / .exe）
2. 安装包上传到可下载地址（建议阿里云 OSS；包内嵌 ffmpeg 后超 100MB，Gitee Releases 放不下）
3. 后端记录「最新版本号 + 下载地址」
4. 客户端启动检查 → 弹窗 → 引导下载

**后端**：
- 新增 `GET /api/version/latest?platform=macos|windows`，返回 `{ ok, version, build, url, changelog, force }`
- 版本信息先写死在 `.env`（`LATEST_VERSION` / `DOWNLOAD_URL_MACOS` / `DOWNLOAD_URL_WINDOWS` / `CHANGELOG`），发版时改完重启即可；以后需要再上数据库表 `app_versions`

**客户端**：
- 依赖：`package_info_plus`（读版本号）、`url_launcher`（打开下载链接）
- 启动时异步检查（不阻塞、失败静默），比较 `build` 号（或语义化版本）
- 有新版 → 弹窗显示版本号 + changelog +「立即更新」按钮 → 打开浏览器下载 → 用户手动安装

### 阶段 17：UI 重新设计 ⏳ 待开始

- 侧边栏 4 项：首页 / 下载 / 历史 / 设置
- 字幕提取归入阶段 18（ASR）
- 顶部「试用剩余 X 天」倒计时横幅

### 阶段 18：字幕语音生成（ASR）⏳ 后期再开发

- 上传音频 / 无字幕视频 → 语音转文字生成字幕
- 需选 ASR 方案（本地 Whisper / 第三方 API），暂缓

### 阶段 19：站点登录（解决需要 Cookie 的站点）✅ 已完成

- 下载失败且报错为「需要登录 / cookie」时，自动弹「需要登录 XX 站」提示 → 打开该站内置浏览器登录 → 抓取 cookie 按站存成 `cookies/<站点>.txt`
- 下载时把所有已登录站点的 cookie 文件 `--cookies` 传给 yt-dlp，按域名自动匹配
- 内置支持的站点（登录页 / 域名已配置）：

| 站点 | 域名 |
|------|------|
| YouTube | youtube.com / youtu.be |
| 抖音 | douyin.com |
| 哔哩哔哩 | bilibili.com |
| 小红书 | xiaohongshu.com |
| 快手 | kuaishou.com |
| 微博 | weibo.com |
| Twitter / X | x.com / twitter.com |
| Vimeo | vimeo.com |
| Twitch | twitch.tv |
| Instagram | instagram.com |
| TikTok | tiktok.com |

- 未列入的站点按域名自动推导登录页，同样支持登录
- 依赖 `flutter_inappwebview`（macOS 用 WKWebView、Windows 用 WebView2，Windows 需装 WebView2 runtime）
- 注意：抖音例外——抖音解析不走 yt-dlp + cookie，改走 WebView 拦截 `aweme/detail`（见阶段 21），登录抓 cookie 对抖音无用

### 阶段 20：yt-dlp 自动更新 ✅ 已完成 + OSS 镜像源 ⏳ 后期

**已完成：运行时自动更新（无需重新打包 App）**

- 启动时后台跑 `yt-dlp -U`（fire-and-forget，不阻塞 UI，60s 超时，失败静默降级继续用旧版）
- 设置页「关于」区新增「yt-dlp 版本 + 检查更新」按钮，手动触发
- 原理：`yt-dlp -U` 内部自带版本对比，发现新版才下载替换自己；已最新时不会重复下载
- 生效前提：**只有打包版内嵌的 standalone 二进制支持 `-U` 自更新**；开发态走系统 PATH 的 brew/pip 版会被 yt-dlp 禁用 `-U`（提示用 pip 更新），自动更新自动跳过，不影响下载

**后期：OSS 镜像更新源（暂不实现，需先有 OSS）**

> 现在还没有阿里云 OSS，此功能先不加。等申请好 OSS（阶段 16 版本推送也需要它）再实现。

**原因**：
1. 当前 `-U` 直连 GitHub，国内访问慢且不稳定，自动更新经常超时失败 → 静默降级后用户实际拿不到最新版，更新机制形同虚设
2. 服务器定时拉 GitHub 最新 yt-dlp 存到 OSS，客户端用 `yt-dlp -U --update-to <OSS 地址>` 指向国内下载，速度快且可控
3. 和阶段 16「版本推送」共用一个 OSS，避免重复建设

**实现方式（到时候）**：
- 服务器定时任务：拉取 yt-dlp GitHub 最新 release 的 standalone 二进制 → 上传 OSS 固定路径（如 `yt-dlp/yt-dlp_latest`)
- 客户端：`YtDlpRunner.update()` 改用 `--update-to` 指向 OSS 地址，失败再回退 GitHub 官方源

### 阶段 21：抖音解析（WebView 拦截 aweme/detail API）✅ 已完成

> 2026-08 完成。背景：yt-dlp 抖音提取器未实现 `a_bogus` 签名，被抖音反爬打穿，补任何 cookie 都报 Fresh cookies。

**根因**（curl 实测 + yt-dlp 源码查证）：
1. yt-dlp `tiktok.py` 的 `DouyinIE` 请求 `aweme/v1/web/aweme/detail/` API 时没实现 `a_bogus` 签名（源码只有 `# TODO: Run verification challenge`），抖音拒绝请求返回空 JSON，误报 `Fresh cookies`。补 sessionid/msToken/s_v_web_id 全都没用。
2. 抖音 2026 年分享页（`iesdouyin.com/share/video/{id}`）SSR 只渲染页面框架（itemId/abParams），**播放地址由前端 JS 异步调 `aweme/detail` 拉取**——纯 HTTP 抓分享页拿不到 `play_addr`。
3. 结论：纯 HTTP 两条路（yt-dlp、抓分享页 SSR）都断。唯一可靠方案是**真实浏览器环境拦截 aweme/detail 响应**（浏览器自动生成 a_bogus 签名 + 带 cookie + msToken）。

**实现**：
1. [home_provider.dart](../apps/desktop/lib/features/home/home_provider.dart)：url 含 `douyin.com` → 走 `DouyinWebDialog`（不走 yt-dlp）
2. [douyin_web_dialog.dart](../apps/desktop/lib/features/downloads/douyin_web_dialog.dart)：弹 WebView 对话框，**桌面 Chrome UA** 打开短链，注入 JS hook（`AT_DOCUMENT_START`）拦截 `aweme/detail` 的 fetch/XHR 响应存到 `window.__douyin_data__`，轮询读取后解析 `aweme_detail`（标题/作者/封面/时长/各清晰度 `gear_name`），构造 VideoInfo
3. [download_provider.dart](../apps/desktop/lib/features/downloads/download_provider.dart)：按 `extractor=='Douyin'` 分流到 HTTP 直链下载
4. [douyin_downloader.dart](../apps/desktop/lib/core/engine/douyin_downloader.dart)：HTTP 直链下载（桌面 UA + `Referer: https://www.douyin.com/`），带进度回调

**关键坑（实测踩过）**：
- **必须桌面 UA**：移动 UA 会让分享页停在「打开 App」引导页，不请求 aweme/detail，hook 截获不到
- **下载防盗链**：下载地址是 PC 网页版（`browser_name=Chrome`），CDN 要求桌面 UA + Referer douyin.com；缺 Referer 时部分节点（如 `v26-web.douyinvod.com`）返回 403
- 格式名直接显示 `gear_name` 原样（`normal_1080_0`、`1080_1_1`），不做分辨率转换

**cookie 文件位置与手动删除**（抖音不依赖 cookie，但其他站点登录用）：
- macOS：`~/Library/Application Support/com.example.downieTest/cookies/<站点>.txt`
- Windows：`%APPDATA%\com.downlo\4KDownle\cookies\<站点>.txt`
- App 内暂无删除入口，直接删对应文件即可

### 阶段 22：激活码管理后台（Web 页面）✅ 已完成

> 2026-08 完成。之前生成卡密只能跑命令行 `npm run generate`，麻烦且看不到全局。加了 Web 管理页面。

**技术方案**：
- 后端：`src/routes/admin.js`，JWT 认证（`jsonwebtoken`），账号密码配在 `.env`（`ADMIN_USERNAME` / `ADMIN_PASSWORD` / `JWT_SECRET`）
- 前端：`admin/index.html` 单页（原生 HTML/CSS/JS，无构建）
- 部署：前端页面和 API 都在**同一个 Express 进程**（`app.use('/admin', express.static('admin'))` 托管静态页面），`pm2 restart downie-license-api` 即可，无需额外前端服务

**功能**：
- 登录（JWT 24h 过期）
- 统计卡片：总数 / 未激活 / 已激活 / 已吊销 / 免费版 / 永久版 / 绑定设备总数
- 生成卡密：类型（永久/免费）、数量、设备数、过期天数，一键复制 + 下载 CSV
- 卡密列表：搜索 / 按状态·类型筛选 / 分页，每行显示已绑设备数
- 卡密详情：查看绑定的设备列表（设备名/指纹/绑定时间/最后心跳）
- 吊销 / 恢复卡密（软删除可恢复，**不物理删除**）
- 导出 CSV（按当前筛选条件）

**接口**（`/admin/api/*`，除 login 外都需 `Authorization: Bearer <token>`）：
| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/admin/api/login` | 登录 |
| GET | `/admin/api/stats` | 统计 |
| GET | `/admin/api/licenses` | 列表（分页/搜索/筛选） |
| POST | `/admin/api/licenses/generate` | 生成卡密 |
| GET | `/admin/api/licenses/:code` | 详情 + 绑定设备 |
| POST | `/admin/api/licenses/:code/revoke` | 吊销 |
| POST | `/admin/api/licenses/:code/restore` | 恢复 |
| GET | `/admin/api/licenses/export` | 导出 CSV |

> 数据库**不改表**，复用 `licenses` + `device_bindings`。跟踪只按激活状态（unused/activated/revoked），不加「销售/渠道」字段。
