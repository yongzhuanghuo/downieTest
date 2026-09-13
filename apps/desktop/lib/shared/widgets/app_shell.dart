import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/version/version_check.dart';
import '../routes/app_routes.dart';

/// 应用主框架 - 侧边栏 + 主体内容
class AppShell extends ConsumerStatefulWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  @override
  void initState() {
    super.initState();
    // 启动后延迟检查应用新版本（后台，有新版弹窗 + 侧边栏亮红点，无则静默）
    unawaited(() async {
      await Future<void>.delayed(const Duration(seconds: 3));
      if (!mounted) return;
      try {
        if (await refreshUpdateState(ref) && mounted) {
          await showUpdateDialog(ref.read(updateInfoProvider)!);
        }
      } catch (e) {
        debugPrint('[更新] 版本检查失败（静默）: $e');
      }
    }());
  }

  @override
  Widget build(BuildContext context) {
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
          Expanded(child: widget.child),
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
      child: Row(
        children: [
          const _UpdateButton(),
          const SizedBox(width: 8),
          // 版本号动态读 pubspec（package_info_plus），发版不用再手改这里
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snap) => Text(
              'v${snap.data?.version ?? ''}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 侧边栏左下角「检查更新」小图标（版本号左边）：
/// 有新版时右上角亮红点（未读消息样式），点击弹更新窗 / 重新检查。
class _UpdateButton extends ConsumerStatefulWidget {
  const _UpdateButton();

  @override
  ConsumerState<_UpdateButton> createState() => _UpdateButtonState();
}

class _UpdateButtonState extends ConsumerState<_UpdateButton> {
  bool _checking = false;

  Future<void> _onTap() async {
    // 已经知道有新版：直接弹窗，不再重复请求
    final known = ref.read(updateInfoProvider);
    if (known != null) {
      await showUpdateDialog(known);
      return;
    }
    if (_checking) return;

    setState(() => _checking = true);
    try {
      final found = await refreshUpdateState(ref);
      if (!mounted) return;
      if (found) {
        await showUpdateDialog(ref.read(updateInfoProvider)!);
      } else {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(
            content: Text('当前已是最新版本'),
            duration: Duration(seconds: 2),
          ));
      }
    } catch (e) {
      debugPrint('[更新] 手动检查失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(
            content: Text('检查更新失败，请稍后重试'),
            duration: Duration(seconds: 2),
          ));
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6);
    final hasUpdate = ref.watch(updateInfoProvider) != null;

    return Tooltip(
      message: hasUpdate ? '发现新版本，点击查看' : '检查更新',
      child: IconButton(
        onPressed: _onTap,
        iconSize: 18,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
        color: iconColor,
        icon: _checking
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: iconColor,
                ),
              )
            : Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.update),
                  // 红点 = 有新版本（未读消息样式）；描边让红点不糊进图标
                  if (hasUpdate)
                    Positioned(
                      top: -3,
                      right: -3,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.error,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: theme.colorScheme.surfaceContainerLow,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
