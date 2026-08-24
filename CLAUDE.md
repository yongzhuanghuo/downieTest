# CLAUDE.md

本文件为 Claude Code（claude.ai/code）提供**仓库级**指引。各端的细节在各自目录的 CLAUDE.md 里，不要都堆在这。

## 这是什么仓库

4KDownle（水影）— 全能视频下载器的**多端 monorepo**。同一个产品，四个客户端形态 + 两个共享后端服务。

产品矩阵、快速开始、已知问题见 [README.md](README.md)；跨端架构见 [docs/architecture.md](docs/architecture.md)。

## 目录约定

```
apps/        客户端。按平台命名（desktop / mobile / harmony-pc），不按技术栈命名 —— 技术栈可能换
services/    服务端。多端共享，不隶属任何单一客户端
docs/        跨端文档。单端文档放各端目录下
```

新增端 → 加 `apps/<平台名>/`；新增服务 → 加 `services/<服务名>/`。全部 kebab-case。

## 改动前先读哪个 CLAUDE.md

| 你要改的东西 | 读这个 |
|---|---|
| Flutter 桌面端（Dart / macOS / Windows 工程） | [apps/desktop/CLAUDE.md](apps/desktop/CLAUDE.md) |
| uniapp 移动端（Vue3 / 小程序 / H5） | [apps/mobile/CLAUDE.md](apps/mobile/CLAUDE.md) |
| Python 解析下载服务 | [services/media-api/CLAUDE.md](services/media-api/CLAUDE.md) |
| Node 授权服务 | [services/license-api/README.md](services/license-api/README.md)（结构简单，无单独 CLAUDE.md） |
| 鸿蒙 PC 端 | [apps/harmony-pc/README.md](apps/harmony-pc/README.md)（占位，路线未定） |

## 全局约定（所有端通用）

### Git 远程

- `origin` = **Gitee**（服务器从此拉取，国内网络可访问）—— 日常 `git push origin main`
- `github` = **GitHub**（用于 Actions CI）—— 常因国内网络 push 超时，失败属正常

### 路径与构建

- **命令要在对应子目录执行**。`flutter` 命令在 `apps/desktop/` 下，`npm` 在 `apps/mobile/` 或 `services/license-api/` 下，`uvicorn` 在 `services/media-api/` 下。在仓库根跑 `flutter pub get` 会失败。
- **CI 的 artifact 路径不受 `working-directory` 影响**。`.github/workflows/build.yml` 里 `actions/upload-artifact` 的 `path` 相对 `$GITHUB_WORKSPACE` 解析，必须显式写 `apps/desktop/` 前缀；其余 `run` 步骤由 `defaults.run.working-directory` 覆盖。
- **`.gitignore` 里含斜杠的规则锚定仓库根**，改目录结构时这些规则会静默失效（如 `apps/desktop/assets/bin/macos/*`）。不含斜杠的（`build/`、`node_modules/`、`.venv/`）匹配任意层级，不受影响。

### 两条技术路线（不要混淆）

- `apps/desktop` **本地跑引擎**：内嵌 yt-dlp + ffmpeg 二进制，解析下载都在用户机器上，只在授权时联网。
- `apps/mobile` / `apps/harmony-pc` **走服务端**：手机与鸿蒙沙箱起不了子进程，全部交给 `services/media-api`。

同一个功能在两条路线上是**两套独立实现**，改一边不会自动同步到另一边。抖音解析尤其如此（详见 [docs/architecture.md](docs/architecture.md) 的「已知重复」一节）。

### 安全红线

- `services/media-api` 目前**无鉴权**（CORS `*`、`/files` `/tmp` 全公开）。别在没加鉴权的情况下把它暴露到公网。
- 激活码 CSV、`.env`、keystore 都在 `.gitignore` 里，别用 `git add -f` 绕过。
- 文档里不要写明文密码或密钥 —— 仓库同时推 Gitee 和 GitHub，历史清不掉。
