import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

/// 多级窗口像（UGE → 帮助）共享同一个主窗口时，
/// 只让最上层页面响应关闭，并统一管理 preventClose。
class WindowCloseCoordinator with WindowListener {
  WindowCloseCoordinator._();

  static final WindowCloseCoordinator instance = WindowCloseCoordinator._();

  final List<_CloseEntry> _entries = <_CloseEntry>[];
  bool _listening = false;

  void push(Object owner, VoidCallback handler) {
    if (!_listening) {
      windowManager.addListener(this);
      _listening = true;
    }
    _entries.removeWhere((e) => identical(e.owner, owner));
    _entries.add(_CloseEntry(owner, handler));
    windowManager.setPreventClose(true);
  }

  void pop(Object owner) {
    _entries.removeWhere((e) => identical(e.owner, owner));
    if (_entries.isEmpty) {
      windowManager.setPreventClose(false);
    }
  }

  @override
  void onWindowClose() {
    if (_entries.isNotEmpty) {
      _entries.last.handler();
    }
  }
}

class _CloseEntry {
  final Object owner;
  final VoidCallback handler;
  const _CloseEntry(this.owner, this.handler);
}
