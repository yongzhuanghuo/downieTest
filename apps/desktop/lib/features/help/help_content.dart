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
      '1. 点击主窗口底部左侧的 +，粘贴视频链接；也可以把浏览器地址直接拖进窗口。\n'
          '2. 解析完成后选择画质/后处理，点击「添加下载」。\n'
          '3. 任务会直接出现在主窗口队列里。',
      '一次可以粘贴多条链接（每行一条或混在分享文案里），应用会逐条解析并入队。'
          '勾选「展开列表」后，播放列表链接最多展开 200 个视频。'
          '下载中可以暂停/继续；等待中的任务可以调整优先级。',
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
          '偏好设置 → 字幕与音频可以设置新任务是否下载字幕、保存缩略图；'
          '等待中的任务也可以从行内操作菜单单独切换。',
      '下载行内可以切换画质（等待中）、后处理方式、字幕/缩略图，或暂停/继续。'
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
          '系统通知、主题模式、开机自启动、代理、历史保留时间和默认后处理/字幕。',
      '下载位置面板支持文件名模板（{title}/{extractor}/{id}/{date}）和按站点分文件夹。',
      '「关于」里可以查看版本、yt-dlp 版本并手动检查更新。'
          '应用自身的新版本会在启动时自动检查。',
    ],
  ),
  const HelpTopic(
    title: '自动化添加',
    summary: '从脚本、快捷指令或命令行把链接交给应用。',
    paragraphs: [
      'macOS 可以用 open -a Downie6 <链接>，也可以使用自定义协议：\n'
          'downie6://XUOpenURL?url=<编码后的链接>&postprocessing=mp4\n'
          '可选参数：title、destination（保存目录）、'
          'postprocessing=mp4/audio、action=open_in_uge。',
      'Windows 安装版会注册 downie6:// 协议；也可以直接运行 '
          'Downie6.exe "downie6://..."。自动化请求不会弹出保存位置询问，'
          '未指定 destination 时使用全局下载目录。',
      '出于安全考虑，只接受 http/https 链接；file:// 等本地路径会被忽略。',
    ],
  ),
  const HelpTopic(
    title: 'CSV / XML 导入',
    summary: '批量导入链接、标题和保存目录。',
    paragraphs: [
      'CSV 表头需要包含 url 和 title，可选 path：\n'
          'url,title,path\n'
          'https://example.com/a,示例标题,/Users/me/Videos\n\n'
          'XML 使用 <downloads> 根元素，每个 <download> 包含 '
          '<url>、<title>，可选 <path>。',
      '通过「文件 → 从文件导入…」选择 .csv/.xml，或直接把内容粘贴到添加链接面板。'
          '导入时会跳过播放列表展开，path 作为该任务的独立保存目录。',
    ],
  ),
  const HelpTopic(
    title: '浏览器扩展',
    summary: '浏览器里看到视频，怎么交给应用。',
    paragraphs: [
      '偏好设置 → 浏览器扩展里可以开启本机接收端口（127.0.0.1:8765），'
          '点「导出浏览器扩展」把内置扩展复制到磁盘，再在 Chrome/Edge 的扩展管理页'
          '「加载已解压的扩展程序」。填入面板里的 token 后，'
          '在视频页面点扩展图标即可发回应用。',
      '不用扩展也可以复制面板里的书签脚本，新建浏览器书签使用。'
          '端口只监听本机，并用随机 token 鉴权；关闭开关即可停用。'
          '如果端口被占用，应用会在日志里提示，书签不会生效。'
          '也可以继续用复制链接粘贴或「用户自定义视频提取」。',
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
      '偏好设置 → 历史记录可以设置保留 7/30/90/365 天或永久；'
          '过期记录在下次启动时清理。清空历史不会删除已经下载到磁盘的文件。',
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
      '在偏好设置 → 字幕与音频里开启「下载字幕（如果可用）」，'
          '支持 WebVTT、SRT、DFXP、SMPTE-TT 等常见格式，具体取决于站点提供什么。',
      '等待中的任务可以在行内操作菜单单独切换是否下载字幕或保存缩略图；'
          '字幕语言可以填 zh,en，留空时下载站点提供的全部字幕。',
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
          '偏好设置 → 家长控制与隐私可以一键清除站点登录数据或下载历史。'
          '反馈和支持报告会通过服务器发送到 ${AppBrand.supportEmail}。',
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
    title: '站点覆盖',
    summary: '哪些站点能下，哪些还需要验证。',
    paragraphs: [
      '设置 → 支持站点里列出了 Downie 的 786 个下载器/站点变体，'
          '并标注为「原生插件」「yt-dlp」「通用资源检测（未复刻）」或「DRM」。'
          '可以按站点名、域名或 yt-dlp 提取器搜索，也可以按状态筛选。',
      '「原生插件」是我们自己实现的站点（当前是抖音和 B 站）；'
          '「yt-dlp」表示功能由 yt-dlp 负责，能下载但还没有逐站验证；'
          '「通用资源检测」表示没有专门实现，解析失败时会尝试用内置浏览器抓 m3u8/mpd/mp4。'
          '「DRM」是 Downie 本身也不下载的版权保护内容。',
      '站点表会随版本更新；如果某个站点失败，请在「不支持的链接」里选择'
          '「始终自动检测」，或把链接和日志发给支持邮箱。'
          '完整表格在仓库 docs/site-coverage.md。',
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
          '偏好设置 → 高级里可以手动检查 yt-dlp 更新。',
      '日志按天保存在应用数据目录的 logs/ 下，排查问题时可以查看。'
          '代理可以在偏好设置 → 代理服务器里配置，会传给 yt-dlp。',
      '偏好设置 → 浏览器扩展可以开启「读取浏览器登录状态」，'
          '让 yt-dlp 复用 Chrome/Safari/Edge/Firefox/Brave 的 cookie；'
          '默认关闭，读取失败不会影响普通下载。',
    ],
  ),
  HelpTopic(
    title: '许可证代码',
    summary: '激活、设备和反激活。',
    paragraphs: [
      '在右上角菜单「显示许可证代码…」或偏好设置底部的「授权…」里'
          '输入购买邮箱和激活码。授权默认支持 4 台设备；授权窗口的「设备管理」'
          '可以查看已绑定设备并解绑旧设备，「反激活此设备」会释放当前设备名额。',
      '授权码丢失或设备数量有问题，可以发邮件到 '
          '${AppBrand.supportEmail}，附上购买邮箱和授权码前缀。',
    ],
  ),
];
