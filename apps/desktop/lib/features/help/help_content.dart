import '../../shared/branding/app_brand.dart';

/// 帮助主题。
class HelpTopic {
  final String title;
  final String summary;
  final List<String> paragraphs;

  const HelpTopic({
    required this.title,
    required this.summary,
    required this.paragraphs,
  });
}

/// 帮助内容为自有文案，布局参考常见下载器帮助窗口。
final List<HelpTopic> kHelpTopics = [
  const HelpTopic(
    title: '快速开始',
    summary: '第一次使用？从这里开始。',
    paragraphs: [
      '1. 点击主窗口底部左侧的 +，粘贴视频链接。\n'
          '2. 解析完成后选择画质/后处理，点击「添加下载」。\n'
          '3. 任务会直接出现在主窗口队列里。',
      '抖音、B 站等站点使用内置站点插件；其他站点默认走 yt-dlp。'
          '需要登录的站点会自动弹出内置登录窗口，登录后 cookie 保存在本地。',
      '如果某个站点解析失败，可以打开「用户自定义视频提取」，'
          '在打开的页面里播放视频，再选择捕获到的媒体地址。',
    ],
  ),
  const HelpTopic(
    title: '下载选项',
    summary: '画质、字幕、封面和音频。',
    paragraphs: [
      '解析完成后可以选择视频画质、MP4/MP3 等格式。'
          '下载选项里可以勾选「同时下载字幕」和「同时下载封面」。',
      'B 站、抖音等站点使用原生站点插件；YouTube、Instagram、TikTok、X 等'
          '目前主要走 yt-dlp，登录后成功率更高。',
    ],
  ),
  const HelpTopic(
    title: '选择画质',
    summary: '如何选择 1080P、4K 或纯音频。',
    paragraphs: [
      '解析结果会列出当前可用的画质。B 站高画质通常需要登录，'
          '部分番剧需要大会员。',
      '如果没有看到 4K，先确认站点本身提供 4K、账号有权限，'
          '并在站点登录窗口完成登录后重新解析。',
    ],
  ),
  const HelpTopic(
    title: '设置',
    summary: '下载目录、并发数、主题和更新。',
    paragraphs: [
      '在「设置」里可以修改下载目录、并行下载数、是否下载完成后自动打开文件夹、'
          '主题模式和开机自启动。',
      '「关于」里可以查看版本、yt-dlp 版本并手动检查更新。'
          '应用自身的新版本会在启动时自动检查。',
    ],
  ),
  const HelpTopic(
    title: '浏览器扩展',
    summary: '浏览器里看到视频，怎么交给应用。',
    paragraphs: [
      '当前版本可以先复制浏览器地址，回到应用粘贴解析；'
          '或者使用「用户自定义视频提取」打开页面并捕获媒体地址。',
      '浏览器扩展和本地 HTTP 服务在规划中，后续会支持从 Chrome/Edge/Safari'
          '直接把当前页面发送到 Downie6。',
    ],
  ),
  const HelpTopic(
    title: '后处理',
    summary: '合并、转码和自定义后处理。',
    paragraphs: [
      'HLS/DASH 等分离音视频流下载完成后会自动用 ffmpeg 合并为 MP4。'
          '纯音频可以选择 MP3。',
      '自定义 ffmpeg 后处理脚本会在后续版本提供。',
    ],
  ),
  const HelpTopic(
    title: '历史记录',
    summary: '查看和清理已完成的下载。',
    paragraphs: [
      '「历史记录」保存已完成的下载任务，数据保存在本地 SQLite。'
          '可以打开文件所在目录，也可以从历史中删除单条记录或清空全部。',
      '清空历史不会删除已经下载到磁盘的文件。',
    ],
  ),
  const HelpTopic(
    title: '音频语言',
    summary: '音轨和音频格式。',
    paragraphs: [
      '支持的站点可以在解析结果里选择纯音频格式（MP3）。'
          '多音轨/多语言的站点会在后续版本暴露音轨选择。',
    ],
  ),
  const HelpTopic(
    title: '需要登录的站点',
    summary: '需要登录的站点怎么处理。',
    paragraphs: [
      '遇到需要登录的站点，解析或下载失败时会弹出内置登录窗口。'
          '登录成功后 cookie 会按站点保存在本地，后续解析/下载自动使用。',
      '如果登录后仍然失败，先在站点的设置里确认账号有权限，'
          '再尝试重新登录或更新 yt-dlp。',
    ],
  ),
  const HelpTopic(
    title: '字幕',
    summary: '字幕下载和格式。',
    paragraphs: [
      '下载时可以勾选「同时下载字幕」。支持 WebVTT、SRT、DFXP、'
          'SMPTE-TT 等常见格式，具体取决于站点提供什么。',
    ],
  ),
  const HelpTopic(
    title: '用户自定义视频提取',
    summary: '用户自定义视频提取：抓取页面里的媒体地址。',
    paragraphs: [
      '1. 点主窗口底部左侧的提取图标，或从右上角菜单选择「用户自定义视频提取…」。\n'
          '2. 在「添加链接」浮层里粘贴页面链接，点「用户自定义视频提取」。\n'
          '3. 在内置浏览器里播放视频，窗口下方会出现捕获到的 m3u8/mpd/mp4 地址。\n'
          '4. 选中地址，点「使用此地址」，再选择下载。',
      '用户自定义视频提取是兜底能力，DRM 保护的内容（如 Netflix 正片）无法下载。',
    ],
  ),
  const HelpTopic(
    title: '故障排查',
    summary: '打不开、解析失败、没有速度。',
    paragraphs: [
      'macOS 提示「无法验证开发者」：右键应用 → 打开，或到'
          '「系统设置 → 隐私与安全性 → 安全性」点「仍要打开」。',
      'macOS 提示「已损坏」：打开终端，输入 xattr -cr （末尾有空格），'
          '把 Downie6.app 拖进终端，回车后再打开。',
      '解析失败：先尝试站点登录；仍然失败可以在设置里检查 yt-dlp 更新，'
          '或使用用户自定义视频提取。',
    ],
  ),
  const HelpTopic(
    title: '隐私政策',
    summary: '本地处理，不上传视频内容。',
    paragraphs: [
      '解析和下载在本地完成，不会上传你下载的视频内容。'
          '只有授权校验、版本检查和你主动发送的反馈会联网。',
      '站点 cookie 保存在本地应用数据目录，用于后续解析/下载。'
          '反馈和支持邮件会发送到 ${AppBrand.supportEmail}。',
    ],
  ),
  const HelpTopic(
    title: '下载过多',
    summary: '合理使用和站点条款。',
    paragraphs: [
      '请遵守目标站点的服务条款和当地版权法律，只下载你有权访问的内容。'
          '不要批量滥用或用于商业分发。',
      '应用提供 14 天全功能试用；试用结束后输入授权码继续使用。',
    ],
  ),
  const HelpTopic(
    title: '站点专项提示',
    summary: 'B 站、抖音、YouTube 等常见站点。',
    paragraphs: [
      'B 站：普通视频和番剧 ep/ss 链接走原生插件；高画质/番剧可能需要登录或大会员。',
      '抖音：使用内置 a_bogus 签名解析；如果失败，尝试重新解析或更新版本。',
      'YouTube/Instagram/TikTok/X：目前主要走 yt-dlp；遇到登录/风控时先在站点登录窗口完成登录。',
      '其他站点：先在「添加链接」浮层直接解析；失败后尝试「用户自定义视频提取」。',
    ],
  ),
  const HelpTopic(
    title: '高级',
    summary: '代理、日志和引擎更新。',
    paragraphs: [
      '内嵌 yt-dlp 和 ffmpeg，首次运行会复制到应用数据目录。'
          '设置里可以手动检查 yt-dlp 更新。',
      '日志按天保存在应用数据目录的 logs/ 下，排查问题时可以查看。'
          '代理和自定义 engine 路径会在后续版本提供。',
    ],
  ),
  HelpTopic(
    title: '许可证代码',
    summary: '激活、设备和反激活。',
    paragraphs: [
      '在「设置 → 授权」里输入激活码并绑定邮箱。授权默认支持 4 台设备，'
          '换机前可以先反激活旧设备。',
      '授权码丢失或设备数量有问题，可以发邮件到 '
          '${AppBrand.supportEmail}，附上购买邮箱和授权码前缀。',
    ],
  ),
];
