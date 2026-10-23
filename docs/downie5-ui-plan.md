# Downie 风格 UI 规划（内部代号 downie5）

## 0. 目标与边界

- **目标**：把 4KDownle 桌面端改成 Downie 风格的布局：侧边栏 + 顶部工具栏 + 列表/详情 + 设置/帮助/支持窗口；macOS 与 Windows 共用一套 Flutter 代码。
- **语言**：中文单语言，不做多语言。
- **边界**：只对齐信息架构、布局和操作路径；**不复制** Downie 的名称、图标、截图文案、图片、nib 或像素级视觉。品牌、图标和文案使用自有资产。
- **分支**：`downie5`（内部代号）。DMG 安装包改动保留。
- **支持邮箱**：`huoyongzhuang@qq.com`。

## 1. 品牌配置

- `lib/shared/branding/app_brand.dart`
  - `name` / `tagline` / `supportEmail` / `logoAsset` / `privacyNote`
  - 默认名称：`4KDownle 6`
  - 后续换品牌只改这个文件；图标换 `assets/logo.png` 或重新生成平台图标。

## 2. 页面与组件

### 主窗口

- `AppShell`：侧边栏 + 顶部工具栏 + 内容区。
- 侧边栏分组：
  - 资料库：新建下载、下载队列、历史记录
  - 工具：网页嗅探
  - 设置
  - 支持：帮助、报告问题
  - 底部：版本号 + 检查更新（红点）
- 顶部工具栏：添加链接、帮助、报告问题。
- 现有页面保留并嵌入：首页解析/画质/下载、下载队列、历史记录、设置、授权、网页嗅探、更新提示。

### 帮助窗口（中文）

- `HelpWindow`：左侧主题列表 + 搜索 + 右侧内容。
- 主题：快速开始、下载选项、选择画质、设置、浏览器扩展、后处理、历史记录、音频语言、需要登录的站点、字幕、用户引导提取、故障排查、隐私政策、下载过多、站点专项提示、高级、许可证代码。
- 首次打开显示品牌首页；点击主题显示自有中文说明；底部有「联系支持」入口。

### 支持/报告窗口

- `SupportDialog`：报告链接、通用报告、打开帮助。
- 发送按钮用 `mailto:` 打开默认邮件客户端，收件人 `huoyongzhuang@qq.com`。
- 支持隐私信息弹窗、显示帮助、取消。

### 设置页

- 保留现有下载/外观/系统/关于/授权。
- 新增「帮助与支持」分组：打开帮助、报告问题。
- 支持邮箱统一从 `AppBrand.supportEmail` 读取。

## 3. 双端设计

- **一套 Flutter 代码**；`Platform.isMacOS` / `isWindows` 只控制布局细节。
- macOS：
  - 244px 侧边栏、浅灰背景、紫色强调色、原生标题栏。
  - 帮助/支持使用大尺寸 Dialog，后续可升级为独立窗口。
- Windows：
  - 224px 侧边栏、原生标题栏；顶部工具栏显示应用名。
  - 同一套帮助/支持/设置页面；后续加菜单栏、快捷键和路径适配。
- 中文单语言；日期、路径、快捷键按平台处理。

## 4. 阶段

1. **Phase 1（本次）**：品牌配置、紫色主题、AppShell 侧边栏/工具栏、中文帮助窗口、支持窗口、设置页帮助入口。
2. **Phase 2**：主窗口下载列表 + 详情面板；首页解析/画质布局对齐。
3. **Phase 3**：偏好设置分类页、授权/设备管理、Windows 菜单/快捷键打磨。
4. **Phase 4**：浏览器扩展/本地服务、自定义集成、站点覆盖扩展。

## 5. 验证

- `flutter analyze` / `flutter test`
- CI `-ci` 标签构建 macOS + Windows（release job 跳过）
- 手动检查：
  - macOS/Windows 侧边栏选中态、工具栏、帮助/支持窗口
  - 中文文案完整，无英文残留
  - 「发送」能拉起邮件客户端，收件人为 `huoyongzhuang@qq.com`
  - 设置页帮助/支持入口可用

## 6. 换品牌改哪里

应用内品牌（名称/邮箱/隐私说明）只改一个文件：

- `apps/desktop/lib/shared/branding/app_brand.dart`

换名称/图标还会涉及发行产物，按需改：

| 位置 | 作用 |
| --- | --- |
| `apps/desktop/assets/logo.png` | 应用内 logo（256px） |
| `apps/desktop/assets/logo6.png` | 图标源图（1024px，`tools/generate_brand_icon.swift` 生成） |
| `apps/desktop/tools/generate_icons.sh` | 从源图生成 macOS appiconset + Windows ICO + 256px logo |
| `apps/desktop/tools/generate_installer_assets.swift` | DMG 背景图、安装说明长图的标题/文案 |
| `apps/desktop/macos/Runner/Info.plist` | macOS `CFBundleName` / `CFBundleDisplayName` |
| `apps/desktop/windows/runner/Runner.rc` | Windows 文件属性 `ProductName` / `FileDescription` |
| `apps/desktop/windows/installer/setup.iss` | 安装向导名称、开始菜单/桌面快捷方式名称 |
| `.github/workflows/build.yml` | DMG 卷名（`hdiutil create -volname`） |

注意：`macos/installer/dmg-layout/.DS_Store` 里记录的是 `4KDownle.app` 的图标位置，
不要改 .app 文件名，否则 DMG 窗口布局会失效；显示名用 `CFBundleDisplayName` 即可。
