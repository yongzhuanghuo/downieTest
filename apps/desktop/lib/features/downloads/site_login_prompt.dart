import '../../core/storage/site_registry.dart';
import '../../shared/routes/navigator_key.dart';
import 'site_login_dialog.dart';

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
  // Downie 是直接弹出登录浏览器窗口，不再多一层「去登录」确认
  return SiteLoginDialog.show(ctx, site);
}
