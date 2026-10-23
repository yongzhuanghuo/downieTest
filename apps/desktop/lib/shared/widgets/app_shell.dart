import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/version/version_check.dart';
import '../../features/help/help_window.dart';
import '../../features/help/support_dialog.dart';
import '../branding/app_brand.dart';
import '../routes/app_routes.dart';

/// 应用主框架 - 侧边栏 + 顶部工具栏 + 内容区。
///
/// 页面结构参考桌面下载器的常见布局；品牌、图标和文案使用自有资产。
class AppShell extends ConsumerStatefulWidget {
  final String location;
  final Widget child;

  const AppShell({
    super.key,
    required this.location,
    required this.child,
  });

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
    final theme = Theme.of(context);
    return Scaffold(
      body: Row(
        children: [
          _Sidebar(location: widget.location, theme: theme),
          VerticalDivider(
            width: 1,
            color: theme.dividerColor.withValues(alpha: 0.35),
          ),
          Expanded(
            child: Column(
              children: [
                _Toolbar(theme: theme),
                Expanded(child: widget.child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final String location;
  final ThemeData theme;

  const _Sidebar({required this.location, required this.theme});

  @override
  Widget build(BuildContext context) {
    final width = Platform.isMacOS ? 244.0 : 224.0;
    return Container(
      width: width,
      color: theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.6),
      child: Column(
        children: [
          _buildBrand(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
              children: [
                _section('资料库'),
                _nav(context, '新建下载', Icons.add_circle_outline,
                    AppRoutes.home),
                _nav(context, '下载队列', Icons.download_outlined,
                    AppRoutes.downloads),
                _nav(context, '历史记录', Icons.history, AppRoutes.history),
                _section('工具'),
                _action(context, '网页嗅探', Icons.travel_explore, () {
                  context.go(AppRoutes.home);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('在首页粘贴链接后点击「网页嗅探」'),
                    ),
                  );
                }),
                _section('设置'),
                _nav(context, '设置', Icons.settings_outlined,
                    AppRoutes.settings),
                _section('支持'),
                _action(context, '帮助', Icons.help_outline,
                    () => HelpWindow.show(context)),
                _action(context, '报告问题', Icons.support_agent,
                    () => SupportDialog.show(context)),
              ],
            ),
          ),
          _buildBottom(),
        ],
      ),
    );
  }

  Widget _buildBrand() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset(
              AppBrand.logoAsset,
              width: 36,
              height: 36,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppBrand.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  AppBrand.tagline,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _nav(
    BuildContext context,
    String label,
    IconData icon,
    String route,
  ) {
    final selected = location == route;
    return _item(
      context: context,
      label: label,
      icon: icon,
      selected: selected,
      onTap: () => context.go(route),
    );
  }

  Widget _action(
    BuildContext context,
    String label,
    IconData icon,
    VoidCallback onTap,
  ) {
    return _item(
      context: context,
      label: label,
      icon: icon,
      selected: false,
      onTap: onTap,
    );
  }

  Widget _item({
    required BuildContext context,
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: selected
            ? theme.colorScheme.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: selected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottom() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        children: [
          const _UpdateButton(),
          const SizedBox(width: 6),
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snap) => Text(
              'v${snap.data?.version ?? ''}',
              style: theme.textTheme.bodySmall?.copyWith(
                color:
                    theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.65),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  final ThemeData theme;

  const _Toolbar({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.35),
          ),
        ),
      ),
      child: Row(
        children: [
          FilledButton.icon(
            onPressed: () => context.go(AppRoutes.home),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('添加链接'),
          ),
          const SizedBox(width: 12),
          if (Platform.isWindows)
            Text(
              AppBrand.name,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          const Spacer(),
          IconButton(
            tooltip: '帮助',
            icon: const Icon(Icons.help_outline),
            onPressed: () => HelpWindow.show(context),
          ),
          IconButton(
            tooltip: '报告问题',
            icon: const Icon(Icons.support_agent),
            onPressed: () => SupportDialog.show(context),
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
    final iconColor =
        theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6);
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
