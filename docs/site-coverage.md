# Downie 4 站点覆盖矩阵

- 基线：Downie 4 v4.13.3；yt-dlp 2026.07.04（1752 个提取器）
- 总数：786 个 Downie 下载器/站点变体
- 生成：`python3 apps/desktop/tools/generate_site_coverage.py`

## 统计

| 状态 | 数量 | 含义 |
|---|---:|---|
| 原生插件 | 9 | 我们自己的解析/下载实现 |
| 原生插件（部分） | 0 | 原生实现只覆盖部分链接形态 |
| yt-dlp | 298 | 功能可用（由 yt-dlp 负责），但不是 Downie 代码复刻；仍需逐站验证 |
| 通用资源检测（未复刻） | 473 | 没有原生/已知提取器，只能靠通用 HTML/WebView 嗅探；未逐站验证 |
| DRM（不支持） | 6 | Downie 自身也拒绝的 DRM 正片 |

> 重要：`yt-dlp` 不等于“原生复刻”。本表把“能下载”和“代码复刻”分开标注，避免把 yt-dlp 覆盖误报成已完成站点。

## 最近样本验证

来源：`docs/site-verification.csv`（`tools/verify_site_samples.py` 生成）。失败不等于站点不支持，需区分样本失效、地区限制、登录/风控和引擎缺陷。

| 站点 | 覆盖状态 | 结果 | 详情/错误 | 耗时 |
|---|---|---|---|---:|
| YouTube | ytdlp | 失败 | ERROR: [youtube] 3x5d12PP5Mo: Private video | 28.6s |
| Twitter | yt-dlp（待验证） | 失败 | ERROR: [twitter] 1673335410510946309: Suspended | 29.1s |
| Facebook | ytdlp | 失败 | timeout 35s | 35.0s |
| Vimeo | ytdlp | 失败 | timeout 35s | 35.0s |
| Reddit | ytdlp | 失败 | ERROR: [Reddit] 20x091: Account authentication is required. Use --cookies-from-browser or --cookies for the authentication. See  https://github.com/yt-dlp/yt-dlp/wiki/FAQ#how-do-i- | 26.5s |
| Soundcloud | ytdlp | 通过 | soundcloud	Lostin Powers - She so Heavy (SneakPreview) Adrian Ackers Blueprint 1	143.206 | 30.1s |
| TikTok | ytdlp | 失败 | ERROR: [TikTok] 6756589355923410178: Unexpected response from webpage request; please report this issue on  https://github.com/yt-dlp/yt-dlp/issues?q= , filling out the appropriate | 24.3s |
| Twitch | ytdlp | 失败 | ERROR: [twitch:vod] 124137118: Video 124137118 does not exist | 24.9s |
| Weibo | ytdlp | 失败 | ERROR: Unsupported URL: https://h5.video.weibo.com/show/1034:4574447982805003 | 23.8s |
| Youku | ytdlp | 通过 | youku	地铁借肩膀乘客错过12站 睡神终寻"真爱"	236.67 | 33.6s |
| WeTV | ytdlp | 失败 | timeout 35s | 35.0s |
| Pinterest | ytdlp | 通过 | Pinterest	Pinterest video #28147566414114925	7.3 | 26.2s |
| Rumble | ytdlp | 失败 | ERROR: [RumbleEmbed] vbq2h: Unable to download JSON metadata: HTTP Error 403: Forbidden (caused by <HTTPError 403: Forbidden>) | 28.1s |
| CCTV | ytdlp | 通过 | CCTV	《遇见大咖》 20160304	1610.0 | 31.3s |
| CBS | ytdlp | 失败 | ERROR: [CBS] GfttMtUBBfAeORI6kkvqq1RBwe1bmjQa: Failed to parse XML (caused by ParseError('no element found: line 1, column 0')); please report this issue on  https://github.com/yt- | 24.7s |
| NBC | ytdlp | 失败 | ERROR: [NBC] 9000319183: Unable to download JSON metadata: [SSL: UNEXPECTED_EOF_WHILE_READING] EOF occurred in violation of protocol (_ssl.c:1082) (caused by SSLError('[SSL: UNEXPE | 24.4s |
| PBS | ytdlp | 失败 | ERROR: 3043497119: An extractor error has occurred. (caused by KeyError('title')); please report this issue on  https://github.com/yt-dlp/yt-dlp/issues?q= , filling out the appropr | 30.9s |
| MLB | ytdlp | 通过 | MLBVideo	Condensed Game: 2023 All-Star Game	899 | 27.5s |
| MTV | ytdlp | 失败 | ERROR: [mtv] qxjq6t: Unable to download JSON metadata: HTTP Error 404: Not Found (caused by <HTTPError 404: Not Found>) | 30.3s |
| Naver | ytdlp | 失败 | ERROR: 2084516: An extractor error has occurred. (caused by KeyError('result')); please report this issue on  https://github.com/yt-dlp/yt-dlp/issues?q= , filling out the appropria | 27.9s |
| Bilibili | native | 通过 | BiliBili	字幕君交流场所	2055.637 | 23.6s |
| Douyin | native | 失败 | ERROR: [Douyin] 7701030749851389219: Fresh cookies (not necessarily logged in) are needed | 24.4s |
> 说明：Douyin 行的失败是 **yt-dlp 直跑**需要 cookie，不代表原生插件；TikTok 2.0.19 已改为原生插件，下一次样本验证会更新。X 的样本被冻结、YouTube 样本私有、Twitch VOD 已删除，属于样本失效。


## P0 站点（35 个）

| 站点 | Downie 类 | 域名 | 状态 | 已验证 | 优先级 | 备注 |
|---|---|---|---|---|---|---|
| Bilibili | BilibiliDownloader | https://bilibili.com, http://www.bilibili.tv, http://api.bilibili.com | 原生插件 | 是 | P0 | 2026-10-27 样本解析通过 |
| Douyin | DouyinDownloader | https://www.douyin.com, https://live.douyin.com, https://music.douyin.com | 原生插件 | 是 | P0 |  |
| TikTok | TikTokDownloader | https://www.tiktok.com | 原生插件 | 否 | P0 |  |
| Weibo | WeiboDownloader | https://weibo.com, https://www.weibo.com, http://video.weibo.com | 原生插件 | 否 | P0 |  |
| AbemaTV | AbemaTVDownloader |  | yt-dlp（待验证） | 否 | P0 |  |
| BBC | BBCDownloader | http://www.bbc.com, https://www.bbc.com, http://www.bbc.co.uk | yt-dlp（待验证） | 否 | P0 |  |
| CBS | CBSDownloader | http://www.cbs.com, https://can.cbs.com, https://www.cbs.com | yt-dlp（待验证） | 否 | P0 |  |
| CCTV | CCTVDownloader | http://tv.cctv.cn, http://app.cctv.com, http://news.cctv.com | yt-dlp（待验证） | 是 | P0 | 2026-10-27 样本解析通过 |
| ESPN | ESPNDownloader | http://espn.go.com, http://www.espn.com, https://www.espn.com | yt-dlp（待验证） | 否 | P0 |  |
| Facebook | FacebookDownloader | https://www.facebook.com | yt-dlp（待验证） | 否 | P0 |  |
| Fox | FoxDownloader | http://www.fox.com, https://www.fox.com, https://api3.fox.com | yt-dlp（待验证） | 否 | P0 |  |
| Instagram | InstagramDownloader | http://instagram.com, https://i.instagram.com, https://www.instagram.com | yt-dlp（待验证） | 否 | P0 |  |
| Kakao | KakaoDownloader | https://kakaotv.daum.net, https://play-tv.kakao.com | yt-dlp（待验证） | 否 | P0 |  |
| Kaltura | KalturaDownloader | http://www.kaltura.com, http://cdnapi.kaltura.com, https://cdnapisec.kaltura.com | yt-dlp（待验证） | 否 | P0 | generic/base |
| MLB | MLBDownloader | https://www.mlb.com, https://dapi.cms.mlbinfra.com, https://media-gateway.mlb.com | yt-dlp（待验证） | 是 | P0 | 2026-10-27 样本解析通过 |
| MTV | MTVDownloader | http://www.mtv.com, http://media.mtvnservices.com, https://media-utils.mtvnservices.com | yt-dlp（待验证） | 否 | P0 |  |
| Naver | NaverDownloader | http://tv.naver.com, https://m.naver.com, http://m.tv.naver.com | yt-dlp（待验证） | 否 | P0 |  |
| NBC | NBCDownloader | https://api.nbc.com, https://www.nbc.com, http://www.msnbc.com | yt-dlp（待验证） | 否 | P0 |  |
| PBS | PBSDownloader | https://pbskids.org, https://player.pbs.org, https://www.pbslearningmedia.org | yt-dlp（待验证） | 否 | P0 |  |
| Pinterest | PinterestDownloader | https://www.pinterest.at, https://www.pinterest.com | yt-dlp（待验证） | 是 | P0 | 2026-10-27 样本解析通过 |
| Radiko | RadikoDownloader | https://radiko.jp, https://api.radiko.jp | yt-dlp（待验证） | 否 | P0 |  |
| Reddit | RedditDownloader | http://reddit.tv, http://www.reddit.com, https://www.reddit.com | yt-dlp（待验证） | 否 | P0 |  |
| Rumble | RumbleDownloader | https://rumble.com | yt-dlp（待验证） | 否 | P0 |  |
| Soundcloud | SoundcloudDownloader | https://soundcloud.com, https://api.soundcloud.com, http://api-v2.soundcloud.com | yt-dlp（待验证） | 是 | P0 | 2026-10-27 样本解析通过 |
| Twitch | TwitchDownloader | https://twitch.tv, https://api.twitch.tv, https://gql.twitch.tv | yt-dlp（待验证） | 否 | P0 |  |
| Twitter | TwitterDownloader |  | yt-dlp（待验证） | 否 | P0 |  |
| Udemy | UdemyDownloader | https://www.udemy.com | yt-dlp（待验证） | 否 | P0 |  |
| Vimeo | VimeoDownloader | http://vimeo.com, https://vimeo.com, https://vimeopro.com | yt-dlp（待验证） | 否 | P0 |  |
| WeTV | WeTVDownloader | https://wetv.vip, https://play.wetv.vip | yt-dlp（待验证） | 否 | P0 |  |
| Youku | YoukuDownloader | http://youku.com, http://m.youku.com, http://v.youku.com | yt-dlp（待验证） | 是 | P0 | 2026-10-27 样本解析通过 |
| YouTube | YouTubeDownloader | https://youtube.com, https://m.youtube.com, http://www.youtube.com | yt-dlp（待验证） | 否 | P0 |  |
| JWPlayer | JWPlayerDownloader | https://cdn.jwplayer.com | 通用资源检测（未复刻） | 否 | P0 | generic/base；未原生复刻，需通用资源检测/自定义集成验证 |
| Odysee | OdyseeDownloader | https://odysee.com, https://api.na-backend.odysee.com | 通用资源检测（未复刻） | 否 | P0 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Wavve | WavveDownloader | https://www.wavve.com, https://apis.wavve.com | 通用资源检测（未复刻） | 否 | P0 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Disney | DisneyDownloader | http://video.disney.com, http://watchdisneyxd.go.com | DRM（不支持） | 否 | P0 | DRM host: Downie refuses |

## 已原生复刻

| 站点 | Downie 类 | 域名 | 状态 | 已验证 | 优先级 | 备注 |
|---|---|---|---|---|---|---|
| Bilibili | BilibiliDownloader | https://bilibili.com, http://www.bilibili.tv, http://api.bilibili.com | 原生插件 | 是 | P0 | 2026-10-27 样本解析通过 |
| Douyin | DouyinDownloader | https://www.douyin.com, https://live.douyin.com, https://music.douyin.com | 原生插件 | 是 | P0 |  |
| TikTok | TikTokDownloader | https://www.tiktok.com | 原生插件 | 否 | P0 |  |
| Weibo | WeiboDownloader | https://weibo.com, https://www.weibo.com, http://video.weibo.com | 原生插件 | 否 | P0 |  |
| BilibiliBangumi | BilibiliBangumiDownloader |  | 原生插件 | 否 | P1 |  |
| BilibiliEmbed | BilibiliEmbedDownloader |  | 原生插件 | 否 | P1 |  |
| Iesdouyin | IesdouyinDownloader | https://www.iesdouyin.com | 原生插件 | 是 | P1 |  |
| Kuaishou | KuaishouDownloader | https://www.kuaishou.com, https://live.kuaishou.com | 原生插件 | 否 | P1 |  |
| WeiboHTML5 | WeiboHTML5Downloader |  | 原生插件 | 否 | P1 |  |

## yt-dlp 功能覆盖（代码未复刻，待逐站验证）

| 站点 | Downie 类 | 域名 | 状态 | 已验证 | 优先级 | 备注 |
|---|---|---|---|---|---|---|
| AbemaTV | AbemaTVDownloader |  | yt-dlp（待验证） | 否 | P0 |  |
| BBC | BBCDownloader | http://www.bbc.com, https://www.bbc.com, http://www.bbc.co.uk | yt-dlp（待验证） | 否 | P0 |  |
| CBS | CBSDownloader | http://www.cbs.com, https://can.cbs.com, https://www.cbs.com | yt-dlp（待验证） | 否 | P0 |  |
| CCTV | CCTVDownloader | http://tv.cctv.cn, http://app.cctv.com, http://news.cctv.com | yt-dlp（待验证） | 是 | P0 | 2026-10-27 样本解析通过 |
| ESPN | ESPNDownloader | http://espn.go.com, http://www.espn.com, https://www.espn.com | yt-dlp（待验证） | 否 | P0 |  |
| Facebook | FacebookDownloader | https://www.facebook.com | yt-dlp（待验证） | 否 | P0 |  |
| Fox | FoxDownloader | http://www.fox.com, https://www.fox.com, https://api3.fox.com | yt-dlp（待验证） | 否 | P0 |  |
| Instagram | InstagramDownloader | http://instagram.com, https://i.instagram.com, https://www.instagram.com | yt-dlp（待验证） | 否 | P0 |  |
| Kakao | KakaoDownloader | https://kakaotv.daum.net, https://play-tv.kakao.com | yt-dlp（待验证） | 否 | P0 |  |
| Kaltura | KalturaDownloader | http://www.kaltura.com, http://cdnapi.kaltura.com, https://cdnapisec.kaltura.com | yt-dlp（待验证） | 否 | P0 | generic/base |
| MLB | MLBDownloader | https://www.mlb.com, https://dapi.cms.mlbinfra.com, https://media-gateway.mlb.com | yt-dlp（待验证） | 是 | P0 | 2026-10-27 样本解析通过 |
| MTV | MTVDownloader | http://www.mtv.com, http://media.mtvnservices.com, https://media-utils.mtvnservices.com | yt-dlp（待验证） | 否 | P0 |  |
| Naver | NaverDownloader | http://tv.naver.com, https://m.naver.com, http://m.tv.naver.com | yt-dlp（待验证） | 否 | P0 |  |
| NBC | NBCDownloader | https://api.nbc.com, https://www.nbc.com, http://www.msnbc.com | yt-dlp（待验证） | 否 | P0 |  |
| PBS | PBSDownloader | https://pbskids.org, https://player.pbs.org, https://www.pbslearningmedia.org | yt-dlp（待验证） | 否 | P0 |  |
| Pinterest | PinterestDownloader | https://www.pinterest.at, https://www.pinterest.com | yt-dlp（待验证） | 是 | P0 | 2026-10-27 样本解析通过 |
| Radiko | RadikoDownloader | https://radiko.jp, https://api.radiko.jp | yt-dlp（待验证） | 否 | P0 |  |
| Reddit | RedditDownloader | http://reddit.tv, http://www.reddit.com, https://www.reddit.com | yt-dlp（待验证） | 否 | P0 |  |
| Rumble | RumbleDownloader | https://rumble.com | yt-dlp（待验证） | 否 | P0 |  |
| Soundcloud | SoundcloudDownloader | https://soundcloud.com, https://api.soundcloud.com, http://api-v2.soundcloud.com | yt-dlp（待验证） | 是 | P0 | 2026-10-27 样本解析通过 |
| Twitch | TwitchDownloader | https://twitch.tv, https://api.twitch.tv, https://gql.twitch.tv | yt-dlp（待验证） | 否 | P0 |  |
| Twitter | TwitterDownloader |  | yt-dlp（待验证） | 否 | P0 |  |
| Udemy | UdemyDownloader | https://www.udemy.com | yt-dlp（待验证） | 否 | P0 |  |
| Vimeo | VimeoDownloader | http://vimeo.com, https://vimeo.com, https://vimeopro.com | yt-dlp（待验证） | 否 | P0 |  |
| WeTV | WeTVDownloader | https://wetv.vip, https://play.wetv.vip | yt-dlp（待验证） | 否 | P0 |  |
| Youku | YoukuDownloader | http://youku.com, http://m.youku.com, http://v.youku.com | yt-dlp（待验证） | 是 | P0 | 2026-10-27 样本解析通过 |
| YouTube | YouTubeDownloader | https://youtube.com, https://m.youtube.com, http://www.youtube.com | yt-dlp（待验证） | 否 | P0 |  |
| ABCNews | ABCNewsDownloader | http://abcnews.go.com, https://abcnews.go.com | yt-dlp（待验证） | 否 | P1 |  |
| Acast | AcastDownloader | https://play.acast.com, https://embed.acast.com, https://feeder.acast.com | yt-dlp（待验证） | 否 | P1 |  |
| AcFun | AcFunDownloader | http://acfun.cn, http://m.acfun.cn, http://www.acfun.cn | yt-dlp（待验证） | 否 | P1 |  |
| AcFunBangumi | AcFunBangumiDownloader |  | yt-dlp（待验证） | 否 | P1 |  |
| Adobe | AdobeDownloader | http://tv.adobe.com, https://www-ccv.adobe.io, http://video.tv.adobe.com | yt-dlp（待验证） | 否 | P1 |  |
| AdultSwim | AdultSwimDownloader | http://www.adultswim.com, https://www.adultswim.com | yt-dlp（待验证） | 否 | P1 |  |
| Allocine | AllocineDownloader | http://www.allocine.fr | yt-dlp（待验证） | 否 | P1 |  |
| AmericasTestKitchen | AmericasTestKitchenDownloader | http://www.americastestkitchen.com, https://www.americastestkitchen.com | yt-dlp（待验证） | 否 | P1 |  |
| AnimalPlanet | AnimalPlanetDownloader | https://www.animalplanet.com | yt-dlp（待验证） | 否 | P1 |  |
| Antenna | AntennaDownloader | https://api.antenna.gr, https://vod.antenna.gr | yt-dlp（待验证） | 否 | P1 |  |
| Anvato | AnvatoDownloader |  | yt-dlp（待验证） | 否 | P1 |  |
| Aparat | AparatDownloader | https://www.aparat.com | yt-dlp（待验证） | 否 | P1 |  |
| ARD | ARDDownloader | http://ard.de, https://streamyard.com, https://play.vidyard.com | yt-dlp（待验证） | 否 | P1 |  |
| Areena | AreenaDownloader | https://areena.yle.fi | yt-dlp（待验证） | 否 | P1 |  |
| ArteTV | ArteTVDownloader |  | yt-dlp（待验证） | 否 | P1 |  |
| Artv | ArtvDownloader |  | yt-dlp（待验证） | 否 | P1 |  |
| AtresPlayer | AtresPlayerDownloader | https://api.atresplayer.com, https://www.atresplayer.com | yt-dlp（待验证） | 否 | P1 |  |
| ATV | ATVDownloader | http://atv.at, https://www.alphatv.gr, http://www.documaniatv.com | yt-dlp（待验证） | 否 | P1 |  |
| Baidu | BaiduDownloader | https://mbd.baidu.com, https://pan.baidu.com, https://baike.baidu.com | yt-dlp（待验证） | 否 | P1 |  |
| Bandcamp | BandcampDownloader | https://bitesizedaudio.bandcamp.com, https://synteleiaofficial.bandcamp.com | yt-dlp（待验证） | 否 | P1 |  |
| Beeg | BeegDownloader | http://beeg.com, https://beeg.com, https://video.beeg.com | yt-dlp（待验证） | 否 | P1 |  |
| Bigo | BigoDownloader | https://ta.bigo.tv, https://www.bigo.tv | yt-dlp（待验证） | 否 | P1 |  |
| Bild | BildDownloader | http://www.bild.de | yt-dlp（待验证） | 否 | P1 |  |
| BilibiliAudio | BilibiliAudioDownloader |  | yt-dlp（待验证） | 否 | P1 |  |
| BitChute | BitChuteDownloader | https://api.bitchute.com, https://www.bitchute.com | yt-dlp（待验证） | 否 | P1 |  |
| Blogger | BloggerDownloader | https://www.blogger.com | yt-dlp（待验证） | 否 | P1 |  |
| Bloomberg | BloombergDownloader | http://www.bloomberg.com, https://www.bloomberg.com | yt-dlp（待验证） | 否 | P1 |  |
| Bluesky | BlueskyDownloader |  | yt-dlp（待验证） | 否 | P1 |  |
| Box | BoxDownloader | http://vbox7.com, https://api.box.com, https://app.box.com | yt-dlp（待验证） | 否 | P1 |  |
| BR | BRDownloader | https://lbry.tv, https://www.br.de, http://sfdebris.com | yt-dlp（待验证） | 否 | P1 |  |
| Cam4 | Cam4Downloader | https://www.cam4.com | yt-dlp（待验证） | 否 | P1 |  |
| CanalPlus | CanalPlusDownloader | http://www.canalplus.fr, https://www.canalplus.com, http://player.canalplus.fr | yt-dlp（待验证） | 否 | P1 |  |
| CBSLocal | CBSLocalDownloader | http://gooddaysacramento.cbslocal.com | yt-dlp（待验证） | 否 | P1 |  |
| CBSNews | CBSNewsDownloader | http://www.cbsnews.com, https://www.cbsnews.com | yt-dlp（待验证） | 否 | P1 |  |
| CDA | CDADownloader | http://m.cda.pl, https://www.cda.pl | yt-dlp（待验证） | 否 | P1 |  |
| CeskaTelevize | CeskaTelevizeDownloader | http://www.ceskatelevize.cz, https://api.ceskatelevize.cz | yt-dlp（待验证） | 否 | P1 |  |
| Chaturbate | ChaturbateDownloader | https://chaturbate., https://fr.chaturbate.com | yt-dlp（待验证） | 否 | P1 |  |
| CloudyCDN | CloudyCDNDownloader | https://embed.cloudycdn.services | yt-dlp（待验证） | 否 | P1 |  |
| Clyp | ClypDownloader | https://api.clyp.it | yt-dlp（待验证） | 否 | P1 |  |
| CNET | CNETDownloader | http://www.cnet.com, https://www.cnet.com | yt-dlp（待验证） | 否 | P1 |  |
| CNN | CNNDownloader | http://www.cnn.com, https://www.cnn.com, http://edition.cnn.com | yt-dlp（待验证） | 否 | P1 |  |
| ComedyCentral | ComedyCentralDownloader | http://comedycentral.com | yt-dlp（待验证） | 否 | P1 |  |
| Coub | CoubDownloader | http://coub.com, https://coub.com, http://c-cdn.coub.com | yt-dlp（待验证） | 否 | P1 |  |
| CP24 | CP24Downloader | http://www.cp24.com | yt-dlp（待验证） | 否 | P1 |  |
| CPAC | CPACDownloader | http://www.cpac.ca | yt-dlp（待验证） | 否 | P1 |  |
| CSPAN | CSPANDownloader |  | yt-dlp（待验证） | 否 | P1 |  |
| CTVNews | CTVNewsDownloader | http://ctvnews.ca | yt-dlp（待验证） | 否 | P1 |  |
| CultureUnplugged | CultureUnpluggedDownloader | http://www.cultureunplugged.com | yt-dlp（待验证） | 否 | P1 |  |
| DailyMail | DailyMailDownloader | http://www.dailymail.co.uk | yt-dlp（待验证） | 否 | P1 |  |
| DailyMotion | DailyMotionDownloader | http://www.dailymotion.com, https://geo.dailymotion.com, https://www.dailymotion.com | yt-dlp（待验证） | 否 | P1 |  |
| Daum | DaumDownloader | https://kamp.daum.net, https://kakaotv.daum.net | yt-dlp（待验证） | 否 | P1 |  |
| Discovery | DiscoveryDownloader | https://api.discovery.com, https://www.discoverygo.com, http://science.discovery.com | yt-dlp（待验证） | 否 | P1 |  |
| Douyu | DouyuDownloader | https://v.douyu.com, https://www.douyu.com | yt-dlp（待验证） | 否 | P1 |  |
| DR | DRDownloader | http://www.dr.dk, http://www.ndr.de, https://www.dr.dk | yt-dlp（待验证） | 否 | P1 |  |
| Dropbox | DropboxDownloader | https://www.dropbox.com, https://api.dropboxapi.com, https://replay.dropbox.com | yt-dlp（待验证） | 否 | P1 |  |
| DrTuber | DrTuberDownloader | http://www.drtuber.com | yt-dlp（待验证） | 否 | P1 |  |
| DTU | DTUDownloader | https://video.dtu.dk, http://www.godtube.com, http://www.redtube.com | yt-dlp（待验证） | 否 | P1 |  |
| Dumpert | DumpertDownloader | http://www.dumpert.nl, https://www.dumpert.nl | yt-dlp（待验证） | 否 | P1 |  |
| DW | DWDownloader | http://www.dw.de, http://www.dw.com | yt-dlp（待验证） | 否 | P1 |  |
| EggHead | EggHeadDownloader |  | yt-dlp（待验证） | 否 | P1 |  |
| EITB | EITBDownloader | https://mam.eitb.eus, https://www.eitb.eus | yt-dlp（待验证） | 否 | P1 |  |
| EmpFlix | EmpFlixDownloader | https://www.empflix.com | yt-dlp（待验证） | 否 | P1 |  |
| Eporner | EpornerDownloader | http://www.eporner.com, https://www.eporner.com | yt-dlp（待验证） | 否 | P1 |  |
| ERT | ERTDownloader | http://overthumbs.com, http://www.dumpert.nl, https://www.dumpert.nl | yt-dlp（待验证） | 否 | P1 |  |
| FC2 | FC2Downloader | http://video.fc2.com, https://video.fc2.com | yt-dlp（待验证） | 否 | P1 |  |
| Flickr | FlickrDownloader | https://api.flickr.com, https://www.flickr.com | yt-dlp（待验证） | 否 | P1 |  |
| FoodNetwork | FoodNetworkDownloader | https://watch.foodnetwork.com | yt-dlp（待验证） | 否 | P1 |  |
| Formula1 | Formula1Downloader | https://f1tv.formula1.com | yt-dlp（待验证） | 否 | P1 |  |
| FoxNews | FoxNewsDownloader | https://api.foxnews.com, https://www.foxnews.com, http://video.foxnews.com | yt-dlp（待验证） | 否 | P1 |  |
| FoxSports | FoxSportsDownloader | https://www.foxsports.com | yt-dlp（待验证） | 否 | P1 |  |
| FranceTV | FranceTVDownloader | http://geo.francetv.fr, http://embed.francetv.fr, http://pluzzvad.francetv.fr | yt-dlp（待验证） | 否 | P1 |  |
| FrontendMasters | FrontendMastersDownloader |  | yt-dlp（待验证） | 否 | P1 |  |
| Fux | FuxDownloader | http://www.fux.com, https://www.fux.com, https://token.fux.com | yt-dlp（待验证） | 否 | P1 |  |
| Gaia | GaiaDownloader | https://www.gaia.com, https://gaiamount.com, http://www.gaiamount.com | yt-dlp（待验证） | 否 | P1 |  |
| Gamespot | GamespotDownloader | http://www.gamespot.com | yt-dlp（待验证） | 否 | P1 |  |
| GetCourse | GetCourseDownloader |  | yt-dlp（待验证） | 否 | P1 |  |
| Globo | GloboDownloader | http://globotv.globo.com, http://globoplay.globo.com, https://api.globovideos.com | yt-dlp（待验证） | 否 | P1 |  |
| GodTube | GodTubeDownloader | http://www.godtube.com | yt-dlp（待验证） | 否 | P1 |  |
| HGTV | HGTVDownloader | https://www.hgtv.ca, https://watch.hgtv.com | yt-dlp（待验证） | 否 | P1 |  |
| History | HistoryDownloader | http://www.history.com, https://www.history.com, https://watch.historyvault.com | yt-dlp（待验证） | 否 | P1 |  |
| HotNewHipHop | HotNewHipHopDownloader | http://www.hotnewhiphop.com | yt-dlp（待验证） | 否 | P1 |  |
| Hotstar | HotstarDownloader | http://www.hotstar.com, https://www.hotstar.com | yt-dlp（待验证） | 否 | P1 |  |
| Huya | HuyaDownloader | http://v.huya.com, http://v-api-play.huya.com | yt-dlp（待验证） | 否 | P1 |  |
| IGN | IGNDownloader | http://www.ign.com, http://compaign.tudou.com, http://chriswhitedesigns.smugmug.com | yt-dlp（待验证） | 否 | P1 |  |
| IMDb | IMDbDownloader | http://www.imdb.com, https://www.imdb.com | yt-dlp（待验证） | 否 | P1 |  |
| Ina | InaDownloader | https://www.ina.fr, http://www.sina.com, https://player.ina.fr | yt-dlp（待验证） | 否 | P1 |  |
| Indavideo | IndavideoDownloader | http://embed.indavideo.hu, http://amfphp.indavideo.hu | yt-dlp（待验证） | 否 | P1 |  |
| InfoQ | InfoQDownloader | http://www.infoq.com | yt-dlp（待验证） | 否 | P1 |  |
| InvestigationDiscovery | InvestigationDiscoveryDownloader | https://www.investigationdiscovery.com | yt-dlp（待验证） | 否 | P1 |  |
| IOL | IOLDownloader | http://www.iol.pt, http://www.tvi.iol.pt | yt-dlp（待验证） | 否 | P1 |  |
| IPrima | IPrimaDownloader | http://play.iprima.cz, https://api.play-backend.iprima.cz | yt-dlp（待验证） | 否 | P1 |  |
| Iq | IqDownloader | https://www.iq.com, http://www.iqiyi.com, https://www.iqiyi.com | yt-dlp（待验证） | 否 | P1 |  |
| Iqiyi | IqiyiDownloader | http://www.iqiyi.com, https://www.iqiyi.com, http://pps.m.iqiyi.com | yt-dlp（待验证） | 否 | P1 |  |
| ITV | ITVDownloader | https://itvdn.com, https://tubitv.com, https://www.itv.com | yt-dlp（待验证） | 否 | P1 |  |
| Iwara | IwaraDownloader | https://api.iwara.tv, https://www.iwara.tv | yt-dlp（待验证） | 否 | P1 |  |
| Ixigua | IxiguaDownloader | https://m.ixigua.com, https://www.ixigua.com | yt-dlp（待验证） | 否 | P1 |  |
| JOJ | JOJDownloader | https://media.joj.sk, http://profesionali.joj.sk | yt-dlp（待验证） | 否 | P1 |  |
| Jove | JoveDownloader | http://www.jove.com, https://www.jove.com | yt-dlp（待验证） | 否 | P1 |  |
| KelbyOne | KelbyOneDownloader | https://members.kelbyone.com | yt-dlp（待验证） | 否 | P1 |  |
| Kick | KickDownloader | https://kick.com, https://mobile.kick.com | yt-dlp（待验证） | 否 | P1 |  |
| La7 | La7Downloader |  | yt-dlp（待验证） | 否 | P1 |  |
| LCI | LCIDownloader | https://www.lci.fr | yt-dlp（待验证） | 否 | P1 |  |
| Letv | LetvDownloader | http://www.letv.com, http://yuntv.letv.com, http://api.letvcloud.com | yt-dlp（待验证） | 否 | P1 |  |
| Libsyn | LibsynDownloader | http://html5-player.libsyn.com | yt-dlp（待验证） | 否 | P1 |  |
| ListenNotes | ListenNotesDownloader | https://www.listennotes.com | yt-dlp（待验证） | 否 | P1 |  |
| LiTV | LiTVDownloader | https://www.litv.tv | yt-dlp（待验证） | 否 | P1 |  |
| LiveJournal | LiveJournalDownloader |  | yt-dlp（待验证） | 否 | P1 |  |
| Loom | LoomDownloader | https://www.loom.com, http://www.bloomberg.com, https://www.bloomberg.com | yt-dlp（待验证） | 否 | P1 |  |
| LRT | LRTDownloader | https://www.lrt.lt | yt-dlp（待验证） | 否 | P1 |  |
| Lumni | LumniDownloader | https://www.lumni.fr | yt-dlp（待验证） | 否 | P1 |  |
| MagentaMusik | MagentaMusikDownloader | https://www.magentamusik.de | yt-dlp（待验证） | 否 | P1 |  |
| MailRu | MailRuDownloader |  | yt-dlp（待验证） | 否 | P1 |  |
| Markiza | MarkizaDownloader | https://media.cms.markiza.sk, http://videoarchiv.markiza.sk, https://videoarchiv.markiza.sk | yt-dlp（待验证） | 否 | P1 |  |
| Mediaset | MediasetDownloader | http://cdnsel01.mediaset.net, http://www.video.mediaset.it, https://www.iene.mediaset.it | yt-dlp（待验证） | 否 | P1 |  |
| MediaStream | MediaStreamDownloader |  | yt-dlp（待验证） | 否 | P1 |  |
| Medici | MediciDownloader | http://www.medici.tv, https://api.medici.tv, https://www.medici.tv | yt-dlp（待验证） | 否 | P1 |  |
| Meipai | MeipaiDownloader | http://www.meipai.com | yt-dlp（待验证） | 否 | P1 |  |
| Melon | MelonDownloader | https://www.melon.com | yt-dlp（待验证） | 否 | P1 |  |
| Metacritic | MetacriticDownloader | http://www.metacritic.com | yt-dlp（待验证） | 否 | P1 |  |
| MIT | MITDownloader | http://techtv.mit.edu | yt-dlp（待验证） | 否 | P1 |  |
| MixCloud | MixCloudDownloader | http://www.mixcloud.com, https://app.mixcloud.com, https://www.mixcloud.com | yt-dlp（待验证） | 否 | P1 |  |
| MLBTV | MLBTVDownloader |  | yt-dlp（待验证） | 否 | P1 |  |
| MojeVideo | MojeVideoDownloader | https://www.mojevideo.sk, https://cache01.mojevideo.sk | yt-dlp（待验证） | 否 | P1 |  |
| MotorSport | MotorSportDownloader | https://api.motorsport.tv | yt-dlp（待验证） | 否 | P1 |  |
| MySpass | MySpassDownloader | http://www.myspass.de | yt-dlp（待验证） | 否 | P1 |  |
| MyVidster | MyVidsterDownloader | http://www.myvidster.com | yt-dlp（待验证） | 否 | P1 |  |
| NationalGeographic | NationalGeographicDownloader | https://www.nationalgeographic.com, http://video.nationalgeographic.com | yt-dlp（待验证） | 否 | P1 |  |
| NBCNews | NBCNewsDownloader | http://www.nbcnews.com, https://www.nbcnews.com | yt-dlp（待验证） | 否 | P1 |  |
| NBCSports | NBCSportsDownloader | http://vplayer.nbcsports.com | yt-dlp（待验证） | 否 | P1 |  |
| NDR | NDRDownloader | http://www.ndr.de, https://www.ndr.de | yt-dlp（待验证） | 否 | P1 |  |
| Netzkino | NetzkinoDownloader | http://www.netzkino.de, http://api.netzkino.de.simplecache.net, https://pmd.netzkino-seite.netzkino.de | yt-dlp（待验证） | 否 | P1 |  |
| NewGrounds | NewGroundsDownloader | https://www.newgrounds.com | yt-dlp（待验证） | 否 | P1 |  |
| Nexx | NexxDownloader | https://api.nexx.cloud, https://arc.nexx.cloud | yt-dlp（待验证） | 否 | P1 |  |
| NFB | NFBDownloader | http://www.nfb.ca, https://www.nfb.ca | yt-dlp（待验证） | 否 | P1 |  |
| NFL | NFLDownloader | https://www.nfl.com, https://www.inflearn.com, https://ucc-api.inflearn.com | yt-dlp（待验证） | 否 | P1 |  |
| NHKRadio | NHKRadioDownloader |  | yt-dlp（待验证） | 否 | P1 |  |
| Nick | NickDownloader | https://www.nick.com | yt-dlp（待验证） | 否 | P1 |  |
| NicoVideo | NicoVideoDownloader | http://www.nicovideo.jp, https://account.nicovideo.jp | yt-dlp（待验证） | 否 | P1 |  |
| Nonktube | NonktubeDownloader | http://www.nonktube.com | yt-dlp（待验证） | 否 | P1 |  |
| NOS | NOSDownloader |  | yt-dlp（待验证） | 否 | P1 |  |
| Nova | NovaDownloader | http://tn.nova.cz, http://novaplus.nova.cz, https://media.cms.nova.cz | yt-dlp（待验证） | 否 | P1 |  |
| NPO | NPODownloader | http://www.npo.nl, https://inporn.com, http://www.npoplus.nl | yt-dlp（待验证） | 否 | P1 |  |
| NPR | NPRDownloader | http://www.npr.org | yt-dlp（待验证） | 否 | P1 |  |
| NRK | NRKDownloader | http://tv.nrk.no, http://www.nrk.no, https://tv.nrk.no | yt-dlp（待验证） | 否 | P1 |  |
| Nu | NuDownloader | https://www.nu.nl, http://nudeyoga.net, http://www.nuvid.com | yt-dlp（待验证） | 否 | P1 |  |
| NuVid | NuVidDownloader | http://www.nuvid.com | yt-dlp（待验证） | 否 | P1 |  |
| NYTimes | NYTimesDownloader | http://www.nytimes.com, https://www.nytimes.com, https://samizdat-graphql.nytimes.com | yt-dlp（待验证） | 否 | P1 |  |
| NYTimesArticle | NYTimesArticleDownloader |  | yt-dlp（待验证） | 否 | P1 |  |
| NZZ | NZZDownloader | http://www.nzz.ch | yt-dlp（待验证） | 否 | P1 |  |
| Odnoklassniki | OdnoklassnikiDownloader |  | yt-dlp（待验证） | 否 | P1 |  |
| Olympic | OlympicDownloader | https://olympic.org, https://olympics.com, https://www.olympics.com | yt-dlp（待验证） | 否 | P1 |  |
| Omny | OmnyDownloader | https://omny.fm | yt-dlp（待验证） | 否 | P1 |  |
| OnDemandChina | OnDemandChinaDownloader | https://www.ondemandchina.com | yt-dlp（待验证） | 否 | P1 |  |
| Onet | OnetDownloader | http://onet.tv, http://qi.ckm.onetapi.pl | yt-dlp（待验证） | 否 | P1 |  |
| Ontv | OntvDownloader |  | yt-dlp（待验证） | 否 | P1 |  |
| ORF | ORFDownloader | http://fm4.orf.at, http://oe1.orf.at, https://on.orf.at | yt-dlp（待验证） | 否 | P1 |  |
| Panopto | PanoptoDownloader | https://ubc.ca.panopto.com, https://usask.cloud.panopto.eu | yt-dlp（待验证） | 否 | P1 |  |
| PBSKids | PBSKidsDownloader | https://pbskids.org | yt-dlp（待验证） | 否 | P1 |  |
| PlaySuisse | PlaySuisseDownloader | https://www.playsuisse.ch | yt-dlp（待验证） | 否 | P1 |  |
| PluralSight | PluralSightDownloader | https://app.pluralsight.com | yt-dlp（待验证） | 否 | P1 |  |
| PornerBros | PornerBrosDownloader | http://www.pornerbros.com | yt-dlp（待验证） | 否 | P1 |  |
| Pornhub | PornhubDownloader | http://www.pornhub.com, https://www.pornhub.com, http://www.pornhubselect.com | yt-dlp（待验证） | 否 | P1 |  |
| PornTop | PornTopDownloader | https://porntop.com | yt-dlp（待验证） | 否 | P1 |  |
| PornTube | PornTubeDownloader | http://www.porntube.com, https://token.porntube.com | yt-dlp（待验证） | 否 | P1 |  |
| PRX | PRXDownloader | https://m.prx.org, https://exchange.prx.org | yt-dlp（待验证） | 否 | P1 |  |
| PuhuTV | PuhuTVDownloader | https://puhutv.com | yt-dlp（待验证） | 否 | P1 |  |
| QQ | QQDownloader | http://v.qq.com, http://ke.qq.com, https://v.qq.com | yt-dlp（待验证） | 否 | P1 |  |
| RadioCanada | RadioCanadaDownloader |  | yt-dlp（待验证） | 否 | P1 |  |
| RadioFrance | RadioFranceDownloader | https://www.radiofrance.fr | yt-dlp（待验证） | 否 | P1 |  |
| RadioJavan | RadioJavanDownloader | https://www.radiojavan.com | yt-dlp（待验证） | 否 | P1 |  |
| RaiNews | RaiNewsDownloader | http://www.rainews.it | yt-dlp（待验证） | 否 | P1 |  |
| RaiPlay | RaiPlayDownloader | http://www.raiplay.it, http://www.raiplayradio.it, https://www.raiplaysound.it | yt-dlp（待验证） | 否 | P1 |  |
| Redtube | RedtubeDownloader | http://www.redtube.com, https://www.redtube.com | yt-dlp（待验证） | 否 | P1 |  |
| Reuters | ReutersDownloader | http://www.reuters.com, https://www.reuters.com, https://queso.prod.reuters.tv | yt-dlp（待验证） | 否 | P1 |  |
| ReverbNation | ReverbNationDownloader | http://www.reverbnation.com, https://www.reverbnation.com | yt-dlp（待验证） | 否 | P1 |  |
| Rottentomatoes | RottentomatoesDownloader | http://www.rottentomatoes.com | yt-dlp（待验证） | 否 | P1 |  |
| Roya | RoyaDownloader | https://www.roya.tv | yt-dlp（待验证） | 否 | P1 |  |
| Rozhlas | RozhlasDownloader | https://mujrozhlas.cz, https://api.mujrozhlas.cz, https://www.mujrozhlas.cz | yt-dlp（待验证） | 否 | P1 |  |
| RTBF | RTBFDownloader | http://www.rtbf.be, https://www.rtbf.be, https://auvio.rtbf.be | yt-dlp（待验证） | 否 | P1 |  |
| RTVE | RTVEDownloader | http://www.rtve.es, https://www.rtve.es, https://api2.rtve.es | yt-dlp（待验证） | 否 | P1 |  |
| RTVS | RTVSDownloader | http://4d.rtvslo.si, https://www.rtvs.sk, http://api.rtvslo.si | yt-dlp（待验证） | 否 | P1 |  |
| RTVSlo | RTVSloDownloader | http://4d.rtvslo.si, http://api.rtvslo.si, https://api.rtvslo.si | yt-dlp（待验证） | 否 | P1 |  |
| Rutube | RutubeDownloader | http://rutube.ru | yt-dlp（待验证） | 否 | P1 |  |
| SAPO | SAPODownloader | http://videos.sapo.pt, http://rd3.videos.sapo.pt | yt-dlp（待验证） | 否 | P1 |  |
| SBS | SBSDownloader | http://www.sbs6.nl, http://www.sbs.com.au, https://apis.sbs.co.kr | yt-dlp（待验证） | 否 | P1 |  |
| ScienceChannel | ScienceChannelDownloader | https://www.sciencechannel.com | yt-dlp（待验证） | 否 | P1 |  |
| Screencast | ScreencastDownloader | http://www.screencast.com, https://app.screencastify.com, https://watch.screencastify.com | yt-dlp（待验证） | 否 | P1 |  |
| Screencastify | ScreencastifyDownloader | https://app.screencastify.com, https://watch.screencastify.com, https://umbrella.svc.screencastify.com | yt-dlp（待验证） | 否 | P1 |  |
| Sex | SexDownloader | http://www.sex.com, https://manysex.com, https://www.sex.com | yt-dlp（待验证） | 否 | P1 |  |
| Simplecast | SimplecastDownloader | https://api.simplecast.com, https://player.simplecast.com | yt-dlp（待验证） | 否 | P1 |  |
| Sina | SinaDownloader | http://www.sina.com, http://video.sina.com.cn, http://s.video.sina.com.cn | yt-dlp（待验证） | 否 | P1 |  |
| Sky | SkyDownloader | https://bsky.app, http://video.sky.it, https://news.sky.com | yt-dlp（待验证） | 否 | P1 |  |
| Slideshare | SlideshareDownloader | http://www.slideshare.net | yt-dlp（待验证） | 否 | P1 |  |
| Sohu | SohuDownloader | https://tv.sohu.com, http://my.tv.sohu.com, http://hot.vrs.sohu.com | yt-dlp（待验证） | 否 | P1 |  |
| Space | SpaceDownloader | http://vip.9p1.space, http://www.space.com, http://space.tv.cctv.com | yt-dlp（待验证） | 否 | P1 |  |
| SpankBang | SpankBangDownloader | http://spankbang.com, https://spankbang.com | yt-dlp（待验证） | 否 | P1 |  |
| SproutVideo | SproutVideoDownloader | https://videos.sproutvideo.com, https://hls2.videos.sproutvideo.com | yt-dlp（待验证） | 否 | P1 |  |
| SRGSSR | SRGSSRDownloader | http://tp.srgssr.ch, https://il.srgssr.ch, https://tp.srgssr.ch | yt-dlp（待验证） | 否 | P1 |  |
| Stream | StreamDownloader | https://loopstream, http://streamcloud.eu, http://www.ustream.tv | yt-dlp（待验证） | 否 | P1 |  |
| Streamable | StreamableDownloader | https://streamable.com | yt-dlp（待验证） | 否 | P1 |  |
| StripChat | StripChatDownloader | https://stripchat.com, https://hu.stripchat.com | yt-dlp（待验证） | 否 | P1 |  |
| SVT | SVTDownloader | http://www.svt.se, https://api.svt.se, https://www.svtplay.se | yt-dlp（待验证） | 否 | P1 |  |
| TeamCoco | TeamCocoDownloader | http://teamcoco.com, https://teamcoco.com, https://embed.teamcoco.com | yt-dlp（待验证） | 否 | P1 |  |
| TeamTreehouse | TeamTreehouseDownloader | https://teamtreehouse.com | yt-dlp（待验证） | 否 | P1 |  |
| TED | TEDDownloader | http://ed.ted.com, http://www.ted.com, http://chriswhitedesigns.smugmug.com | yt-dlp（待验证） | 否 | P1 |  |
| Tele5 | Tele5Downloader | https://tele5.de, https://www.tele5.de | yt-dlp（待验证） | 否 | P1 |  |
| Telegram | TelegramDownloader |  | yt-dlp（待验证） | 否 | P1 |  |
| TeleQuebec | TeleQuebecDownloader | https://telequebec.tv, https://mnmedias.api.telequebec.tv | yt-dlp（待验证） | 否 | P1 |  |
| TF1 | TF1Downloader | https://www.tf1.fr, https://www.tf1info.fr, https://mediainfo.tf1.fr | yt-dlp（待验证） | 否 | P1 |  |
| TheGuardian | TheGuardianDownloader | https://www.theguardian.com | yt-dlp（待验证） | 否 | P1 |  |
| ThePlatform | ThePlatformDownloader | http://feed.theplatform., http://link.theplatform., https://feed.theplatform. | yt-dlp（待验证） | 否 | P1 |  |
| ThisAmericanLife | ThisAmericanLifeDownloader | http://m.thisamericanlife.org, http://audio.thisamericanlife.org | yt-dlp（待验证） | 否 | P1 |  |
| ThisOldHouse | ThisOldHouseDownloader | https://www.thisoldhouse.com, https://thisoldhouse.chorus.build | yt-dlp（待验证） | 否 | P1 |  |
| TMZ | TMZDownloader | http://www.tmz.com | yt-dlp（待验证） | 否 | P1 |  |
| TNAFlix | TNAFlixDownloader | http://www.tnaflix.com, https://www.tnaflix.com | yt-dlp（待验证） | 否 | P1 |  |
| Today | TodayDownloader | http://www.today.com, https://www.ettoday.net | yt-dlp（待验证） | 否 | P1 |  |
| Toutiao | ToutiaoDownloader | http://www.toutiao.com, https://www.toutiao.com | yt-dlp（待验证） | 否 | P1 |  |
| TravelChannel | TravelChannelDownloader | https://watch.travelchannel.com | yt-dlp（待验证） | 否 | P1 |  |
| Tube8 | Tube8Downloader | http://www.tube8.com | yt-dlp（待验证） | 否 | P1 |  |
| TubiTV | TubiTVDownloader | https://tubitv.com | yt-dlp（待验证） | 否 | P1 |  |
| Tumblr | TumblrDownloader | https://www.tumblr.com, http://flamingteddyproductions.tumblr.com | yt-dlp（待验证） | 否 | P1 |  |
| TV2 | TV2Downloader | http://www.tv2.no, http://sumo.tv2.no, https://sumo.tv2.no | yt-dlp（待验证） | 否 | P1 |  |
| TV5Monde | TV5MondeDownloader | https://api.tv5monde.com, https://revoir.tv5monde.com | yt-dlp（待验证） | 否 | P1 |  |
| TV5Unis | TV5UnisDownloader | https://api.tv5unis.ca | yt-dlp（待验证） | 否 | P1 |  |
| TVC | TVCDownloader | http://www.tvc.ru, http://api.tvcbook.com, http://www.tvcbook.com | yt-dlp（待验证） | 否 | P1 |  |
| TVer | TVerDownloader | https://tver.jp, https://player.tver.jp, https://statics.tver.jp | yt-dlp（待验证） | 否 | P1 |  |
| Tvigle | TvigleDownloader | http://cloud.tvigle.ru | yt-dlp（待验证） | 否 | P1 |  |
| TVN24 | TVN24Downloader | https://tvn24.pl | yt-dlp（待验证） | 否 | P1 |  |
| TVP | TVPDownloader | http://vod.tvp.pl, https://vod.tvp.pl, https://uktvplay.co.uk | yt-dlp（待验证） | 否 | P1 |  |
| TwitCasting | TwitCastingDownloader | https://twitcasting.tv | yt-dlp（待验证） | 否 | P1 |  |
| TXXX | TXXXDownloader | https://www.txxx.com, https://videotxxx.com | yt-dlp（待验证） | 否 | P1 |  |
| URPlay | URPlayDownloader | http://urplay.se, https://urplay.se, https://media-api.urplay.se | yt-dlp（待验证） | 否 | P1 |  |
| USANetwork | USANetworkDownloader | https://www.usanetwork.com | yt-dlp（待验证） | 否 | P1 |  |
| VBOX7 | VBOX7Downloader | http://vbox7.com, https://www.vbox7.com | yt-dlp（待验证） | 否 | P1 |  |
| VGTV | VGTVDownloader | http://www.vgtv.no, https://www.vgtv.no | yt-dlp（待验证） | 否 | P1 |  |
| VH1 | VH1Downloader | http://www.vh1.com | yt-dlp（待验证） | 否 | P1 |  |
| VHX | VHXDownloader | https://api.vhx.tv, https://embed.vhx.tv | yt-dlp（待验证） | 否 | P1 |  |
| Vice | ViceDownloader | http://www.vice.com, https://vms.vice.com, http://embeds.vice.com | yt-dlp（待验证） | 否 | P1 |  |
| Videa | VideaDownloader | https://videa.hu, http://videakid.hu, https://videakid.hu | yt-dlp（待验证） | 否 | P1 |  |
| VideoPress | VideoPressDownloader | https://videopress.com | yt-dlp（待验证） | 否 | P1 |  |
| VidMe | VidMeDownloader |  | yt-dlp（待验证） | 否 | P1 |  |
| Vidyard | VidyardDownloader | https://play.vidyard.com | yt-dlp（待验证） | 否 | P1 |  |
| Viu | ViuDownloader | https://www.viu.com, https://api-gateway-global.viu.com | yt-dlp（待验证） | 否 | P1 |  |
| VK | VKDownloader | http://vk.com, https://vk.ru, https://vk.com | yt-dlp（待验证） | 否 | P1 |  |
| VOD | VODDownloader | http://vod.pl, http://vod.tvp.pl, https://vod.tvp.pl | yt-dlp（待验证） | 否 | P1 |  |
| Vox | VoxDownloader | https://volume.vox-cdn.com | yt-dlp（待验证） | 否 | P1 |  |
| VRT | VRTDownloader | https://www.vrt.be, https://media-services-public.vrt.be | yt-dlp（待验证） | 否 | P1 |  |
| WDR | WDRDownloader | http://www1.wdr.de, https://kinder.wdr.de | yt-dlp（待验证） | 否 | P1 |  |
| Weather | WeatherDownloader | https://weather.com, http://www.weather.com, https://dsx.weather.com | yt-dlp（待验证） | 否 | P1 |  |
| Weverse | WeverseDownloader | https://weverse.io | yt-dlp（待验证） | 否 | P1 |  |
| WeverseLive | WeverseLiveDownloader |  | yt-dlp（待验证） | 否 | P1 |  |
| Wikimedia | WikimediaDownloader | http://commons.wikimedia.org | yt-dlp（待验证） | 否 | P1 |  |
| Wistia | WistiaDownloader | http://fast.wistia.com, http://fast.wistia.net, https://fast.wistia.com | yt-dlp（待验证） | 否 | P1 |  |
| WSJ | WSJDownloader | https://www.wsj.com, http://video-api.wsj.com, https://video-api.wsj.com | yt-dlp（待验证） | 否 | P1 |  |
| WWE | WWEDownloader | https://watch.wwe.com, http://network.wwe.com, https://cdn.watch.wwe.com | yt-dlp（待验证） | 否 | P1 |  |
| XHamster | XHamsterDownloader | http://xhamster.com, http://xhamster.xxx, https://xhamster.com | yt-dlp（待验证） | 否 | P1 |  |
| Xiaohongshu | XiaohongshuDownloader | https://www.xiaohongshu.com | yt-dlp（待验证） | 否 | P1 |  |
| Ximalaya | XimalayaDownloader | https://m.ximalaya.com, http://www.ximalaya.com, https://www.ximalaya.com | yt-dlp（待验证） | 否 | P1 |  |
| Xinpianchang | XinpianchangDownloader | http://www.xinpianchang.com, https://www.xinpianchang.com, https://mod-api.xinpianchang.com | yt-dlp（待验证） | 否 | P1 |  |
| XNXX | XNXXDownloader | http://www.xnxx.com | yt-dlp（待验证） | 否 | P1 |  |
| XVideos | XVideosDownloader | http://www.xvideos.com, https://www.xvideos.com, http://flashservice.xvideos.com | yt-dlp（待验证） | 否 | P1 |  |
| Yahoo | YahooDownloader | https://www.yahoo.com, http://screen.yahoo.com, https://video.yahoo.com | yt-dlp（待验证） | 否 | P1 |  |
| YapFiles | YapFilesDownloader | http://www.yapfiles.ru | yt-dlp（待验证） | 否 | P1 |  |
| YouJizz | YouJizzDownloader | http://www.youjizz.com | yt-dlp（待验证） | 否 | P1 |  |
| YouPorn | YouPornDownloader | http://www.youporn.com, https://www.youporn.com | yt-dlp（待验证） | 否 | P1 |  |
| ZDF | ZDFDownloader | http://zdf.de, https://www.zdf.de | yt-dlp（待验证） | 否 | P1 |  |
| Zhihu | ZhihuDownloader | https://lens.zhihu.com, https://video.zhihu.com | yt-dlp（待验证） | 否 | P1 |  |
| Zing | ZingDownloader | http://mp3.zing.vn | yt-dlp（待验证） | 否 | P1 |  |
| Zoom | ZoomDownloader | https://zoom.us, https://trhc.zoom.us, https://us02web.zoom.us | yt-dlp（待验证） | 否 | P1 |  |
| Zype | ZypeDownloader | https://player.zype.com | yt-dlp（待验证） | 否 | P1 |  |
| XU | XUDownloader | https://article.xuexi.cn | yt-dlp（待验证） | 否 | P2 | generic/base |

## 通用资源检测/未复刻（需逐站验证）

| 站点 | Downie 类 | 域名 | 状态 | 已验证 | 优先级 | 备注 |
|---|---|---|---|---|---|---|
| JWPlayer | JWPlayerDownloader | https://cdn.jwplayer.com | 通用资源检测（未复刻） | 否 | P0 | generic/base；未原生复刻，需通用资源检测/自定义集成验证 |
| Odysee | OdyseeDownloader | https://odysee.com, https://api.na-backend.odysee.com | 通用资源检测（未复刻） | 否 | P0 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Wavve | WavveDownloader | https://www.wavve.com, https://apis.wavve.com | 通用资源检测（未复刻） | 否 | P0 | 未原生复刻，需通用资源检测/自定义集成验证 |
| ABCiView | ABCiViewDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| ABCShows | ABCShowsDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| AbsoluPorn | AbsoluPornDownloader | http://www.absoluporn.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| AcastEmbed | AcastEmbedDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| AdobeCC | AdobeCCDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| AdobeKnowHow | AdobeKnowHowDownloader | https://www.adobeknowhow.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| AdultSwimVideo | AdultSwimVideoDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| AETV | AETVDownloader | https://play.aetv.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Afamily | AfamilyDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| AfreecaTV | AfreecaTVDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Aftenposten | AftenpostenDownloader | http://www.aftenposten.no | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| AhMe | AhMeDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Aktualne | AktualneDownloader | http://video.aktualne.cz, https://video.aktualne.cz | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| AlphaTV | AlphaTVDownloader | https://www.alphatv.gr | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| AmazonShopping | AmazonShoppingDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Analdin | AnaldinDownloader | http://www.analdin.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| AnimeDigitalNetwork | AnimeDigitalNetworkDownloader | https://animedigitalnetwork.fr | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Animelek | AnimelekDownloader | http://player.animelek.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| AnyPorn | AnyPornDownloader | http://anyporn.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| AppleDeveloper | AppleDeveloperDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| ApplePodcasts | ApplePodcastsDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| ARDSounds | ARDSoundsDownloader | https://www.ardsounds.de | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| ArteEmbeddedPlaylist | ArteEmbeddedPlaylistDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| ArtePlaylist | ArtePlaylistDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| ArteTVVideos | ArteTVVideosDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| AT5 | AT5Downloader | http://www.at5.nl | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| AtresPlayerEpisode | AtresPlayerEpisodeDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Avgle | AvgleDownloader | https://avgle.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| AvgleConfiguration | AvgleConfigurationDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Awaan | AwaanDownloader | http://www.awaan.ae | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| AwwwardsAcademy | AwwwardsAcademyDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Baofeng | BaofengDownloader | http://www.baofeng.com, http://rd.p2p.baofeng.net | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| BBCArchives | BBCArchivesDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| BBCEventPlayer | BBCEventPlayerDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| BBCIdeas | BBCIdeasDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| BBCNews | BBCNewsDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| BBCPlaylistItem | BBCPlaylistItemDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| BBCRadio | BBCRadioDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| BBCRewind | BBCRewindDownloader | https://bbcrewind.co.uk | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| BBCTeach | BBCTeachDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| BBCVideos | BBCVideosDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| BedBathAndBeyond | BedBathAndBeyondDownloader | https://video.bedbathandbeyond.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| BFIPlayer | BFIPlayerDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| BilibiliCool | BilibiliCoolDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| BilibiliInternational | BilibiliInternationalDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| BilibiliMovie | BilibiliMovieDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| BilibiliNew | BilibiliNewDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Blick | BlickDownloader | http://www.blick.ch | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| BokeCC | BokeCCDownloader | http://p.bokecc.com, https://p.bokecc.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Boomplay | BoomplayDownloader | https://www.boomplay.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| BoyzTube | BoyzTubeDownloader | http://www.boyztube.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| BravoTube | BravoTubeDownloader | http://www.bravotube.net | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| BritishLibrary | BritishLibraryDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| BritishPathe | BritishPatheDownloader | http://www.britishpathe.com, http://streaming.britishpathe.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| BRKlassik | BRKlassikDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| BRVideo | BRVideoDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| CartoonNetwork | CartoonNetworkDownloader | http://www.cartoonnetwork.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| CBBC | CBBCDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| CBCCanada | CBCCanadaDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| CBCCanadaArchive | CBCCanadaArchiveDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| CBCCanadaEmbedded | CBCCanadaEmbeddedDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| CBCCanadaRadio | CBCCanadaRadioDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| CBCGem | CBCGemDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| CBCGemMediaID | CBCGemMediaIDDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| CBCWatch | CBCWatchDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| CBCWatchEmbedded | CBCWatchEmbeddedDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| CBSNewsStory | CBSNewsStoryDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| CCHR | CCHRDownloader | http://fr.cchr.org | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| CCTalk | CCTalkDownloader | https://www.cctalk.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| CCTVGUID | CCTVGUIDDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| CCTVSpecial | CCTVSpecialDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| CCTVSports | CCTVSportsDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Channel4 | Channel4Downloader | https://www.channel4.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| ChefKoch | ChefKochDownloader | https://www.chefkoch.de | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| ChicagoTribune | ChicagoTribuneDownloader | http://www.chicagotribune.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Cineversity | CineversityDownloader | http://www.cineversity.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Cliphunter | CliphunterDownloader | http://www.cliphunter.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| CNNArticle | CNNArticleDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| CNTV | CNTVDownloader | http://tv.cntv.cn, http://news.cntv.cn, https://api.cntv.cn | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| CNTVConfig | CNTVConfigDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| CNTVNews | CNTVNewsDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| CNTVSports | CNTVSportsDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| CooksCountry | CooksCountryDownloader | http://www.cookscountry.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Corriere | CorriereDownloader | http://video.corriere.it | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Coursera | CourseraDownloader | https://www.coursera.org | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| CreativeLive | CreativeLiveDownloader | https://www.creativelive.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Crehana | CrehanaDownloader | https://www.crehana.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Culturebox | CultureboxDownloader | http://culturebox.francetvinfo.fr | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| CustomIntegration | CustomIntegrationDownloader |  | 通用资源检测（未复刻） | 否 | P1 | custom integration；未原生复刻，需通用资源检测/自定义集成验证 |
| CustomIntegrationDownload | CustomIntegrationDownloadDownloader |  | 通用资源检测（未复刻） | 否 | P1 | custom integration；未原生复刻，需通用资源检测/自定义集成验证 |
| CWSeed | CWSeedDownloader | http://cwseed.com, http://www.cwseed.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| CWTV | CWTVDownloader | http://cwtv.com, http://www.cwtv.com, https://images.cwtv.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| CZTV | CZTVDownloader | http://tv.cztv.com, http://zvod.cztv.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| DailyKos | DailyKosDownloader | http://www.dailykos.com, http://www.dailykostv.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| DasErste | DasErsteDownloader | http://www.daserste.de, https://www.daserste.de | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| DasErsteBase | DasErsteBaseDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| DASHDirect | DASHDirectDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| DavidReviews | DavidReviewsDownloader | http://www.davidreviews.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| DefineBabe | DefineBabeDownloader | http://www.definebabe.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| DeltaBit | DeltaBitDownloader | https://deltabit.co | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| DesiPorn | DesiPornDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Digg | DiggDownloader | http://digg.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Digi24 | Digi24Downloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| DiliDili | DiliDiliDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| DingTalk | DingTalkDownloader | https://n.dingtalk.com, https://h5.dingtalk.com, https://lv.dingtalk.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| DiscoveryBase | DiscoveryBaseDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| DiscoveryGo | DiscoveryGoDownloader | https://www.discoverygo.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| DiscoveryGoBase | DiscoveryGoBaseDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| DNTV | DNTVDownloader | https://dntv.dn.no | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| DocumaniaTV | DocumaniaTVDownloader | http://www.documaniatv.com, https://www.documaniatv.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Domestika | DomestikaDownloader | https://www.domestika.org | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Douban | DoubanDownloader | http://movie.douban.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| DouyinLive | DouyinLiveDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| DouyinMusic | DouyinMusicDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| DouyuLive | DouyuLiveDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| DRDRTV | DRDRTVDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| DropboxReplay | DropboxReplayDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| DRURNBased | DRURNBasedDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| DynTube | DynTubeDownloader | https://api.dyntube.com, https://videos.dyntube.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| EkstraBladet | EkstraBladetDownloader | https://ekstrabladet.dk, https://jw.video.ekstrabladet.dk | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| ElMundo | ElMundoDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Embedy | EmbedyDownloader | https://embedy.cc | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Engineering | EngineeringDownloader | http://www.engineering.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Entensity | EntensityDownloader | http://poststuff5.entensity.net | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| EroVideo | EroVideoDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| ESPNCerebro | ESPNCerebroDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| ESPNWatch | ESPNWatchDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| ETtoday | ETtodayDownloader | https://www.ettoday.net | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| EurosportPlayer | EurosportPlayerDownloader | https://fr.eurosportplayer.com, https://search-api.svcs.eurosportplayer.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| EurosportPlayerPartnerContent | EurosportPlayerPartnerContentDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| EurovisionSports | EurovisionSportsDownloader | http://www.eurovisionsports.tv | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Eventials | EventialsDownloader | https://www.eventials.com, http://ondemand.eventials.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| EZPlayer | EZPlayerDownloader | https://server.ezplayer.net | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| FandangoTrailer | FandangoTrailerDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Fansly | FanslyDownloader | https://fansly.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| FilmsForAction | FilmsForActionDownloader | http://www.filmsforaction.org | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| FilmStarts | FilmStartsDownloader | http://www.filmstarts.de | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Flirt4Free | Flirt4FreeDownloader | https://www.flirt4free.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| FloRacing | FloRacingDownloader | https://www.floracing.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| FlyFLV | FlyFLVDownloader | http://flyflv.com, https://www.flyflv.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| FM4ORF | FM4ORFDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| FoxBusiness | FoxBusinessDownloader | http://video.foxbusiness.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| FrameIO | FrameIODownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| FranceTVEmbed | FranceTVEmbedDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| FujiTV | FujiTVDownloader | https://fod.fujitv.co.jp, https://i.fod.fujitv.co.jp, https://fod-sp.fujitv.co.jp | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| FunnyOrDie | FunnyOrDieDownloader | http://www.funnyordie.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| FunTV | FunTVDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| GaiaMount | GaiaMountDownloader | https://gaiamount.com, http://www.gaiamount.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Gamer | GamerDownloader | https://ani.gamer.com.tw | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| GamerConfiguration | GamerConfigurationDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| GeniusKitchen | GeniusKitchenDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| GlobalNews | GlobalNewsDownloader | http://globalnews.ca | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| GoldPoster | GoldPosterDownloader | http://www.goldposter.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| GoogleDocs | GoogleDocsDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| GoogleUserContent | GoogleUserContentDownloader | https://lh4.googleusercontent.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| GoogleVideo | GoogleVideoDownloader | http://redirector.googlevideo.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Gooqle | GooqleDownloader | https://gooqlevideo.xyz | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| GoPlay | GoPlayDownloader | https://api.goplay.be, https://www.goplay.be | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| GotPorn | GotPornDownloader | http://www.gotporn.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Gulli | GulliDownloader | http://replay.gulli.fr, https://replay.gulli.fr | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Hanime | HanimeDownloader | https://hanime.tv, https://api.hanime.tv | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| HClips | HClipsDownloader | http://www.hclips.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| HDPussy | HDPussyDownloader | http://hdpussy.xxx | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| HDZog | HDZogDownloader | https://hdzog.com, https://www.hdzog.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| HLSDirect | HLSDirectDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| HomeMoviesTube | HomeMoviesTubeDownloader | http://www.homemoviestube.com, https://www.homemoviestube.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Hotmart | HotmartDownloader | https://player.hotmart.com, https://cf-embed.play.hotmart.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| HotMovs | HotMovsDownloader | http://hotmovs.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| HQPorner | HQPornerDownloader | http://hqporner.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| HuffingtonPostCanada | HuffingtonPostCanadaDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| IBM | IBMDownloader | http://video.ibm.com, https://video.ibm.com, https://ibm.ent.box.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| IDnes | IDnesDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Ifeng | IfengDownloader | http://v.ifeng.com, http://tv.ifeng.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| IfengVideo | IfengVideoDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Imomoe | ImomoeDownloader | http://www.imomoe.ai, http://www.imomoe.jp, http://www.imomoe.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| InaEmbed | InaEmbedDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Independent | IndependentDownloader | http://www.independent.ie, http://independent.bbvms.com, http://mm.independent.bbvms.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Inflearn | InflearnDownloader | https://www.inflearn.com, https://ucc-api.inflearn.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| InPorn | InPornDownloader | https://inporn.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| IqiyiAlt | IqiyiAltDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| IqiyiConfiguration | IqiyiConfigurationDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| IqiyiSports | IqiyiSportsDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| ITVDN | ITVDNDownloader | https://itvdn.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| JacquieMichelTV | JacquieMichelTVDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| JamPlay | JamPlayDownloader | http://www.jamplay.com, https://www.jamplay.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| JavTube | JavTubeDownloader | http://www.javtube.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| JibJab | JibJabDownloader | https://www.jibjab.com, https://origin-prod-phoenix.jibjab.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| JWPlayerBase | JWPlayerBaseDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| JWPlayerConfig | JWPlayerConfigDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| KalturaBase | KalturaBaseDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| KalturaConcrete | KalturaConcreteDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| KalturaEmbedFrame | KalturaEmbedFrameDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| KickBase | KickBaseDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| KickLiveStream | KickLiveStreamDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Kijk | KijkDownloader | http://www.kijk.nl, https://www.kijk.nl, https://embed.kijk.nl | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| KijkShortLink | KijkShortLinkDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| KissAnime | KissAnimeDownloader | http://kissanime.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Knowledge | KnowledgeDownloader | https://api.knowledge.ca, https://www.knowledge.ca | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| KuaishouLive | KuaishouLiveDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| KwikMotion | KwikMotionDownloader | https://embed.kwikmotion.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| LaFabriqueCulturelle | LaFabriqueCulturelleDownloader | http://www.lafabriqueculturelle.tv | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| LaPresse | LaPresseDownloader | http://www.lapresse.ca | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| LaSexta | LaSextaDownloader | http://www.lasexta.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| LetvCloud | LetvCloudDownloader | http://api.letvcloud.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| LimelightConcrete | LimelightConcreteDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| LimelightVideoID | LimelightVideoIDDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| LineTV | LineTVDownloader | https://www.linetv.tw | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| LineTVNew | LineTVNewDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| LinkedInLearning | LinkedInLearningDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| LinkedInPost | LinkedInPostDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Macworld | MacworldDownloader | http://www.macworld.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| MaisUOL | MaisUOLDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| ManySex | ManySexDownloader | https://manysex.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Mashable | MashableDownloader | http://mashable.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| MasterClass | MasterClassDownloader | https://www.masterclass.com, https://edge.masterclass.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| MasterDev | MasterDevDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| MediaDelivery | MediaDeliveryDownloader | https://iframe.mediadelivery.net, https://player.mediadelivery.net | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Medscape | MedscapeDownloader | http://www.medscape.com, https://api.medscape.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Meihua | MeihuaDownloader | https://www.meihua.info | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Meloman | MelomanDownloader | http://player.meloman.facecast.net | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| MichelOnfray | MichelOnfrayDownloader | https://michelonfray.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Miguvideo | MiguvideoDownloader | http://m.miguvideo.com, https://www.miguvideo.com, https://v0-sc.miguvideo.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| MixWithTheMasters | MixWithTheMastersDownloader | https://mixwiththemasters.com, https://www.mixwiththemasters.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Motherless | MotherlessDownloader | http://motherless.com, https://motherless.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| MotoGP | MotoGPDownloader | http://www.motogp.com, https://secure.motogp.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Mover | MoverDownloader | http://mover.uz, http://v.mover.uz | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| MP4Upload | MP4UploadDownloader | http://mp4upload.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| MSDN | MSDNDownloader | http://channel9.msdn.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| MSNBCWatch | MSNBCWatchDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| MSNNews | MSNNewsDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| MTVEmbedded | MTVEmbeddedDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| MTVTriforce | MTVTriforceDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Music163 | Music163Downloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| MyDaddy | MyDaddyDownloader | http://mydaddy.cc | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| MyLust | MyLustDownloader | http://mylust.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| MyMuscleVideo | MyMuscleVideoDownloader | http://mymusclevideo.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| MyTVSuper | MyTVSuperDownloader | https://www.mytvsuper.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Nanairo | NanairoDownloader | https://nanairo.co, https://api.nanairo.co | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| NaverCHZZK | NaverCHZZKDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| NaverConfiguration | NaverConfigurationDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| NaverEmbedded | NaverEmbeddedDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| NaverLive | NaverLiveDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| NaverNeonPlayerDash | NaverNeonPlayerDashDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| NaverShorts | NaverShortsDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| NCAA | NCAADownloader | http://www.ncaa.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| NDREmbed | NDREmbedDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Nerdist | NerdistDownloader | http://content.nerdist.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Nhac | NhacDownloader | http://www.nhaccuatui.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| NHKNews | NHKNewsDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| NHKWorld | NHKWorldDownloader | https://api.nhkworld.jp | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Noovo | NoovoDownloader | https://www.noovo.info | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Novinky | NovinkyDownloader | https://novinky.cz, http://www.novinky.cz, https://api-web.novinky.cz | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| NowDownload | NowDownloadDownloader | http://www.nowdownload.ec | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| NowTV | NowTVDownloader | http://www.nowtv.de | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| NRKClip | NRKClipDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| NRKEmbedded | NRKEmbeddedDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| NRKEpisode | NRKEpisodeDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| NudeYoga | NudeYogaDownloader | http://nudeyoga.net | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| NYDailyNews | NYDailyNewsDownloader | https://www.nydailynews.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| NYTimesBase | NYTimesBaseDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| OceanEngine | OceanEngineDownloader | https://school.oceanengine.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| OE1 | OE1Downloader | http://oe1.orf.at, https://oe1.orf.at | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Okjike | OkjikeDownloader | https://m.okjike.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Ololo | OloloDownloader | http://ololo.fm | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Oprah | OprahDownloader | http://www.oprah.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Orange | OrangeDownloader | http://video-streaming.orange.fr | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| OReilly | OReillyDownloader | https://www.oreilly.com, https://learning.oreilly.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Osmosis | OsmosisDownloader | https://www.osmosis.org | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Overthumbs | OverthumbsDownloader | http://overthumbs.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| PanBaidu | PanBaiduDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| PandaVideo | PandaVideoDownloader | https://player-vz-4f008646-5e1.tv.pandavideo.com.br | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| PBSLearningMedia | PBSLearningMediaDownloader | https://www.pbslearningmedia.org | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| PeopleCN | PeopleCNDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| PerfectGirls | PerfectGirlsDownloader | http://www.perfectgirls.net, http://ipad.perfectgirls.net | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| PilatesAnytime | PilatesAnytimeDownloader | http://www.pilatesanytime.com, https://www.pilatesanytime.com, http://videos.pilatesanytime.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| PinShan | PinShanDownloader | http://www.pinshan.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Pitchfork | PitchforkDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| POLYV | POLYVDownloader | http://polyv.net, https://v3.polyv.net, http://static.polyv.net | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| POLYVConfig | POLYVConfigDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| PornDig | PornDigDownloader | http://videos.porndig.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| PornDoe | PornDoeDownloader | https://porndoe.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| PornhubPremium | PornhubPremiumDownloader | https://www.pornhubpremium.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| PornhubSelect | PornhubSelectDownloader | http://www.pornhubselect.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| PornMaki | PornMakiDownloader | http://pornmaki.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Pornolandia | PornolandiaDownloader | http://www.pornolandia.xxx | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| PornTrex | PornTrexDownloader | https://www.porntrex.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| PPTV | PPTVDownloader | http://v.pptv.com, http://web-play.pptv.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| PremierLeague | PremierLeagueDownloader | https://premierleague.com, https://api.premierleague.com, https://www.premierleague.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| PrivateHomeClips | PrivateHomeClipsDownloader | http://privatehomeclips.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| ProSieben | ProSiebenDownloader | http://www.prosieben.at | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| PTSPlus | PTSPlusDownloader | https://www.ptsplus.tv | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| PulsEmbed | PulsEmbedDownloader | http://pulsembed.eu | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| QCloud | QCloudDownloader | http://play.video.qcloud.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Qello | QelloDownloader | https://qello.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| QQBase | QQBaseDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| QQLive | QQLiveDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| QQNew | QQNewDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| QQNews | QQNewsDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| QQPlayer | QQPlayerDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| QQWeishiFeed | QQWeishiFeedDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| QUB | QUBDownloader | https://www.qub.ca | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| R18 | R18Downloader | http://www.r18.com, https://www.r18.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| RadioCanadaConfiguration | RadioCanadaConfigurationDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| RadioJavanMusic | RadioJavanMusicDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| RadioJavanPodcast | RadioJavanPodcastDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| RaiTV | RaiTVDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Rambler | RamblerDownloader | https://vp.rambler.ru, https://api.vp.rambler.ru | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| RedtubeBase | RedtubeBaseDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| RTEEmbed | RTEEmbedDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| RTENew | RTENewDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| RTLBE | RTLBEDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| RTLMost | RTLMostDownloader | https://www.rtlmost.hu | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| RTLXL | RTLXLDownloader | http://www.rtlxl.nl, https://www.rtlxl.nl | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| RTPPlay | RTPPlayDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| RTSShortLinkSwiss | RTSShortLinkSwissDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| RTSSwiss | RTSSwissDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| RTSSwissPlay | RTSSwissPlayDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| RTVEPlay | RTVEPlayDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| RTVETelevision | RTVETelevisionDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Rutv | RutvDownloader | http://player.rutv.ru | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| SBS6 | SBS6Downloader | http://www.sbs6.nl | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| SBSKorea | SBSKoreaDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| ScreenCastsOnline | ScreenCastsOnlineDownloader | http://www.screencastsonline.com, https://www.screencastsonline.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Sendvid | SendvidDownloader | http://sendvid.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| SeriallyProcessed | SeriallyProcessedDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| ServusTV | ServusTVDownloader | https://www.servustv.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| SFDebris | SFDebrisDownloader | http://sfdebris.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Shooshtime | ShooshtimeDownloader | https://shooshtime.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| SinaHTML5 | SinaHTML5Downloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| SinaLive | SinaLiveDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Skillshare | SkillshareDownloader | https://www.skillshare.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| SkyItalia | SkyItaliaDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| SmartEdu | SmartEduDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| SmugglerSite | SmugglerSiteDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| SmugMug | SmugMugDownloader | http://chriswhitedesigns.smugmug.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Smule | SmuleDownloader | http://www.smule.com, https://www.smule.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| SohuTV | SohuTVDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Souncloud | SouncloudDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Soundboard | SoundboardDownloader | http://www.soundboard.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| SoundSlice | SoundSliceDownloader | https://www.soundslice.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| SpankBangPlaylistItem | SpankBangPlaylistItemDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| SpankingTube | SpankingTubeDownloader | http://www.spankingtube.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| SpiegelTV | SpiegelTVDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| SpiegelTVNew | SpiegelTVNewDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| SRF | SRFDownloader | http://www.srf.ch, https://ws.srf.ch | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| StackSkills | StackSkillsDownloader | http://stackskills.com, https://stackskills.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| StarlightDigital | StarlightDigitalDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| StreamCloud | StreamCloudDownloader | http://streamcloud.eu | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| StreamYard | StreamYardDownloader | https://streamyard.com, https://oa-api.streamyard.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| STVPlayer | STVPlayerDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| SVCManifest | SVCManifestDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| SVTPlay | SVTPlayDownloader | https://www.svtplay.se | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| SWFObject | SWFObjectDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| SydneyMorningHerald | SydneyMorningHeraldDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Taobao | TaobaoDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| TEDEd | TEDEdDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| TeleZueri | TeleZueriDownloader | http://www.telezueri.ch, https://www.telezueri.ch | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Tenor | TenorDownloader | https://tenor.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Tenplay | TenplayDownloader | http://tenplay.com.au | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| TF1Base | TF1BaseDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| TheGay | TheGayDownloader | https://thegay.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| ThePlatformBase | ThePlatformBaseDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| ThePlatformEmbedded | ThePlatformEmbeddedDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| TheSpruce | TheSpruceDownloader | https://www.thespruce.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| TheTimesUK | TheTimesUKDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| TheVerge | TheVergeDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| ThisAV | ThisAVDownloader | http://www.thisav.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| ThreeNow | ThreeNowDownloader | https://www.threenow.co.nz | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Tidal | TidalDownloader | http://tidal.com, https://tidal.com, https://api.tidal.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| TouTV | TouTVDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| TrailersApple | TrailersAppleDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| TubePornClassic | TubePornClassicDownloader | https://tubepornclassic.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Tucao | TucaoDownloader | http://api.tucao.tv, http://www.tucao.tv | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Tudou | TudouDownloader | http://v2.tudou.com, http://www.tudou.com, http://js.tudouui.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| TudouNewPlay | TudouNewPlayDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Tukif | TukifDownloader | http://videos.tukif.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| TumblrVideo | TumblrVideoDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Tuto | TutoDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Tutsplus | TutsplusDownloader | https://tutsplus.com, https://courses.tutsplus.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| TV2Lorry | TV2LorryDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| TV4Play | TV4PlayDownloader | https://www.tv4play.se | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| TVCBook | TVCBookDownloader | http://api.tvcbook.com, http://www.tvcbook.com, https://www.tvcbook.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| TVCF | TVCFDownloader | https://play.tvcf.co.kr | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| TVMidtvest | TVMidtvestDownloader | http://www.tvmidtvest.dk | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| TVRain | TVRainDownloader | http://tvrain.ru, https://tvrainru.media.eagleplatform.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| TwitchBase | TwitchBaseDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| TwitchClip | TwitchClipDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| TwitchClip2 | TwitchClip2Downloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| TwitchLive | TwitchLiveDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| UKTVPlay | UKTVPlayDownloader | https://uktvplay.co.uk, http://uktvplay.uktv.co.uk, https://uktvplay.uktv.co.uk | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Ultimedia | UltimediaDownloader | http://www.ultimedia.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Univision | UnivisionDownloader | https://www.univision.com, https://usprauth.univision.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Upornia | UporniaDownloader | http://upornia.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| UsersCloud | UsersCloudDownloader | https://userscloud.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| VGTRK | VGTRKDownloader | http://player.vgtrk.com, https://player.vgtrk.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| VideaKid | VideaKidDownloader | http://videakid.hu, https://videakid.hu | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| VideoHive | VideoHiveDownloader | http://videohive.net | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| VideoLecturesNet | VideoLecturesNetDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| VideoMegaTV | VideoMegaTVDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| VideoStreamingSolutions | VideoStreamingSolutionsDownloader | https://videostreamingsolutions.net | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| VideoWeed | VideoWeedDownloader | http://www.videoweed.es, http://embed.videoweed.es | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Vidoza | VidozaDownloader | https://vidoza.net | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Vidto | VidtoDownloader | http://vidto.me | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Vidzi | VidziDownloader | http://vidzi.tv | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| VimeoEmbedded | VimeoEmbeddedDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| VimeoEvent | VimeoEventDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| VimeoOnDemand | VimeoOnDemandDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| VimeoPro | VimeoProDownloader | https://vimeopro.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| VivaTube | VivaTubeDownloader | http://vivatube.com, http://m.vivatube.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| VJAV | VJAVDownloader | https://vjav.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Vogue | VogueDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| VoyeurHit | VoyeurHitDownloader | https://voyeurhit.tube | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Vporn | VpornDownloader | http://www.vporn.com, https://www.vporn.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| VRTNews | VRTNewsDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| VXXX | VXXXDownloader | https://vxxx.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Vzan | VzanDownloader | https://wx.vzan.com, https://live-play.vzan.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| VzanPage | VzanPageDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Wasu | WasuDownloader | http://s.wasu.cn, http://www.wasu.cn | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Wav | WavDownloader | http://wav.tv, https://www.wavve.com, https://apis.wavve.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| WebCookingClasses | WebCookingClassesDownloader | http://www.webcookingclasses.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Webinar | WebinarDownloader | https://events.webinar.ru | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| WebMD | WebMDDownloader | http://www.webmd.com, https://www.webmd.com, https://webmd-vh.akamaihd.net | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| WeiboLiveShow | WeiboLiveShowDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| WeiboShow | WeiboShowDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| WeiboTVVideo | WeiboTVVideoDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Welt | WeltDownloader | http://www.welt.de, https://www.welt.de | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| WeTransfer | WeTransferDownloader | https://wetransfer.com, https://billykyle.wetransfer.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Wimp | WimpDownloader | http://www.wimp.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Wired | WiredDownloader | http://www.wired.com, https://www.wired.com, https://tdb.wiredrive.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Wiredrive | WiredriveDownloader | https://tdb.wiredrive.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| WireWax | WireWaxDownloader | http://embed.wirewax.com, https://embed.wirewax.com, http://edge-vids.wirewax.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| XBroadcast | XBroadcastDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| XHamsterLive | XHamsterLiveDownloader | https://xhamsterlive.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Xiaoying | XiaoyingDownloader | http://xiaoying.tv, http://w.api.xiaoying.co | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| XSpaces | XSpacesDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| XStatus | XStatusDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| XTube | XTubeDownloader | https://www.xtube.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Xuexi | XuexiDownloader | https://article.xuexi.cn | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| XVideosEmbed | XVideosEmbedDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| XVideoStatus | XVideoStatusDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| YahooConfiguration | YahooConfigurationDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| YahooScreen | YahooScreenDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| YahooScreenLive | YahooScreenLiveDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Yiche | YicheDownloader | https://vc.yiche.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Yiihuu | YiihuuDownloader | https://www.yiihuu.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Yinyuetai | YinyuetaiDownloader | http://v.yinyuetai.com, http://www.yinyuetai.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| YogaEasy | YogaEasyDownloader | http://www.yogaeasy.de, https://www.yogaeasy.de | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| YouAV | YouAVDownloader | https://www.youav.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| YoukuCOOP | YoukuCOOPDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| YoukuEmbedded | YoukuEmbeddedDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| YouMaker | YouMakerDownloader | https://youmaker.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| YourUpload | YourUploadDownloader | https://www.yourupload.com, http://embed.yourupload.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| YouTu_Be | YouTu_BeDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| YouTubeClip | YouTubeClipDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| YouTubeConfiguration | YouTubeConfigurationDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| YouTubeGoogleAPIs | YouTubeGoogleAPIsDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| YouTubeNoCookie | YouTubeNoCookieDownloader |  | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Zee5 | Zee5Downloader | https://www.zee5.com | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| Zhibo | ZhiboDownloader | http://video.zhibo.tv | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| ZXX | ZXXDownloader | https://www.zxx.edu.cn | 通用资源检测（未复刻） | 否 | P1 | 未原生复刻，需通用资源检测/自定义集成验证 |
| BrightcoveConcrete | BrightcoveConcreteDownloader |  | 通用资源检测（未复刻） | 否 | P2 | generic/base；未原生复刻，需通用资源检测/自定义集成验证 |
| BrightcoveEdge | BrightcoveEdgeDownloader |  | 通用资源检测（未复刻） | 否 | P2 | generic/base；未原生复刻，需通用资源检测/自定义集成验证 |
| BrightcoveEdgeEmbedded | BrightcoveEdgeEmbeddedDownloader |  | 通用资源检测（未复刻） | 否 | P2 | generic/base；未原生复刻，需通用资源检测/自定义集成验证 |
| BrightcoveEdgePage | BrightcoveEdgePageDownloader |  | 通用资源检测（未复刻） | 否 | P2 | generic/base；未原生复刻，需通用资源检测/自定义集成验证 |
| CWNetwork | CWNetworkDownloader |  | 通用资源检测（未复刻） | 否 | P2 | generic/base；未原生复刻，需通用资源检测/自定义集成验证 |
| DownloaderWithConfirmationForm | DownloaderWithConfirmationFormDownloader |  | 通用资源检测（未复刻） | 否 | P2 | generic/base；未原生复刻，需通用资源检测/自定义集成验证 |
| FranceTVBase | FranceTVBaseDownloader |  | 通用资源检测（未复刻） | 否 | P2 | generic/base；未原生复刻，需通用资源检测/自定义集成验证 |
| HTTPDirect | HTTPDirectDownloader |  | 通用资源检测（未复刻） | 否 | P2 | generic/base；未原生复刻，需通用资源检测/自定义集成验证 |
| IPForwarding | IPForwardingDownloader |  | 通用资源检测（未复刻） | 否 | P2 | generic/base；未原生复刻，需通用资源检测/自定义集成验证 |
| LimelightNetworks | LimelightNetworksDownloader |  | 通用资源检测（未复刻） | 否 | P2 | generic/base；未原生复刻，需通用资源检测/自定义集成验证 |

## DRM（不支持）

| 站点 | Downie 类 | 域名 | 状态 | 已验证 | 优先级 | 备注 |
|---|---|---|---|---|---|---|
| Disney | DisneyDownloader | http://video.disney.com, http://watchdisneyxd.go.com | DRM（不支持） | 否 | P0 | DRM host: Downie refuses |
| Apple | AppleDownloader | http://www.apple.com, https://tv.apple.com, http://trailers.apple.com | DRM（不支持） | 否 | P1 | DRM host: Downie refuses |
| AppleTVClip | AppleTVClipDownloader |  | DRM（不支持） | 否 | P1 | DRM 正片不支持 |
| DisneyBase | DisneyBaseDownloader |  | DRM（不支持） | 否 | P1 | DRM 正片不支持 |
| DisneyChannel | DisneyChannelDownloader |  | DRM（不支持） | 否 | P1 | DRM 正片不支持 |
| WatchDisneyXD | WatchDisneyXDDownloader | http://watchdisneyxd.go.com | DRM（不支持） | 否 | P1 | DRM 正片不支持 |

## 说明

- 786 个类是 Downie 的下载器/变体数量，不完全等于 786 个独立站点；其中有基类、直播/音频/番剧等变体。
- `yt-dlp` 覆盖来自 Downie 矩阵的启发式标注 + 当前 yt-dlp 提取器名/域名匹配，实际能否下载必须以样本链接测试为准。
- 通用资源检测是兜底，不是逐站复刻；失败率需要按站点记录后再决定是否写原生插件。
