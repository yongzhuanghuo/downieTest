# CLAUDE.md — apps/mobile（uniapp 移动端）

仓库级约定见[根 CLAUDE.md](../../CLAUDE.md)。本文件只讲移动端。

## 项目概述

4KDownle 移动版 — uniapp（Vue3）一套代码编译 **安卓 APK / 微信小程序 / H5** 三端。

**只做 UI 和调接口，不做任何本地视频处理**。手机跑不了 ffmpeg / yt-dlp，解析、下载、去水印全部由 [services/media-api](../../services/media-api/) 完成。前端拿到的都是后端处理好的 URL。

- **当前状态**：V1 功能已实现（10 个页面），未发布。
- 产品设计稿：[docs/mobile-app-design.md](../../docs/mobile-app-design.md)
- 页面清单与平台差异：[README.md](README.md)

> ⚠️ 本目录原先位于 `uniApp/frontend/`。那时的说明文档写着「仅设计文档阶段，尚未写业务代码」，**那是过期信息** —— 实际业务代码早已写完（10 个页面约 3250 行）。

## 常用命令

**全部在本目录（`apps/mobile/`）下执行**：

```bash
npm install
npm run dev:h5            # H5 浏览器预览
npm run dev:mp-weixin     # 微信小程序（用开发者工具打开 dist/dev/mp-weixin）
npm run dev:app           # 安卓（需 HBuilderX 云打包/离线打包）
npm run build:h5
```

跑之前必须先起 `services/media-api`（默认 `http://127.0.0.1:8000`），否则所有功能不可用。

## 架构

```
src/
├── main.js         入口，注册 uview-plus
├── App.vue         全局暗黑样式
├── pages.json      路由 + tabBar + easycom 自动注册
├── manifest.json   三端配置（app-plus / mp-weixin / h5）
├── uni.scss        主题变量
├── api/index.js    后端接口封装（12 个方法）
└── pages/          10 个页面
```

TabBar 三项：首页 / 下载 / 我的。主题为暗黑 `#121212` + 亮绿主色 `#b8ff26`。

## 非显而易见的注意点

- **后端地址不走环境变量**。`src/api/index.js` 顶部用条件编译 + 运行时探测：H5 端取 `location.hostname` 拼 `:8000`，其余情况**硬编码兜底 `http://127.0.0.1:8000`**。真机 / 小程序调试要连局域网后端时，得手动改这个兜底值 —— 没有 `.env` 机制。
- **uniapp 依赖是 alpha 夜间版**：`package.json` 里 `@dcloudio/*` 全部锁在 `3.0.0-5020420260813003`（日期戳 2026-08-13），不是 stable。升级前先确认 uview-plus 兼容性。
- **`pages/launch/launch.vue` 未注册进 `pages.json`**。引导启动页文件存在（144 行），但路由表里没有它，实际不会作为首屏生效。要启用得手动加进 `pages.json` 的 `pages` 数组第一项。
- **小程序上线前要填两处 appid**：`manifest.json` 顶层 `appid` 和 `mp-weixin.appid` 目前都是空字符串；还需在小程序后台配置 request / uploadFile 合法域名。
- **easycom 已配好**：uview-plus 组件（`u--`/`up-`/`u-` 前缀）自动注册，不需要手动 import。
- **平台能力差异见 [README.md](README.md) 末尾表格** —— 保存相册在 App / 小程序 / H5 上是三种不同实现，改这块要三端都测。

## 与桌面端的关系

同一个产品，但**代码零共享**（Dart vs Vue3）。功能对齐靠人工同步，改一边不会影响另一边。跨端架构见 [docs/architecture.md](../../docs/architecture.md)。
