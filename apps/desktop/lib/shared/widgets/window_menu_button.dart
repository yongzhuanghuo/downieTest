import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/version/version_check.dart';
import '../../features/downloads/add_urls_panel.dart';
import '../../features/downloads/download_provider.dart';
import '../../features/help/help_window.dart';
import '../../features/help/support_dialog.dart';
import '../../features/history/history_window.dart';
import '../../features/license/license_card.dart';
import '../../features/preferences/preferences_window.dart';
import '../branding/app_brand.dart';
import '../theme/design_tokens.dart';

/// 标题栏右上角的 Downie 式应用菜单。
class WindowMenuButton extends ConsumerStatefulWidget {
  const WindowMenuButton({super.key});

  @override
  ConsumerState<WindowMenuButton> createState() => _WindowMenuButtonState();
}

class _WindowMenuButtonState extends ConsumerState<WindowMenuButton> {
  final _controller = MenuController();

  String get _cmd => Platform.isMacOS ? '⌘' : 'Ctrl+';
  String _shortcut(String key, {bool shift = false}) =>
      Platform.isMacOS ? '⌘${shift ? '⇧' : ''}$key' : 'Ctrl+${shift ? 'Shift+' : ''}$key';

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final panel = dark ? AppTokens.panel : AppTokens.panelLight;
    final divider = dark ? AppTokens.divider : AppTokens.dividerLight;
    final text = dark ? AppTokens.textPrimary : AppTokens.textPrimaryLight;
    final secondary = dark ? AppTokens.textSecondary : AppTokens.textSecondaryLight;

    return MenuAnchor(
      controller: _controller,
      alignmentOffset: const Offset(-220, 6),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(panel),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(10),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: AppSpacing.xs),
        ),
        minimumSize: const WidgetStatePropertyAll(Size(250, 0)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.panel),
            side: BorderSide(color: divider),
          ),
        ),
      ),
      menuChildren: [
        _item(
          '从粘贴板添加…',
          icon: Icons.content_paste,
          shortcut: _shortcut('V'),
          onTap: _addFromClipboard,
        ),
        _item(
          '从文件导入…',
          icon: Icons.file_open_outlined,
          shortcut: _cmd + 'O',
          onTap: () => _hint('从文件导入将在后续版本接入'),
        ),
        SubmenuButton(
          leadingIcon: const Icon(Icons.list_alt, size: 14),
          menuChildren: [
            _item(
              '清空已完成',
              icon: Icons.cleaning_services_outlined,
              onTap: () => ref
                  .read(downloadListProvider.notifier)
                  .clearFinished(),
            ),
          ],
          child: Text('队列', style: TextStyle(fontSize: 12, color: text)),
        ),
        const Divider(height: 8),
        _item(
          '用户自定义视频提取…',
          icon: Icons.travel_explore,
          shortcut: _shortcut('E'),
          onTap: () => AddUrlsPanel.show(context),
        ),
        _item(
          '打开登录浏览器…',
          icon: Icons.login,
          shortcut: _shortcut('L'),
          onTap: () => _hint('请在添加链接后按站点提示登录'),
        ),
        _item(
          '设置…',
          icon: Icons.settings_outlined,
          shortcut: _shortcut(','),
          onTap: () => PreferencesWindow.show(context),
        ),
        _item(
          '显示历史记录',
          icon: Icons.access_time,
          shortcut: _shortcut('H', shift: true),
          onTap: () => HistoryWindow.show(context),
        ),
        const Divider(height: 8),
        _item('关于 ${AppBrand.name}', icon: Icons.info_outline, onTap: _about),
        _item(
          '显示许可证代码…',
          icon: Icons.key_outlined,
          onTap: () => showProUpgradeDialog(context, ref),
        ),
        _item(
          '停用用户许可证',
          icon: Icons.key_off_outlined,
          onTap: () => showProUpgradeDialog(context, ref),
        ),
        const Divider(height: 8),
        _item(
          '检查更新…',
          icon: Icons.system_update_alt,
          onTap: _checkUpdate,
        ),
        _item(
          '版本说明',
          icon: Icons.description_outlined,
          onTap: () => HelpWindow.show(context),
        ),
        _item(
          '联系支持',
          icon: Icons.support_agent,
          onTap: () => SupportDialog.show(context),
        ),
        const Divider(height: 8),
        _item(
          '调试',
          icon: Icons.bug_report_outlined,
          onTap: () => _hint('调试面板将在后续版本接入'),
        ),
        _item(
          '${AppBrand.name} 帮助',
          icon: Icons.help_outline,
          onTap: () => HelpWindow.show(context),
        ),
        const Divider(height: 8),
        _item(
          '退出 ${AppBrand.name}',
          icon: Icons.power_settings_new,
          shortcut: _shortcut('Q'),
          onTap: () => windowManager.close(),
        ),
      ],
      builder: (context, controller, child) {
        return IconButton(
          onPressed: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
          tooltip: '菜单',
          icon: Icon(Icons.more_horiz, size: 17, color: secondary),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 28, height: 28),
        );
      },
    );
  }

  Widget _item(
    String label, {
    IconData? icon,
    String? shortcut,
    VoidCallback? onTap,
  }) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final text = dark ? AppTokens.textPrimary : AppTokens.textPrimaryLight;
    final secondary = dark ? AppTokens.textSecondary : AppTokens.textSecondaryLight;
    return MenuItemButton(
      onPressed: onTap == null
          ? null
          : () {
              _controller.close();
              onTap();
            },
      leadingIcon: icon == null ? null : Icon(icon, size: 14),
      trailingIcon: shortcut == null
          ? null
          : Text(
              shortcut,
              style: TextStyle(fontSize: 11, color: secondary),
            ),
      child: Text(label, style: TextStyle(fontSize: 12, color: text)),
    );
  }

  Future<void> _addFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    if (!mounted) return;
    await AddUrlsPanel.show(context, initialText: data?.text);
  }

  Future<void> _checkUpdate() async {
    try {
      final found = await refreshUpdateState(ref);
      if (!mounted) return;
      if (found) {
        await showUpdateDialog(ref.read(updateInfoProvider)!);
      } else {
        _hint('当前已是最新版本');
      }
    } catch (e) {
      debugPrint('[更新] 菜单检查失败: $e');
      _hint('检查更新失败，请稍后重试');
    }
  }

  Future<void> _about() async {
    final theme = Theme.of(context);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppBrand.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppBrand.tagline, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            Text(
              '支持邮箱：${AppBrand.supportEmail}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(
              '解析和下载在本地完成；只有授权校验、版本检查和主动发送的反馈会联网。',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('好'),
          ),
        ],
      ),
    );
  }

  void _hint(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
