import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/downloads/downloads_page.dart';
import '../../features/history/history_page.dart';
import '../widgets/window_shell.dart';
import 'navigator_key.dart';

/// 路由名称常量
class AppRoutes {
  AppRoutes._();

  static const String home = '/';
  static const String downloads = '/downloads';
  static const String history = '/history';
  static const String settings = '/settings';
}

/// 全局路由配置 Provider
final goRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.downloads,
    routes: [
      ShellRoute(
        builder: (context, state, child) =>
            WindowShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: AppRoutes.home,
            // 旧首页已退役，主窗口就是下载队列
            redirect: (_, __) => AppRoutes.downloads,
          ),
          GoRoute(
            path: AppRoutes.downloads,
            name: 'downloads',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: DownloadsPage(),
            ),
          ),
          GoRoute(
            path: AppRoutes.history,
            name: 'history',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: HistoryPage(),
            ),
          ),
          GoRoute(
            path: AppRoutes.settings,
            // 设置改为窗口式浮层（PreferencesWindow）
            redirect: (_, __) => AppRoutes.downloads,
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text('页面不存在: ${state.error}'),
      ),
    ),
  );
});
