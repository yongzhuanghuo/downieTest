# apps/mobile — 移动端（uniapp / Vue3 / uview-plus）

一套代码编译**安卓 APK / 微信小程序 / H5** 三端。只做 UI 和调后端接口，不做本地视频处理。

- UI 组件库：uview-plus（CLI 工程 + easycom 自动注册）
- 主题：深色暗黑 `#121212` + 亮绿主色 `#b8ff26`

## 运行方式（npm / CLI）

```bash
cd apps/mobile
npm install

# H5（浏览器预览）
npm run dev:h5

# 微信小程序（需微信开发者工具打开 dist/dev/mp-weixin）
npm run dev:mp-weixin

# App（安卓，需 HBuilderX 云打包或离线打包）
npm run dev:app

# 构建产物
npm run build:h5
npm run build:mp-weixin
```

## 配置后端地址

修改 [src/api/index.js](src/api/index.js) 里的 `BASE_URL`：
- H5 / 浏览器：`http://127.0.0.1:8000`
- 真机 / 小程序：改成电脑局域网 IP，如 `http://192.168.1.100:8000`

> 小程序端需在小程序后台配置 request/uploadFile 合法域名，并在 [src/manifest.json](src/manifest.json) 填 `mp-weixin.appid`。

## 目录结构

```
apps/mobile/
├── index.html          # H5 入口
├── vite.config.js      # vite + uniapp 插件
├── package.json
└── src/                # 源码目录（uniapp CLI 约定）
    ├── main.js         # 入口，注册 uview-plus
    ├── App.vue         # 全局暗黑样式 + uview-plus 基础样式
    ├── manifest.json   # 三端配置
    ├── pages.json      # 页面 + tabBar + easycom
    ├── uni.scss        # 主题变量（暗黑 + 亮绿 + uview-plus 覆盖）
    ├── api/index.js    # 后端接口封装
    └── pages/
        ├── launch/     # 引导启动页（首次启动）
        ├── index/      # 首页（Banner + 链接下载 + 工具卡片）
        ├── parse/      # 解析结果（选清晰度）
        ├── download/   # 下载进度（下载/去水印共用）
        ├── downloads/  # 下载 tab（记录/历史列表）
        ├── delogo/     # 去水印（时间轴定位 + 多框）
        └── mine/       # 我的
```

## 页面说明

| 页面 | 路径 | 说明 |
|------|------|------|
| 引导启动页 | `pages/launch` | 仅首次启动显示，之后直进首页 |
| 首页 | `pages/index` | 导航栏 + 紫蓝 Banner + 链接下载 + 2×2 工具卡片 |
| 下载 tab | `pages/downloads` | 下载记录/历史，可存相册/复制链接 |
| 去水印 | `pages/delogo` | 时间轴定位 + 多框框选 + 多时间点 |
| 我的 | `pages/mine` | 合规声明 + 占位入口 |

## 平台差异

| 能力 | App | 小程序 | H5 |
|------|-----|--------|-----|
| 保存相册 | `saveVideoToPhotosAlbum` | `downloadFile`+`saveVideoToPhotosAlbum` | 无，`window.open` 下载 |
| 上传视频 | 正常 | 受大小限制 | 正常 |
