import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/storage/settings_storage.dart';
import '../../core/version/version_check.dart';
import '../../features/downloads/add_urls_panel.dart';
import '../../features/downloads/download_provider.dart';
import '../../features/help/help_window.dart';
import '../../features/help/support_dialog.dart';
import '../../features/history/history_window.dart';
import '../../features/preferences/preferences_window.dart';
import '../routes/app_routes.dart';
import '../theme/design_tokens.dart';

/// 主窗口底部状态栏：左侧操作、中间下载计数、右侧导航/支持。
class WindowStatusBar extends ConsumerWidget {
  final String location;

  const WindowStatusBar({super.key, required this.location});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? AppTokens.statusBar : AppTokens.statusBarLight;
    final divider = dark ? AppTokens.divider : AppTokens.dividerLight;
    final text = dark ? AppTokens.textPrimary : AppTokens.textPrimaryLight;
    final secondary =
        dark ? AppTokens.textSecondary : AppTokens.textSecondaryLight;

    final tasks = ref.watch(downloadListProvider);
    final hasFinished = tasks.any((t) => t.isFinished);
    final countLabel = tasks.isEmpty
        ? '暂无下载'
        : tasks.length == 1
            ? '1 个下载'
            : '${tasks.length} 个下载';

    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: background,
        border: Border(top: BorderSide(color: divider)),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.center,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => context.go(AppRoutes.downloads),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 80),
                child: Text(
                  countLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.statusBar(text),
                ),
              ),
            ),
          ),
          Row(
            children: [
              const SizedBox(width: AppSpacing.xs),
              _StatusIcon(
                icon: Icons.add,
                tooltip: '添加链接',
                color: secondary,
                onTap: () => AddUrlsPanel.show(context),
              ),
              _StatusIcon(
                icon: Icons.folder_open,
                tooltip: '打开下载目录',
                color: secondary,
                onTap: _openDownloadDir,
              ),
              _StatusIcon(
                icon: Icons.cleaning_services_outlined,
                tooltip: '清空已完成',
                color: hasFinished ? secondary : secondary.withValues(alpha: 0.4),
                onTap: hasFinished
                    ? () => ref
                        .read(downloadListProvider.notifier)
                        .clearFinished()
                    : null,
              ),
              const Spacer(),
              _StatusIcon(
                icon: Icons.history,
                tooltip: '历史记录',
                color: secondary,
                onTap: () => HistoryWindow.show(context),
              ),
              _StatusIcon(
                icon: Icons.settings_outlined,
                tooltip: '设置',
                color: secondary,
                onTap: () => PreferencesWindow.show(context),
              ),
              _StatusIcon(
                icon: Icons.help_outline,
                tooltip: '帮助',
                color: secondary,
                onTap: () => HelpWindow.show(context),
              ),
              _StatusIcon(
                icon: Icons.support_agent,
                tooltip: '报告问题',
                color: secondary,
                onTap: () => SupportDialog.show(context),
              ),
              const _UpdateIcon(),
              const SizedBox(width: AppSpacing.xs),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openDownloadDir() async {
    try {
      final dir = await SettingsStorage.instance.current.resolveDownloadDir();
      await Process.run(
        Platform.isMacOS ? 'open' : 'explorer',
        [dir],
      );
    } catch (e) {
      debugPrint('[状态栏] 打开下载目录失败: $e');
    }
  }
}

class _StatusIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback? onTap;

  const _StatusIcon({
    required this.icon,
    required this.tooltip,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 15),
        color: color,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 28, height: 32),
      ),
    );
  }
}

class _UpdateIcon extends ConsumerStatefulWidget {
  const _UpdateIcon();

  @override
  ConsumerState<_UpdateIcon> createState() => _UpdateIconState();
}

class _UpdateIconState extends ConsumerState<_UpdateIcon> {
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
          ..showSnackBar(const SnackBar(content: Text('当前已是最新版本')));
      }
    } catch (e) {
      debugPrint('[更新] 手动检查失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('检查更新失败，请稍后重试')));
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final secondary =
        dark ? AppTokens.textSecondary : AppTokens.textSecondaryLight;
    final hasUpdate = ref.watch(updateInfoProvider) != null;
    return Tooltip(
      message: hasUpdate ? '发现新版本' : '检查更新',
      child: IconButton(
        onPressed: _onTap,
        icon: _checking
            ? SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: secondary,
                ),
              )
            : Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(Icons.system_update_alt, size: 15, color: secondary),
                  if (hasUpdate)
                    Positioned(
                      top: -2,
                      right: -2,
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: dark ? AppTokens.error : AppTokens.errorLight,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 28, height: 32),
      ),
    );
  }
}
