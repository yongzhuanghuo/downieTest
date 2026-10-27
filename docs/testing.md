# 验证与自测

本仓库没有把 Flutter SDK 提交进仓库；本机也不一定装 Flutter。所以验证分 5 层，越往下越接近真实用户环境。

## L0：静态/编译

```bash
cd apps/desktop
flutter analyze
flutter build macos --release
flutter build windows --release   # Windows 上执行
```

CI（`.github/workflows/build.yml`）在打 tag 时双端真实构建，这是目前最强的编译验证。页面/插件 API 改动必须过这一关。

## L1：单元测试（确定性，CI 每次跑）

```bash
cd apps/desktop
flutter test test/...
```

当前覆盖：

- `format_selector_test.dart`：画质自动/限制/优先 MP4/仅音频
- `douyin_parser_test.dart`：aweme_detail、目标 ID 校验、媒体分轨兜底
- `site_coverage_test.dart`：786 站点状态 JSON、搜索
- `douyin_downloader_test.dart`：MockClient 直链下载、206、失败状态
- `site_plugin_test.dart`：抖音/B 站 URL 匹配（含 live/music/嵌入播放器）
- `bilibili_wbi_test.dart`、`generic_html_extractor_test.dart`、`playlist_test.dart` 等原有回归

## L2：确定性集成测试

对依赖外部二进制的逻辑，优先注入/本地服务，不在测试里访问真实站点：

- HTTP 下载：`MockClient` 验证状态码、进度、完整写入
- 站点解析：固定 JSON 样本（抖音、B 站 WBI、通用 HTML）
- 文件命名、URL 提取、Cookie Netscape 格式：纯函数测试

后续要补：本地 HTTP 服务 + 生成的 1 秒 MP4，验证 ffmpeg 合并/转 MP3。

## L3：WebView 行为验证

登录窗口、UGE、自动资源检测依赖 WKWebView/WebView2，单元测试覆盖不到。做法：

1. 写一个最小 WKWebView 探针（Swift/AppKit），注入与 App 相同的 `AT_DOCUMENT_START` 脚本；
2. 用真实 cookie 加载视频页；
3. 输出 hook 状态、`aweme/detail` 长度、性能资源、`/media-video-*` 数量；
4. 对照 App 日志确认同一行为。

抖音 2.0.17 就是这样定位到“`aweme/detail` 在 WKWebView 里约 31 秒才发出，旧版只等 7–12 秒”的。临时探针不进仓库，结论写进 `apps/desktop/CLAUDE.md`。

桌面端页面本身还要手动验证：登录页按钮可点、UGE 可点、自动检测能选中媒体。

## L4：站点样本验证（真实链接）

```bash
python3 apps/desktop/tools/verify_site_samples.py \
  --samples docs/data/site-samples.csv \
  --out docs/site-verification.csv \
  --proxy http://127.0.0.1:7897   # 海外站点可选
```

样本 CSV 格式：

```csv
site,url,note
YouTube,https://www.youtube.com/watch?v=...,公开视频
Bilibili,https://www.bilibili.com/video/BV...,普通视频
```

规则：

- `--simulate` 只解析不下载，避免样本链接产生大量流量；
- 失败的样本要区分“样本失效/地区限制/需要登录/引擎不支持”，不要直接把站点标成不支持；
- 通过后把 `docs/site-coverage.csv` 的 `verified` 改成 `yes`，并在 `notes` 写明验证日期和样本类型；
- 海外站点走代理测出来的结果要注明“测试环境使用代理”。

## L5：安装包端到端（发布前）

1. 安装 DMG / EXE（不做签名，按安装说明右键打开/仍要运行）；
2. 用真实链接走完整链路：`+` → 登录（如需要）→ 解析 → 选画质 → 下载 → 合并 → 打开文件；
3. 检查日志：

```text
~/Library/Application Support/com.example.downieTest/logs/app_YYYYMMDD.log
```

Windows：`%APPDATA%\com.example.downieTest\logs\`（实际路径以应用数据目录为准）。

yt-dlp 任务另有 `logs/task_<任务ID>.log`（命令行、退出码、stdout/stderr），
可从下载行右键「调试信息 → 任务日志」直接打开。

4. 至少覆盖一条：直链 MP4、HLS/DASH（B 站）、需要登录的站点（抖音/B 站）、一个不支持的链接走自动资源检测。
5. 自动化：`downie6://XUOpenURL?url=...` 与 `open -a Downie6 <链接>` 各验证一次；Windows 安装版验证协议注册与单实例转发。

## 发布判定

- CI 双端构建成功
- 新增单元测试通过
- 站点表更新（新增/修复/失效）
- 至少一条真实下载闭环手工验证
- 版本号、CHANGELOG、OSS、版本接口一致
