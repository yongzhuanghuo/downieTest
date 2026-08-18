import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../routes/app_routes.dart';

/// 应用主框架 - 侧边栏 + 主体内容
class AppShell extends ConsumerWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navItems = ref.watch(navItemsProvider);
    final selectedIndex = ref.watch(selectedNavIndexProvider);
    final theme = Theme.of(context);

    return Scaffold(
      body: Row(
        children: [
          // 侧边导航栏
          _SideNavigationBar(
            navItems: navItems,
            selectedIndex: selectedIndex,
            onDestinationSelected: (index) {
              ref.read(selectedNavIndexProvider.notifier).state = index;
              context.go(navItems[index].route);
            },
            theme: theme,
          ),
          // 分割线
          VerticalDivider(
            width: 1,
            thickness: 1,
            color: theme.dividerColor.withValues(alpha: 0.5),
          ),
          // 主体内容
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// 侧边导航栏
class _SideNavigationBar extends StatelessWidget {
  final List<NavigationItem> navItems;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final ThemeData theme;

  const _SideNavigationBar({
    required this.navItems,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        children: [
          // Logo 区域
          _buildLogo(context),
          const Divider(height: 1),
          // 导航项
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (int i = 0; i < navItems.length; i++)
                  _buildNavItem(context, navItems[i], i == selectedIndex, () => onDestinationSelected(i)),
              ],
            ),
          ),
          // 底部版本信息
          _buildVersionInfo(context),
        ],
      ),
    );
  }

  Widget _buildLogo(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Image.asset(
            'assets/logo.png',
            width: 32,
            height: 32,
          ),
          const SizedBox(width: 12),
          Text(
            '4K全能视频下载器',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context,
    NavigationItem item,
    bool isSelected,
    VoidCallback onTap,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: isSelected
            ? theme.colorScheme.primaryContainer
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(
                  isSelected ? item.selectedIcon : item.icon,
                  size: 22,
                  color: isSelected
                      ? theme.colorScheme.onPrimaryContainer
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Text(
                  item.label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isSelected
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.onSurfaceVariant,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVersionInfo(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        'v2.0.0',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}
