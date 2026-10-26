import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/version/version_check.dart';
import '../../features/downloads/add_urls_panel.dart';
import '../../features/downloads/queue_search_panel.dart';
import '../../features/history/history_window.dart';
import '../../features/license/license_provider.dart';
import '../../features/preferences/preferences_window.dart';
import 'window_status_bar.dart';
import 'window_title_bar.dart';

/// 主窗口壳层：标题栏 + 内容 + 底部状态栏。
///
/// 不再使用侧边栏/顶部工具栏；页面通过底部状态栏和菜单切换。
class WindowShell extends ConsumerStatefulWidget {
  final String location;
  final Widget child;

  const WindowShell({
    super.key,
    required this.location,
    required this.child,
  });

  @override
  ConsumerState<WindowShell> createState() => _WindowShellState();
}

class _WindowShellState extends ConsumerState<WindowShell> {
  @override
  void initState() {
    super.initState();
    unawaited(ref.read(trialProvider.notifier).ensureStarted());
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
    final isMac = Platform.isMacOS;
    return CallbackShortcuts(
      bindings: {
        SingleActivator(
          LogicalKeyboardKey.keyO,
          meta: isMac,
          control: !isMac,
        ): () => AddUrlsPanel.show(context),
        SingleActivator(
          LogicalKeyboardKey.comma,
          meta: isMac,
          control: !isMac,
        ): () => PreferencesWindow.show(context),
        SingleActivator(
          LogicalKeyboardKey.keyH,
          meta: isMac,
          control: !isMac,
          shift: true,
        ): () => HistoryWindow.show(context),
        SingleActivator(
          LogicalKeyboardKey.keyF,
          meta: isMac,
          control: !isMac,
        ): () => QueueSearchPanel.show(context),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          body: Column(
            children: [
              const WindowTitleBar(),
              Expanded(child: widget.child),
              WindowStatusBar(location: widget.location),
            ],
          ),
        ),
      ),
    );
  }
}
