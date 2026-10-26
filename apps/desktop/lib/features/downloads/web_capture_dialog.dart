import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../core/platform/webview2.dart';
import '../../core/sites/plugins/generic_web_plugin.dart';
import '../../core/storage/settings_storage.dart';

/// 用户自定义视频提取抓到的媒体地址
@immutable
class CapturedMedia {
  final String url;
  final String kind; // hls / dash / direct
  final String pageUrl;
  final String title;
  final String referer;
  final String cookie;

  const CapturedMedia({
    required this.url,
    required this.kind,
    required this.pageUrl,
    required this.title,
    required this.referer,
    required this.cookie,
  });
}

/// 通用用户自定义视频提取窗口（Downie UGE 式兜底）。
///
/// 打开目标页面，注入 JS hook fetch/XHR/performance，捕获 m3u8/mpd/mp4/flv，
/// 用户选中后带着 cookie + Referer 返回，交给 GenericWebPlugin 用 ffmpeg 下载。
class WebCaptureDialog extends StatefulWidget {
  final String url;
  final WebViewEnvironment? environment;

  const WebCaptureDialog({super.key, required this.url, this.environment});

  /// 弹出嗅探窗口；返回 null 表示用户取消
  static Future<CapturedMedia?> show(BuildContext context, String url) async {
    WebViewEnvironment? env;
    if (Platform.isWindows) {
      try {
        final dir = await SettingsStorage.getStorageDir();
        env = await WebViewEnvironment.create(
          settings: WebViewEnvironmentSettings(
            userDataFolder: '${dir.path}\\WebView2',
          ),
        );
      } catch (e) {
        debugPrint('[嗅探] WebView2 环境创建失败: $e');
      }
    }
    return showDialog<CapturedMedia>(
      context: context,
      barrierDismissible: false,
      builder: (_) => WebCaptureDialog(url: url, environment: env),
    );
  }

  @override
  State<WebCaptureDialog> createState() => _WebCaptureDialogState();
}

class _WebCaptureDialogState extends State<WebCaptureDialog> {
  bool _webView2Missing = false;
  final Map<String, String> _captured = <String, String>{};
  String? _selected;
  String _pageUrl = '';
  String _title = '';
  bool _collecting = false;

  static const String _captureJs = r'''
(function() {
  if (window.__downloCaptureInstalled) return;
  window.__downloCaptureInstalled = true;
  const seen = new Set();
  function report(url) {
    try {
      if (!url || typeof url !== 'string') return;
      if (url.startsWith('blob:') || url.startsWith('data:')) return;
      const lower = url.toLowerCase();
      const manifest = lower.indexOf('.m3u8') >= 0 || lower.indexOf('.mpd') >= 0;
      const direct = /\.(mp4|m4v|flv)(\?|#|$)/.test(lower) || lower.indexOf('mime=video') >= 0 || lower.indexOf('video/mp4') >= 0;
      const segment = lower.indexOf('.m4s') >= 0 || lower.indexOf('.ts') >= 0 || lower.indexOf('segment') >= 0;
      if (!manifest && !direct) return;
      if (!manifest && segment) return;
      if (seen.has(url)) return;
      window.flutter_inappwebview.callHandler('media', url);
      seen.add(url);
    } catch (e) {}
  }
  const origFetch = window.fetch;
  if (origFetch) {
    window.fetch = function() {
      try {
        const a = arguments[0];
        report(a && a.url ? a.url : a);
      } catch (e) {}
      return origFetch.apply(this, arguments);
    };
  }
  const origOpen = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function(method, url) {
    try { report(url); } catch (e) {}
    return origOpen.apply(this, arguments);
  };
  const origSet = Element.prototype.setAttribute;
  Element.prototype.setAttribute = function(name, value) {
    try { if (name === 'src' && value) report(value); } catch (e) {}
    return origSet.apply(this, arguments);
  };
  setInterval(function() {
    try {
      const entries = performance.getEntriesByType('resource');
      for (let i = 0; i < entries.length; i++) report(entries[i].name);
    } catch (e) {}
  }, 2000);
})();
''';

  @override
  void initState() {
    super.initState();
    _pageUrl = widget.url;
    _webView2Missing = !isWebView2Available();
  }

  void _onMedia(String url) {
    final kind = detectMediaKind(url);
    if (kind == null) return;
    if (_captured.containsKey(url)) return;
    if (!mounted) return;
    setState(() {
      _captured[url] = kind;
      _selected ??= url;
    });
  }

  Future<void> _use() async {
    final selected = _selected;
    if (selected == null) return;
    setState(() => _collecting = true);

    final pageUrl = _pageUrl.isNotEmpty ? _pageUrl : widget.url;
    var cookieHeader = '';
    try {
      final uri = Uri.tryParse(pageUrl);
      if (uri != null &&
          (uri.scheme == 'http' || uri.scheme == 'https')) {
        final cookies = await CookieManager.instance(
          webViewEnvironment: widget.environment,
        ).getCookies(url: WebUri(pageUrl));
        cookieHeader =
            cookies.map((c) => '${c.name}=${c.value}').join('; ');
      }
    } catch (e) {
      debugPrint('[嗅探] 获取 Cookie 失败: $e');
    }

    if (!mounted) return;
    Navigator.of(context).pop(CapturedMedia(
      url: selected,
      kind: _captured[selected] ?? 'direct',
      pageUrl: pageUrl,
      title: _title,
      referer: pageUrl,
      cookie: cookieHeader,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      child: SizedBox(
        width: 1000,
        height: 720,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: theme.dividerColor)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.travel_explore, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '用户自定义视频提取',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  SizedBox(
                    width: 360,
                    child: Text(
                      widget.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: '取消',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _webView2Missing
                  ? _buildWebView2Missing(theme)
                  : InAppWebView(
                      webViewEnvironment: widget.environment,
                      initialUrlRequest:
                          URLRequest(url: WebUri(widget.url)),
                      initialSettings: InAppWebViewSettings(
                        javaScriptEnabled: true,
                        mediaPlaybackRequiresUserGesture: false,
                      ),
                      initialUserScripts: UnmodifiableListView<UserScript>([
                        UserScript(
                          source: _captureJs,
                          injectionTime:
                              UserScriptInjectionTime.AT_DOCUMENT_START,
                        ),
                      ]),
                      onWebViewCreated: (controller) {
                        controller.addJavaScriptHandler(
                          handlerName: 'media',
                          callback: (args) {
                            if (args.isNotEmpty) {
                              _onMedia(args.first.toString());
                            }
                            return true;
                          },
                        );
                      },
                      onLoadStart: (controller, url) {
                        if (url != null) {
                          _pageUrl = url.toString();
                        }
                      },
                      onLoadStop: (controller, url) {
                        if (url != null) {
                          _pageUrl = url.toString();
                        }
                      },
                      onTitleChanged: (controller, title) {
                        if (title != null && title.isNotEmpty && mounted) {
                          setState(() => _title = title);
                        }
                      },
                      onReceivedError: (controller, request, error) {
                        debugPrint('[嗅探] 加载错误: ${error.description}');
                      },
                    ),
            ),
            _buildCapturedPanel(theme),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: theme.dividerColor)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '在页面里播放视频（必要时先登录），上方出现媒体地址后选中并点「使用此地址」',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: (_selected == null || _collecting) ? null : _use,
                    icon: _collecting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download),
                    label: Text(_collecting ? '准备中...' : '使用此地址'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCapturedPanel(ThemeData theme) {
    return Container(
      height: 170,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Text(
              '捕获到的媒体（${_captured.length}）',
              style: theme.textTheme.labelMedium,
            ),
          ),
          Expanded(
            child: _captured.isEmpty
                ? Center(
                    child: Text(
                      '还没有捕获到媒体地址，请在页面里播放视频',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView(
                    children: _captured.entries.map((e) {
                      final selected = _selected == e.key;
                      return ListTile(
                        dense: true,
                        selected: selected,
                        onTap: () => setState(() => _selected = e.key),
                        leading: Chip(
                          label: Text(
                            e.value.toUpperCase(),
                            style: const TextStyle(fontSize: 11),
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                        title: Text(
                          e.key,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: selected
                            ? const Icon(Icons.check_circle, size: 18)
                            : null,
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebView2Missing(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text('未检测到 WebView2 运行时', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '用户自定义视频提取需要微软 WebView2 内核才能显示，请安装后重试',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                openWebView2DownloadPage();
              },
              icon: const Icon(Icons.download),
              label: const Text('去下载 WebView2'),
            ),
          ],
        ),
      ),
    );
  }
}
