# apps/harmony-pc — 鸿蒙 PC 端（占位，未开发）

**当前状态**：空目录占位，技术路线未定。本文件记录候选方案和待验证问题，等真正开工时再定。

仓库总览见[根 README](../../README.md)；跨端架构见 [docs/architecture.md](../../docs/architecture.md)。

---

## 先回答一个问题，路线才能定

> **鸿蒙 PC 的应用沙箱，允许应用启动 `yt-dlp` / `ffmpeg` 这类子进程吗？**

这是所有决策的分水岭：

- **不允许**（大概率）→ 只能做瘦客户端，所有解析下载走 [services/media-api](../../services/media-api/)。这跟移动端是同一套模式，也是为什么 media-api 被放在 `services/` 而不是塞在移动端目录里。
- **允许** → 才有可能复用桌面端那套「内嵌二进制 + 本地跑」的方案，但仍需为鸿蒙重新编译 arm64 版本的 yt-dlp 和 ffmpeg，工作量不小。

开工前先写个最小 demo 验证这一条，不要先动 UI。

---

## 三条候选路线

| 路线 | 做法 | 代码复用 | 主要卡点 |
|------|------|---------|---------|
| **A. 瘦客户端 + media-api** | 原生 ArkTS 写 UI，解析下载全走服务端 | UI 需重写；后端 100% 复用 | 服务器带宽成本；用户下载要过一次服务器中转 |
| **B. uniapp 编译鸿蒙** | 复用 [apps/mobile](../../apps/mobile/) 代码，加一个鸿蒙编译目标 | 最高，理论上一套代码 | 需确认当前 uniapp 版本对**鸿蒙 PC**（不是手机）的支持程度；项目用的还是 alpha 夜间版 |
| **C. 原生 ArkTS 独立工程** | DevEco Studio 从零写，能力对齐桌面端 | 最低，UI + 业务全重写 | 工作量最大，且若沙箱限制成立，仍然绕不开走服务端 |

**倾向性判断**：如果沙箱确实起不了子进程（大概率），那 A 和 B 的差别只在 UI 层怎么写，后端策略是一样的。先验证 B 的可行性 —— 能复用 `apps/mobile` 就省一整个前端。B 不通再退到 A。

C 只在「鸿蒙 PC 要求原生体验、且 uniapp 表现不达标」时才值得。

---

## 真正开工时要做的事

1. 验证沙箱子进程能力（见上）
2. 确认 uniapp 对鸿蒙 PC 的支持状态
3. 定路线后，在本目录建 DevEco 工程（路线 A/C）或在 `apps/mobile` 加编译目标（路线 B）
4. 若建独立工程，`.gitignore` 里的鸿蒙规则已经预置好了（`oh_modules/`、`.hvigor/`、`build/default/`、`*.har`）
5. 写 `apps/harmony-pc/CLAUDE.md` 记录本端的坑

## 目录约定

若走独立 DevEco 工程，按鸿蒙标准布局：

```
apps/harmony-pc/
├── entry/                  # 主 HAP 模块
│   └── src/main/ets/       # ArkTS 源码
├── oh-package.json5        # 依赖声明
├── build-profile.json5     # 构建配置
└── hvigorfile.ts
```
