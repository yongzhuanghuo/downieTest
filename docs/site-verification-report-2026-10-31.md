# P0 站点实测报告（2026-10-31）

- 样本：`docs/data/site-samples.csv`（35 个 P0 站点，34 个有 URL；Wavve 暂无公开样本）
- 引擎：yt-dlp 2026.10.26（App 构建时同样下载 latest）
- 结果：`docs/site-verification.csv`
- 方式：`--simulate` 只解析不下载；未带 cookie / 代理
- 注意：脚本只验证 **yt-dlp 路径**，原生插件站点（抖音、微博、B 站、TikTok）必须在 App 内做真实下载回归

## 结果

**34 个样本：13 通过，21 失败。**

通过：

> Bilibili、TikTok、CCTV、Facebook、Instagram、MLB、Pinterest、Soundcloud、Twitch、Vimeo、Youku、YouTube、JWPlayer

失败分类：

| 分类 | 站点 | 说明 |
|---|---|---|
| 原生插件路径（yt-dlp 结果不代表 App） | Douyin、Weibo | 抖音走 WebView + a_bogus；微博需要登录 cookie，yt-dlp 不支持该页面 |
| 需要登录 / 风控 | Reddit | yt-dlp 要求账号认证；App 可用 WebView 登录后复用 cookie |
| 样本失效 | BBC、ESPN、Kakao、MTV、Disney | 404 / 测试页过期，需要换当前公开链接 |
| 样本本身有问题 | Twitter | 测试链接跳转到失效的 snpy.tv，需要一条公开视频推文 |
| yt-dlp 解析失败（地区 / 反爬 / 站点改版） | AbemaTV、CBS、Fox、Kaltura、Naver、NBC、Radiko、Rumble、Udemy、WeTV | 部分是地区/登录限制（AbemaTV、CBS、Fox、NBC、Radiko、WeTV、Udemy），部分是站点改版或反爬（Kaltura、Naver、Rumble） |
| 超时 | Odysee、PBS | 20 秒内未完成，可能是网络/地区或站点慢 |

## 解读

1. **多数失败不是“App 不支持”**：样本失效、登录、地区限制占很大比例；Downie 在这些站同样需要账号或地区。
2. **抖音 / 微博不能看 yt-dlp 结果**：抖音原生插件已实现；微博原生插件需要登录 cookie。需要 App 内真实回归。
3. **YouTube / Instagram / TikTok / Facebook / Vimeo 已用公开样本验证通过**，说明最新 yt-dlp 路径有效。
4. **真正的长尾缺口**是 AbemaTV、CBS、Fox、Kaltura、Naver、NBC、Radiko、Rumble、Udemy、WeTV 这类站点；是否补原生插件取决于实际使用频率，不值得为 786 个变体全部手写。

## YouTube 追加验证（SABR）

用户反馈的 `https://youtu.be/4RswhZEY9rg` 在正式版 yt-dlp 下报 `Sign in to confirm you're not a bot`；换 client、加 PO Token 后 web client 也只返回 SABR 格式，正式版无法下载。改用 yt-dlp 的 SABR 分支（`coletdjnz/yt-dlp-dev`，PR #13515，固定 commit）后：

- 选中 `616+251`，1080p（m3u8_native + https）
- 实际下载并合并成功
- 不依赖登录 Cookie 或 bgutil/GPL 插件

CI 已接入该分支的固定 commit 构建（macOS 按架构、Windows 单独构建），官方 universal yt-dlp 保留为兜底。注意这是未合并的第三方 fork，需要随上游更新维护；PyInstaller 打包的 yt-dlp 按上游声明是 GPLv3+。

## 下一步

1. 刷新 5 个失效样本（BBC、ESPN、Kakao、MTV、Disney）和 Twitter 样本，再跑一次，避免把“样本问题”误判为“不支持”。
2. 在 App 内用真实账号回归：抖音、微博、B 站、TikTok、Instagram、Facebook、Reddit。
3. 只对用户实际会用的失败站点补原生插件或 UGE 规则，优先顺序按真实链接反馈，不按 786 行清单平铺。
4. 每次发版重新跑本报告并更新 `docs/site-verification.csv` 与站点覆盖矩阵。
