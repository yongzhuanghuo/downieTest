import '../../core/storage/site_registry.dart';
import '../../shared/routes/navigator_key.dart';
import 'site_login_dialog.dart';

/// 是否为 YouTube 链接。
bool isYouTubeUrl(String url) {
  final lower = url.toLowerCase();
  return lower.contains('youtube.com') || lower.contains('youtu.be');
}

/// 登录/风控失败时给用户看的提示。
///
/// YouTube 的 `Sign in to confirm you're not a bot` 不是普通站点登录，
/// 而是反爬验证；提示用户用登录浏览器或浏览器 Cookie，而不是误以为站点不支持。
String loginRequiredMessage(String url) {
  final lower = url.toLowerCase();
  if (lower.contains('tiktok.com/shortdrama/')) {
    return 'TikTok 短剧需要登录后观看：请在登录窗口登录 TikTok，再重试解析';
  }
  if (isYouTubeUrl(url)) {
    return 'YouTube 风控要求登录/验证：请用登录浏览器登录 YouTube，'
        '或在设置→浏览器扩展选择已登录 YouTube 的浏览器 Cookie';
  }
  return '该网站需要登录后才能解析';
}

/// 是否为「需要登录/cookie」类错误
bool isCookieError(String message) {
  final m = message.toLowerCase();
  const kws = [
    'cookie', 'login', 'sign in', 'sign-in', 'bot',
    'authentication', 'registered', '登录', '验证', '需要登录',
  ];
  return kws.any(m.contains);
}

/// 弹「需要登录」提示并引导登录对应站点；返回 true 表示登录成功。
/// 解析失败和下载失败都会调用。
Future<bool> promptSiteLogin(String url) async {
  final ctx = rootNavigatorKey.currentContext;
  if (ctx == null) return false;
  final site = resolveSite(url);
  // Downie 是直接弹出登录浏览器窗口，不再多一层「去登录」确认。
  // 优先打开真正需要登录的页面（如抖音视频页），而不是站点首页。
  return SiteLoginDialog.show(ctx, site, initialUrl: url);
}
