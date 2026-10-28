import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../../shared/branding/app_brand.dart';

/// 菜单栏 / 系统托盘图标（Downie 的菜单栏 popover 入口）。
///
/// 菜单动作由 WindowShell 注入，避免核心层依赖 Riverpod / 页面。
class TrayService with TrayListener {
  TrayService._();

  static final TrayService instance = TrayService._();

  bool _listenerAdded = false;
  bool _enabled = false;

  VoidCallback? onShow;
  VoidCallback? onStartAll;
  VoidCallback? onPauseAll;
  VoidCallback? onHistory;
  VoidCallback? onSettings;
  VoidCallback? onQuit;

  Future<void> configure({
    required VoidCallback show,
    required VoidCallback startAll,
    required VoidCallback pauseAll,
    required VoidCallback history,
    required VoidCallback settings,
    required VoidCallback quit,
    required bool enabled,
  }) async {
    onShow = show;
    onStartAll = startAll;
    onPauseAll = pauseAll;
    onHistory = history;
    onSettings = settings;
    onQuit = quit;
    if (!_listenerAdded) {
      trayManager.addListener(this);
      _listenerAdded = true;
    }
    await setEnabled(enabled);
  }

  Future<void> setEnabled(bool enabled) async {
    if (enabled == _enabled) return;
    try {
      if (enabled) {
        await trayManager.setIcon(
          // Windows LoadImage 只认 ICO，PNG 会得到空 HICON（托盘不显示）
          Platform.isWindows ? 'assets/tray.ico' : 'assets/logo.png',
          iconSize: 18,
        );
        await trayManager.setToolTip(AppBrand.name);
        await _setMenu();
        _enabled = true;
      } else {
        await trayManager.destroy();
        _enabled = false;
      }
    } catch (e) {
      debugPrint('[托盘] 设置失败: $e');
    }
  }

  Future<void> _setMenu() async {
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(
        key: 'show',
        label: '显示 ${AppBrand.name}',
        onClick: (_) => onShow?.call(),
      ),
      MenuItem.separator(),
      MenuItem(
        key: 'start',
        label: '开始全部下载',
        onClick: (_) => onStartAll?.call(),
      ),
      MenuItem(
        key: 'pause',
        label: '暂停全部下载',
        onClick: (_) => onPauseAll?.call(),
      ),
      MenuItem.separator(),
      MenuItem(
        key: 'history',
        label: '历史记录…',
        onClick: (_) => onHistory?.call(),
      ),
      MenuItem(
        key: 'settings',
        label: '设置…',
        onClick: (_) => onSettings?.call(),
      ),
      MenuItem.separator(),
      MenuItem(
        key: 'quit',
        label: '退出 ${AppBrand.name}',
        onClick: (_) => onQuit?.call(),
      ),
    ]));
  }

  @override
  void onTrayIconMouseDown() {
    onShow?.call();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    // onClick 已经处理；保留回调以兼容不同平台。
  }
}

/// 显示并聚焦主窗口。
Future<void> showMainWindow() async {
  try {
    await windowManager.show();
    await windowManager.focus();
  } catch (e) {
    debugPrint('[托盘] 显示主窗口失败: $e');
  }
}
