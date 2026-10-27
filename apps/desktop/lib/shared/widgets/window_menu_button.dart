import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/storage/site_registry.dart';
import '../../core/version/version_check.dart';
import '../../features/downloads/add_urls_panel.dart';
import '../../features/downloads/download_provider.dart';
import '../../features/downloads/quick_add.dart';
import '../../features/downloads/site_login_dialog.dart';
import '../../features/help/help_window.dart';
import '../../features/help/support_dialog.dart';
import '../../features/history/history_window.dart';
import '../../features/license/license_window.dart';
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
          onTap: _addFromClipboard,
        ),
        _item(
          '从文件导入…',
          icon: Icons.file_open_outlined,
          onTap: _importFromFile,
        ),
        SubmenuButton(
          leadingIcon: const Icon(Icons.list_alt, size: 14),
          menuChildren: [
            _item(
              '暂停全部',
              icon: Icons.pause_circle_outline,
              onTap: () =>
                  ref.read(downloadListProvider.notifier).pauseAll(),
            ),
            _item(
              '继续全部',
              icon: Icons.play_circle_outline,
              onTap: () =>
                  ref.read(downloadListProvider.notifier).resumeAll(),
            ),
            _item(
              '重试全部',
              icon: Icons.refresh,
              onTap: () =>
                  ref.read(downloadListProvider.notifier).retryAll(),
            ),
            const Divider(height: 8),
            _item(
              '清空已完成',
              icon: Icons.cleaning_services_outlined,
              onTap: () => ref
                  .read(downloadListProvider.notifier)
                  .clearFinished(),
            ),
            _item(
              '清空未激活',
              icon: Icons.remove_circle_outline,
              onTap: () => ref
                  .read(downloadListProvider.notifier)
                  .clearInactive(),
            ),
            _item(
              '重置队列…',
              icon: Icons.restart_alt,
              onTap: _resetQueue,
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
          onTap: _openLoginBrowser,
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
          onTap: () => LicenseWindow.show(context),
        ),
        _item(
          '停用用户许可证',
          icon: Icons.key_off_outlined,
          onTap: () => LicenseWindow.show(context),
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

  Future<void> _resetQueue() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重置队列'),
        content: const Text('将停止并移除队列中的所有任务，已下载的文件不会被删除。确定继续吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('重置'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await ref.read(downloadListProvider.notifier).resetQueue();
    }
  }

  Future<void> _addFromClipboard() async {
    await quickAddFromClipboard(context, ref);
  }

  Future<void> _importFromFile() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '选择包含链接的文本文件',
      type: FileType.custom,
      allowedExtensions: const ['txt', 'text', 'csv', 'md'],
    );
    final path = result?.files.firstOrNull?.path;
    if (path == null || !mounted) return;
    try {
      final content = await File(path).readAsString();
      if (!mounted) return;
      await AddUrlsPanel.show(context, initialText: content);
    } catch (e) {
      debugPrint('[导入] 读取文件失败: $e');
      _hint('读取文件失败：$e');
    }
  }

  Future<void> _openLoginBrowser() async {
    final site = await showDialog<SiteConfig>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('登录浏览器'),
        children: [
          for (final site in kLoginSites)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(site),
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(site.name),
                subtitle: Text(site.domains.join(', ')),
              ),
            ),
        ],
      ),
    );
    if (site == null || !mounted) return;
    final ok = await SiteLoginDialog.show(context, site);
    if (ok && mounted) {
      _hint('${site.name} 登录成功，cookie 已保存');
    }
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
