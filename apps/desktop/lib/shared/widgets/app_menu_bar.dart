import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../features/downloads/add_urls_panel.dart';
import '../../features/downloads/download_provider.dart';
import '../../features/downloads/quick_add.dart';
import '../../features/help/help_window.dart';
import '../../features/help/support_dialog.dart';
import '../../features/history/history_window.dart';
import '../../features/license/license_window.dart';
import '../../features/preferences/preferences_window.dart';
import '../../core/version/version_check.dart';
import '../branding/app_brand.dart';
import '../routes/navigator_key.dart';

/// macOS 原生菜单栏（Downie 的 File/Edit/Window/Help 菜单）。
///
/// Windows 不包这层：Windows 使用标题栏菜单 + 托盘菜单。
class AppMenuBar extends ConsumerWidget {
  final Widget child;

  const AppMenuBar({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!Platform.isMacOS) return child;
    return PlatformMenuBar(
      menus: _menus(ref),
      child: child,
    );
  }

  BuildContext? get _ctx => rootNavigatorKey.currentContext;

  List<PlatformMenuItem> _menus(WidgetRef ref) {
    return [
      PlatformMenu(
        label: AppBrand.name,
        menus: [
          const PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.about,
          ),
          PlatformMenuItem(
            label: '设置…',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.comma,
              meta: true,
            ),
            onSelected: _openPreferences,
          ),
          PlatformMenuItem(
            label: '许可证…',
            onSelected: _openLicense,
          ),
          PlatformMenuItem(
            label: '检查更新…',
            onSelected: () => _checkUpdate(ref),
          ),
          const PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.hide,
          ),
          const PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.hideOtherApplications,
          ),
          const PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.showAllApplications,
          ),
          const PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.quit,
          ),
        ],
      ),
      PlatformMenu(
        label: '文件',
        menus: [
          PlatformMenuItem(
            label: '打开链接…',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyO,
              meta: true,
            ),
            onSelected: _openUrls,
          ),
          PlatformMenuItem(
            label: '从粘贴板添加',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyV,
              meta: true,
              shift: true,
            ),
            onSelected: () => _addFromClipboard(ref),
          ),
          PlatformMenuItem(
            label: '从文件导入…',
            onSelected: () => _importFromFile(ref),
          ),
          PlatformMenuItem(
            label: '清空已完成',
            onSelected: () => ref
                .read(downloadListProvider.notifier)
                .clearFinished(),
          ),
          PlatformMenuItem(
            label: '关闭窗口',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyW,
              meta: true,
            ),
            onSelected: () => windowManager.close(),
          ),
        ],
      ),
      PlatformMenu(
        label: '窗口',
        menus: [
          PlatformMenuItem(
            label: '显示主窗口',
            onSelected: () async {
              await windowManager.show();
              await windowManager.focus();
            },
          ),
          PlatformMenuItem(
            label: '历史记录',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyH,
              meta: true,
              shift: true,
            ),
            onSelected: () {
              final ctx = _ctx;
              if (ctx != null) HistoryWindow.show(ctx);
            },
          ),
          const PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.minimizeWindow,
          ),
          const PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.zoomWindow,
          ),
          const PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.arrangeWindowsInFront,
          ),
        ],
      ),
      PlatformMenu(
        label: '帮助',
        menus: [
          PlatformMenuItem(
            label: '${AppBrand.name} 帮助',
            onSelected: () {
              final ctx = _ctx;
              if (ctx != null) HelpWindow.show(ctx);
            },
          ),
          PlatformMenuItem(
            label: '报告问题…',
            onSelected: () {
              final ctx = _ctx;
              if (ctx != null) SupportDialog.show(ctx);
            },
          ),
        ],
      ),
    ];
  }

  void _openPreferences() {
    final ctx = _ctx;
    if (ctx != null) PreferencesWindow.show(ctx);
  }

  void _openLicense() {
    final ctx = _ctx;
    if (ctx != null) LicenseWindow.show(ctx);
  }

  void _openUrls() {
    final ctx = _ctx;
    if (ctx != null) AddUrlsPanel.show(ctx);
  }

  Future<void> _addFromClipboard(WidgetRef ref) async {
    final ctx = _ctx;
    if (ctx == null) return;
    await quickAddFromClipboard(ctx, ref);
  }

  Future<void> _importFromFile(WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '选择包含链接的文本文件',
      type: FileType.custom,
      allowedExtensions: const ['txt', 'text', 'csv', 'xml', 'md'],
    );
    final path = result?.files.firstOrNull?.path;
    if (path == null) return;
    final ctx = _ctx;
    if (ctx == null) return;
    try {
      final content = await File(path).readAsString();
      if (ctx.mounted) {
        await AddUrlsPanel.show(ctx, initialText: content);
      }
    } catch (e) {
      debugPrint('[菜单] 导入失败: $e');
    }
  }

  Future<void> _checkUpdate(WidgetRef ref) async {
    final ctx = _ctx;
    if (ctx == null) return;
    final found = await refreshUpdateState(ref);
    if (found && ctx.mounted) {
      await showUpdateDialog(ref.read(updateInfoProvider)!);
    }
  }
}
