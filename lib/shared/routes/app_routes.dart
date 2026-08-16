import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/downloads/downloads_page.dart';
import '../../features/history/history_page.dart';
import '../../features/home/home_page.dart';
import '../../features/settings/settings_page.dart';
import '../../features/tools/watermark_tool_page.dart';
import '../widgets/app_shell.dart';

/// 路由名称常量
class AppRoutes {
  AppRoutes._();

  static const String home = '/';
  static const String downloads = '/downloads';
  static const String history = '/history';
  static const String watermark = '/watermark';
  static const String settings = '/settings';
}

/// 全局路由配置 Provider
final goRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.home,
    routes: [
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: AppRoutes.home,
            name: 'home',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: HomePage(),
            ),
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
            path: AppRoutes.watermark,
            name: 'watermark',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: WatermarkToolPage(),
            ),
          ),
          GoRoute(
            path: AppRoutes.settings,
            name: 'settings',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: SettingsPage(),
            ),
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

/// 当前选中的导航索引 Provider
final selectedNavIndexProvider = StateProvider<int>((ref) => 0);

/// 导航项配置
final navItemsProvider = Provider<List<NavigationItem>>((ref) {
  return const [
    NavigationItem(
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
      label: '首页',
      route: AppRoutes.home,
    ),
    NavigationItem(
      icon: Icons.download_outlined,
      selectedIcon: Icons.download,
      label: '下载',
      route: AppRoutes.downloads,
    ),
    NavigationItem(
      icon: Icons.cleaning_services_outlined,
      selectedIcon: Icons.cleaning_services,
      label: '去水印',
      route: AppRoutes.watermark,
    ),
    NavigationItem(
      icon: Icons.history_outlined,
      selectedIcon: Icons.history,
      label: '历史',
      route: AppRoutes.history,
    ),
    NavigationItem(
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      label: '设置',
      route: AppRoutes.settings,
    ),
  ];
});

/// 导航项数据模型
class NavigationItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final String route;

  const NavigationItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.route,
  });
}
