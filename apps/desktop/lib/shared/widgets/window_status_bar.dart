import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/version/version_check.dart';
import '../../features/downloads/add_urls_panel.dart';
import '../../features/downloads/download_provider.dart';
import '../../features/downloads/queue_search_panel.dart';
import '../../features/help/help_window.dart';
import '../../features/history/history_window.dart';
import '../../features/preferences/preferences_window.dart';
import '../routes/app_routes.dart';
import '../theme/design_tokens.dart';

/// Downie 风格底部工具栏：白色浮动胶囊 + 左侧添加/引导提取 + 中间计数 + 右侧搜索/清空/历史/帮助。
class WindowStatusBar extends ConsumerWidget {
  final String location;

  const WindowStatusBar({super.key, required this.location});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final divider = dark ? AppTokens.divider : AppTokens.dividerLight;
    final pill = dark ? AppTokens.panel : AppTokens.statusBarLight;
    final text = dark ? AppTokens.textPrimary : AppTokens.textPrimaryLight;
    final secondary =
        dark ? AppTokens.textSecondary : AppTokens.textSecondaryLight;
    final accent = dark ? AppTokens.accent : AppTokens.accentLight;

    final tasks = ref.watch(downloadListProvider);
    final hasFinished = tasks.any((t) => t.isFinished);
    final countLabel = tasks.isEmpty
        ? '没有下载'
        : tasks.length == 1
            ? '1 个下载'
            : '${tasks.length} 个下载';

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: pill,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: divider.withValues(alpha: 0.7)),
          boxShadow: dark
              ? null
              : const [
                  BoxShadow(
                    color: Color(0x12000000),
                    blurRadius: 10,
                    offset: Offset(0, 2),
                  ),
                ],
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
                  padding: const EdgeInsets.symmetric(horizontal: 150),
                  child: Text(
                    countLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: text,
                    ),
                  ),
                ),
              ),
            ),
            Row(
              children: [
                const SizedBox(width: 8),
                _StatusIcon(
                  icon: Icons.add,
                  tooltip: '添加链接',
                  color: accent,
                  onTap: () => AddUrlsPanel.show(context),
                ),
                _StatusIcon(
                  icon: Icons.block,
                  tooltip: '用户自定义视频提取',
                  color: accent,
                  onTap: () => AddUrlsPanel.show(context),
                ),
                const Spacer(),
                _StatusIcon(
                  icon: Icons.search,
                  tooltip: '搜索下载',
                  color: accent,
                  onTap: () => QueueSearchPanel.show(context),
                ),
                _StatusIcon(
                  icon: Icons.cancel_outlined,
                  tooltip: '清空已结束',
                  color: hasFinished ? accent : secondary.withValues(alpha: 0.5),
                  onTap: hasFinished
                      ? () => ref
                          .read(downloadListProvider.notifier)
                          .clearFinished()
                      : null,
                ),
                _StatusIcon(
                  icon: Icons.access_time,
                  tooltip: '历史记录',
                  color: accent,
                  onTap: () => HistoryWindow.show(context),
                ),
                _StatusIcon(
                  icon: Icons.help_outline,
                  tooltip: '帮助',
                  color: accent,
                  onTap: () => HelpWindow.show(context),
                ),
                if (Platform.isWindows) ...[
                  _StatusIcon(
                    icon: Icons.settings_outlined,
                    tooltip: '设置',
                    color: accent,
                    onTap: () => PreferencesWindow.show(context),
                  ),
                  const _UpdateIcon(),
                ],
                const SizedBox(width: 8),
              ],
            ),
          ],
        ),
      ),
    );
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
        icon: Icon(icon, size: 18),
        color: color,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 34, height: 40),
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
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: secondary,
                ),
              )
            : Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(Icons.system_update_alt, size: 18, color: secondary),
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
        constraints: const BoxConstraints.tightFor(width: 34, height: 40),
      ),
    );
  }
}
