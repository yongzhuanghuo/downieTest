import 'package:flutter/material.dart';

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

  final go = await showDialog<bool>(
    context: ctx,
    builder: (c) => AlertDialog(
      title: Text('需要登录 ${site.name}'),
      content: const Text('该网站需要登录后才能访问，现在去登录吗？'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(c).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(c).pop(true),
          child: const Text('去登录'),
        ),
      ],
    ),
  );
  if (go != true) return false;

  // 重新取 context，避免跨 async 边界复用旧的 BuildContext
  final ctx2 = rootNavigatorKey.currentContext;
  if (ctx2 == null) return false;
  final messenger = ScaffoldMessenger.of(ctx2);
  final loggedIn = await SiteLoginDialog.show(ctx2, site);
  if (loggedIn) {
    messenger.showSnackBar(
      const SnackBar(content: Text('登录成功，请重试')),
    );
  }
  return loggedIn;
}
