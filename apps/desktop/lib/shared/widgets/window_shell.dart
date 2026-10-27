import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/platform/automation_queue.dart';
import '../../core/platform/automation_request.dart';
import '../../core/platform/tray_service.dart';
import '../../core/server/browser_bridge.dart';
import '../../core/sites/format_selector.dart';
import '../../core/version/version_check.dart';
import '../../features/downloads/add_urls_panel.dart';
import '../../features/downloads/download_provider.dart';
import '../../features/downloads/queue_search_panel.dart';
import '../../features/downloads/quick_add.dart';
import '../../features/history/history_window.dart';
import '../../features/home/home_provider.dart';
import '../../features/license/license_provider.dart';
import '../../features/preferences/preferences_window.dart';
import '../../features/settings/settings_provider.dart';
import '../theme/design_tokens.dart';
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
  static const _linkChannel = MethodChannel('downie6/links');

  bool _dropHover = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isMacOS) {
      _linkChannel.setMethodCallHandler(_onLinkCall);
      unawaited(
        _linkChannel.invokeMethod<void>('ready').catchError((_) {}),
      );
    }
    unawaited(ref.read(trialProvider.notifier).ensureStarted());
    unawaited(_syncBrowserBridge());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(TrayService.instance.configure(
        show: showMainWindow,
        startAll: () =>
            ref.read(downloadListProvider.notifier).startAll(),
        pauseAll: () =>
            ref.read(downloadListProvider.notifier).pauseAll(),
        history: () {
          if (mounted) HistoryWindow.show(context);
        },
        settings: () {
          if (mounted) PreferencesWindow.show(context);
        },
        quit: () => windowManager.close(),
        enabled: ref.read(settingsProvider).showInMenuBar,
      ));
      for (final request in AutomationQueue.drain()) {
        unawaited(_handleAutomation(request));
      }
    });
    unawaited(() async {
      await Future<void>.delayed(const Duration(seconds: 3));
      if (!mounted) return;
      if (!ref.read(settingsProvider).autoCheckUpdates) return;
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
  void dispose() {
    _linkChannel.setMethodCallHandler(null);
    super.dispose();
  }

  /// macOS AppDelegate 转发来的 `open -a` / `downie6://` 链接。
  Future<dynamic> _onLinkCall(MethodCall call) async {
    if (call.method != 'openUrl') return null;
    final raw = call.arguments;
    if (raw is! String) return null;
    final request = parseAutomationRequest(raw);
    if (request == null) {
      debugPrint('[自动化] 忽略无法识别的链接: $raw');
      return null;
    }
    await _handleAutomation(request);
    return null;
  }

  Future<void> _handleAutomation(AutomationRequest request) async {
    await windowManager.show();
    await windowManager.focus();
    if (!mounted) return;
    await quickAddAutomation(context, ref, request);
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
      final settings = ref.read(settingsProvider);
      final format = selectFormatForDownload(
        info,
        qualityPreference: settings.qualityPreference,
        preferMp4: settings.preferMp4,
        forceMp4: settings.forceMp4,
      );
      if (format == null) return false;
      return await ref.read(downloadListProvider.notifier).startDownload(
            videoInfo: info,
            format: format,
            downloadSubtitles: settings.defaultDownloadSubtitles,
            downloadCover: settings.defaultDownloadCover,
          );
    } catch (e) {
      debugPrint('[浏览器接收] 解析失败: $e');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(settingsProvider, (previous, next) {
      unawaited(_syncBrowserBridge());
      if (previous?.showInMenuBar != next.showInMenuBar) {
        unawaited(TrayService.instance.setEnabled(next.showInMenuBar));
      }
    });
    final quickLoading = ref.watch(quickAddLoadingProvider) > 0;
    final isMac = Platform.isMacOS;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DropRegion(
      formats: const [
        Formats.uri,
        Formats.plainText,
        Formats.plainTextFile,
      ],
      hitTestBehavior: HitTestBehavior.opaque,
      onDropOver: _onDropOver,
      onDropEnter: (_) => setState(() => _dropHover = true),
      onDropLeave: (_) => setState(() => _dropHover = false),
      onDropEnded: (_) => setState(() => _dropHover = false),
      onPerformDrop: _onPerformDrop,
      child: Stack(
        children: [
          CallbackShortcuts(
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
          ),
          if (_dropHover)
            Positioned.fill(
              child: IgnorePointer(
                child: _dropOverlay(dark),
              ),
            ),
          if (quickLoading)
            Positioned(
              top: 4,
              right: 8,
              child: IgnorePointer(child: _loadingPill()),
            ),
        ],
      ),
    );
  }

  Widget _loadingPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppTokens.accent,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.6,
              color: Colors.white,
            ),
          ),
          SizedBox(width: 7),
          Text(
            '加载中...',
            style: TextStyle(fontSize: 12, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _dropOverlay(bool dark) {
    return Container(
      margin: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: (dark ? AppTokens.window : AppTokens.windowLight)
            .withValues(alpha: 0.92),
        border: Border.all(color: AppTokens.accent, width: 2),
        borderRadius: BorderRadius.circular(AppRadius.window),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.download, size: 36, color: AppTokens.accent),
          const SizedBox(height: AppSpacing.md),
          Text(
            '松开以添加链接',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: dark
                  ? AppTokens.textPrimary
                  : AppTokens.textPrimaryLight,
            ),
          ),
        ],
      ),
    );
  }

  DropOperation _onDropOver(DropOverEvent event) {
    for (final item in event.session.items) {
      if (item.canProvide(Formats.uri) ||
          item.canProvide(Formats.plainText) ||
          item.canProvide(Formats.plainTextFile)) {
        return DropOperation.copy;
      }
    }
    return DropOperation.none;
  }

  Future<void> _onPerformDrop(PerformDropEvent event) async {
    final urls = <String>[];
    for (final item in event.session.items) {
      final text = await _readDropText(item);
      if (text == null || text.trim().isEmpty) continue;
      final whole = wholeHttpUrl(text);
      if (whole != null) {
        urls.add(whole);
      } else {
        urls.addAll(extractUrls(text));
      }
    }
    if (!mounted) return;
    setState(() => _dropHover = false);
    final unique = urls.toSet().toList();
    if (unique.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('没有识别到可下载的链接')),
      );
      return;
    }
    await AddUrlsPanel.show(context, initialText: unique.join('\n'));
  }

  Future<String?> _readDropText(DropItem item) async {
    final reader = item.dataReader;
    if (reader == null) return null;

    if (reader.canProvide(Formats.uri)) {
      final completer = Completer<NamedUri?>();
      final progress = reader.getValue<NamedUri>(
        Formats.uri,
        (value) {
          if (!completer.isCompleted) completer.complete(value);
        },
        onError: (_) {
          if (!completer.isCompleted) completer.complete(null);
        },
      );
      if (progress != null) {
        final value = await completer.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () => null,
        );
        if (value != null) return value.uri.toString();
      }
    }

    if (reader.canProvide(Formats.plainText)) {
      final completer = Completer<String?>();
      final progress = reader.getValue<String>(
        Formats.plainText,
        (value) {
          if (!completer.isCompleted) completer.complete(value);
        },
        onError: (_) {
          if (!completer.isCompleted) completer.complete(null);
        },
      );
      if (progress != null) {
        final value = await completer.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () => null,
        );
        if (value != null) return value;
      }
    }

    if (reader.canProvide(Formats.plainTextFile)) {
      final completer = Completer<String?>();
      final progress = reader.getFile(
        Formats.plainTextFile,
        (file) async {
          try {
            if ((file.fileSize ?? 0) > 1024 * 1024) {
              if (!completer.isCompleted) completer.complete(null);
              return;
            }
            final bytes = await file.readAll();
            if (!completer.isCompleted) {
              completer.complete(utf8.decode(bytes, allowMalformed: true));
            }
          } catch (_) {
            if (!completer.isCompleted) completer.complete(null);
          }
        },
        onError: (_) {
          if (!completer.isCompleted) completer.complete(null);
        },
      );
      if (progress != null) {
        return completer.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () => null,
        );
      }
    }
    return null;
  }
}
