# Downie6 浏览器扩展（Chrome / Edge / Firefox）

把当前标签页一键发送到本机 Downie6 的下载队列。

## 安装

1. 打开 Chrome 的 `chrome://extensions`（Edge 是 `edge://extensions`）。
2. 打开右上角「开发者模式」。
3. 点「加载已解压的扩展程序」，选择本目录 `apps/desktop/browser-extension`。
4. 在 Downie6 的「偏好设置 → 浏览器扩展」里打开「接收本机浏览器发来的页面」。
5. 复制同一面板里的 token，填到扩展弹窗的输入框（只需填一次）。
6. 在视频页面点扩展图标 →「加入下载队列」。

Firefox：打开 `about:debugging#/runtime/this-firefox` →「临时载入附加组件」，
选择本目录的 `manifest.json`。Firefox 正式安装需要签名，本项目未做签名；
长期使用可以继续用书签脚本。

## 说明

- 只连接 `http://127.0.0.1:8765`，不经过外网。
- token 保存在浏览器扩展的 `chrome.storage.local`，重置 token 后需要重新填写。
- 端口需要在 Downie6 里开启；应用未启动或端口被占用时会提示连接失败。
- 也可以不用扩展，在偏好设置里复制「书签脚本」作为浏览器书签使用。
