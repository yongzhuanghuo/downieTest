import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/server/browser_bridge.dart';
import '../../core/version/version_check.dart';
import '../../features/downloads/add_urls_panel.dart';
import '../../features/downloads/download_provider.dart';
import '../../features/downloads/queue_search_panel.dart';
import '../../features/history/history_window.dart';
import '../../features/home/home_provider.dart';
import '../../features/license/license_provider.dart';
import '../../features/preferences/preferences_window.dart';
import '../../features/settings/settings_provider.dart';
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
    unawaited(_syncBrowserBridge());
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

  /// 启动/停止浏览器接收端口；设置变化时由 ref.listen 重新调用。
  Future<void> _syncBrowserBridge() async {
    final settings = ref.read(settingsProvider);
    if (!settings.browserBridgeEnabled ||
        settings.browserBridgeToken.isEmpty) {
      await BrowserBridge.instance.stop();
      return;
    }
    final ok = await BrowserBridge.instance.start(
      token: settings.browserBridgeToken,
      onUrl: _handleBrowserUrl,
    );
    if (!ok) {
      debugPrint('[浏览器接收] 端口 ${BrowserBridge.defaultPort} 启动失败，可能被占用');
    }
  }

  Future<bool> _handleBrowserUrl(String url) async {
    try {
      await ref.read(parseProvider.notifier).parse(url);
      if (!mounted) return false;
      final parse = ref.read(parseProvider);
      final info = parse.videoInfo;
      if (parse.isError || info == null) return false;
      if (!ref.read(canDownloadProvider)) return false;
      final format = info.recommendedFormat;
      if (format == null) return false;
      final settings = ref.read(settingsProvider);
      await ref.read(downloadListProvider.notifier).startDownload(
            videoInfo: info,
            format: format,
            downloadSubtitles: settings.defaultDownloadSubtitles,
            downloadCover: settings.defaultDownloadCover,
          );
      return true;
    } catch (e) {
      debugPrint('[浏览器接收] 解析失败: $e');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(settingsProvider, (_, __) => unawaited(_syncBrowserBridge()));
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
        SingleActivator(
          LogicalKeyboardKey.keyE,
          meta: isMac,
          control: !isMac,
        ): () => AddUrlsPanel.show(context),
        SingleActivator(
          LogicalKeyboardKey.keyQ,
          meta: isMac,
          control: !isMac,
        ): () => windowManager.close(),
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
