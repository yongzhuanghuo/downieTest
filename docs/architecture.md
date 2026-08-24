# 跨端架构总览

四个客户端 + 两个服务的关系、两条技术路线的分野、已知的重复与待办。
单端内部架构见各端自己的 README / CLAUDE.md。

---

## 全景图

```
                 ┌──────────────────────────────────────────────┐
                 │              客户端 apps/                     │
                 └──────────────────────────────────────────────┘

   apps/desktop              apps/mobile           apps/harmony-pc
  (Flutter · 桌面)      (uniapp · 安卓/小程序/H5)      (占位 · 未定)
        │                        │                        │
        │                        │                        ╎ 大概率同 mobile
        │                        │                        ╎
   ┌────┴─────┐                  │                        │
   │ 本地跑引擎 │                  └────────────┬───────────┘
   │ yt-dlp   │                               │
   │ ffmpeg   │                               ▼
   └────┬─────┘                  ┌────────────────────────┐
        │                        │  services/media-api     │
        │                        │  FastAPI               │
        │                        │  yt-dlp / ffmpeg /     │
        │                        │  抖音 a_bogus 签名       │
        │                        └────────────────────────┘
        │
        └──────────────┐         ┌────────────────────────┐
                       └────────▶│  services/license-api   │
                                 │  Node + MySQL          │
                                 │  激活码 / 设备绑定       │
                                 └────────────────────────┘
                                   ▲
                                   ╎ 移动端/鸿蒙尚未接入
```

---

## 两条技术路线

这是整个仓库最重要的一条分界线。

|  | 桌面端路线 | 移动端 / 鸿蒙路线 |
|---|---|---|
| 引擎在哪跑 | 用户机器（子进程） | 服务器 |
| 依赖 | 内嵌 yt-dlp + ffmpeg 二进制 | 只需网络 |
| 联网时机 | 仅授权校验 | 每一步操作 |
| 安装包 | 170MB+ | 几 MB |
| 用户下载速度 | 直连站点，最快 | 过服务器中转 |
| 反爬维护成本 | 每个客户端都要更新 | 改服务端即可，用户无感 |
| 服务器成本 | 几乎为零 | 带宽是大头 |

**为什么分两条**：手机和鸿蒙的应用沙箱起不了任意子进程，物理上跑不了 yt-dlp / ffmpeg。桌面端没这个限制，所以选了成本更低、速度更快的本地方案。

**这也是 `services/` 独立于 `apps/` 的原因**：media-api 不是「移动端的后端」，而是所有瘦客户端共享的服务。license-api 同理 —— 它现在只服务桌面端，但移动端接授权时会直接复用。

---

## 服务契约

跨语言（Dart / TypeScript / Python）没法共享代码，一致性靠这份契约维持。改接口时**两边都要改**。

### license-api（`:3000`）

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/api/activate` | 激活（事务 + `FOR UPDATE` 防超绑） |
| POST | `/api/unbind` | 解绑设备 |
| GET | `/api/status` | 设备列表 + 剩余名额 |
| POST | `/api/heartbeat` | 更新 `last_seen` |
| POST | `/api/verify` | 离线降级验证 |
| — | `/admin/*` | 管理后台（JWT），同进程托管静态页 |

**安全模型**：客户端只发 `code + device_fp`，完全信任服务端返回的负载，本地无验签、无密钥。安全边界全在服务端。

### media-api（`:8000`）

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/api/parse` | 解析 → 标题/封面/作者/时长/清晰度列表 |
| POST | `/api/download` | 提交下载 → `task_id` |
| GET | `/api/task/{id}` | 轮询进度 |
| POST | `/api/delogo/preview` | 上传视频 → 可 seek 播放源 |
| POST | `/api/delogo/frame` | 指定时间戳抽帧 |
| POST | `/api/delogo/process` | 提交 `segments[]` 去水印 |
| POST | `/api/upload/image`、`/api/watermark`、`/api/md5`、`/api/gif` | 工具类 |
| GET | `/health` | 健康检查 |

静态：`/files/*` → 下载产物，`/tmp/*` → 临时文件（抽帧图等）。

**⚠️ 当前无鉴权**（CORS `*`、静态目录全公开）。公网部署前必须加。

---

## 已知重复：抖音解析有两套实现

这是目前最值得处理的架构债。

| | apps/desktop | services/media-api |
|---|---|---|
| 方案 | WebView 拦截 `aweme/detail` 响应 | 纯 HTTP + a_bogus 签名 |
| 实现 | `douyin_web_dialog.dart` + `douyin_downloader.dart` | `douyin.py` + `douyin_sign/`（约 3200 行 JS） |
| 依赖 | flutter_inappwebview，需弹窗、需桌面 UA | node 子进程跑签名 |
| 能否无头/批量 | 否，必须弹出可见 WebView | 是 |
| 用户体验 | 每次解析弹一次浏览器窗口 | 无感 |

**共同背景**：yt-dlp 的抖音提取器没实现 `a_bogus` 签名（`tiktok.py` 里只有 TODO），且抖音分享页 SSR 不再内嵌播放地址，所以两边都得自己想办法。

**判断**：media-api 那套方案更优 —— 不需要浏览器、可服务端批量跑、用户无感。桌面端的 WebView 方案是当时没有服务端才做的权宜之计。

**建议（未排期）**：桌面端抖音解析改为调 media-api，删掉 WebView 那条路径。代价是桌面端从「纯本地」变成「抖音这一个站点要联网解析」，需要产品上接受。

---

## 其他跨端待办

- **移动端 / 鸿蒙尚未接入 license-api**。目前 `apps/mobile` 完全没有授权逻辑，所有功能免费。要收费得先接。
- **功能对齐靠人工**。桌面端有的（字幕下载、站点登录抓 cookie、MP3），移动端不一定有；移动端有的（加水印、改 MD5、转 GIF），桌面端没有。没有任何机制保证同步。
- **反爬失效是持续成本**。抖音 a_bogus、B站 WBI、视频号登录态都会随平台更新而失效。走服务端路线的好处是改一次全端生效；桌面端则要发版。

---

## 相关文档

- [根 README](../README.md) — 产品矩阵、快速开始、已知问题
- [根 CLAUDE.md](../CLAUDE.md) — 仓库级约定
- [roadmap.md](roadmap.md) — 桌面端开发进度（阶段 1-22）
- [mobile-app-design.md](mobile-app-design.md) — 移动端产品与技术设计稿
- [deploy.md](deploy.md) — 服务器部署
