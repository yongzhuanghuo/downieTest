import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/platform/webview2.dart';
import '../../core/sites/plugins/generic_web_plugin.dart';
import '../../core/sites/search_engines.dart';
import '../../core/storage/settings_storage.dart';
import '../../features/help/help_window.dart';
import '../../features/settings/settings_provider.dart';
import '../../shared/branding/app_brand.dart';
import '../../shared/theme/design_tokens.dart';

const Color _ugeAccent = Color(0xFF0A84FF);

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

/// 点击行内「+」/「添加全部」时的入队回调。
/// 返回 null 表示成功，返回字符串表示错误信息。
typedef UgeEnqueue = Future<String?> Function(CapturedMedia media);

enum _SidebarMode { links, images, subtitles }

class _CapturedItem {
  final String url;
  final String kind; // hls / dash / direct / image / subtitle
  final String host;
  final String title;
  final int width;
  final int height;
  final int? bytes;

  const _CapturedItem({
    required this.url,
    required this.kind,
    required this.host,
    required this.title,
    this.width = 0,
    this.height = 0,
    this.bytes,
  });

  _CapturedItem copyWith({int? bytes}) => _CapturedItem(
        url: url,
        kind: kind,
        host: host,
        title: title,
        width: width,
        height: height,
        bytes: bytes ?? this.bytes,
      );
}

class _Bookmark {
  final String title;
  final String url;
  const _Bookmark(this.title, this.url);
}

/// Downie 4 User-Guided Extraction 的 1:1 窗口。
///
/// 结构来自 XUGuidedExtractionWindowController.nib：
/// - 顶部 Safari 式地址栏（后退/前进、书签、地址、帮助、右侧工具按钮）
/// - 左侧 WKWebView；右侧 300pt 捕获栏（48pt 行、底部搜索/添加全部/清除）
/// - 独立窗口尺寸 1100×548、最小 1010×500，支持边栏开关
class WebCaptureDialog extends ConsumerStatefulWidget {
  final String url;

  /// 自动模式：页面加载后自动选择最佳媒体。
  final bool auto;

  /// 行内添加时直接入队；为空则关闭窗口后把已选列表返回给调用方。
  final UgeEnqueue? onAdd;

  final WebViewEnvironment? environment;

  const WebCaptureDialog({
    super.key,
    this.url = '',
    this.environment,
    this.auto = false,
    this.onAdd,
  });

  /// 打开完整 UGE 窗口；返回关闭时已选择但未直接入队的媒体。
  static Future<List<CapturedMedia>?> show(
    BuildContext context,
    String url, {
    bool auto = false,
    UgeEnqueue? onAdd,
  }) async {
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
        debugPrint('[UGE] WebView2 环境创建失败: $e');
      }
    }
    if (!context.mounted) return null;
    return Navigator.of(context, rootNavigator: true).push<List<CapturedMedia>>(
      PageRouteBuilder<List<CapturedMedia>>(
        opaque: true,
        barrierDismissible: false,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, __, ___) => WebCaptureDialog(
          url: url,
          environment: env,
          auto: auto,
          onAdd: onAdd,
        ),
      ),
    );
  }

  @override
  ConsumerState<WebCaptureDialog> createState() => _WebCaptureDialogState();
}

class _WebCaptureDialogState extends ConsumerState<WebCaptureDialog>
    with WindowListener {
  static const String _uaDesktop =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/126.0.0.0 Safari/537.36';
  static const String _uaSafari =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15';
  static const String _uaChrome =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/126.0.0.0 Safari/537.36';
  static const String _uaMobile =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 '
      'Mobile/15E148 Safari/604.1';

  final _addressController = TextEditingController();
  final _addressFocus = FocusNode();
  final _searchController = TextEditingController();

  InAppWebViewController? _webController;
  bool _webView2Missing = false;
  bool _closing = false;
  bool _loading = false;
  double _progress = 0;
  bool _canBack = false;
  bool _canForward = false;
  bool _muted = false;
  bool _sidebarVisible = true;
  bool _popupsEnabled = true;
  bool _compatibility = false;
  bool _mergeHls = true;
  String _uaMode = 'chrome';
  String _pageUrl = '';
  String _title = '';
  Size? _savedSize;
  Offset? _savedPosition;
  bool _savedMaximized = false;
  bool _disposed = false;

  _SidebarMode _mode = _SidebarMode.links;
  final Map<String, _CapturedItem> _links = <String, _CapturedItem>{};
  final Map<String, _CapturedItem> _images = <String, _CapturedItem>{};
  final Map<String, _CapturedItem> _subtitles = <String, _CapturedItem>{};
  final Set<String> _added = <String>{};
  final Set<String> _adding = <String>{};
  final List<CapturedMedia> _pending = <CapturedMedia>[];
  final List<_Bookmark> _bookmarks = <_Bookmark>[];
  OverlayEntry? _popover;
  bool _addingAll = false;

  bool _autoActive = false;
  DateTime? _autoStartedAt;
  DateTime? _firstMediaAt;
  Timer? _autoTimer;

  String _cookiePage = '';
  String _cookieValue = '';

  static const String _captureJs = r'''
(function() {
  if (window.__downloCaptureInstalled) return;
  window.__downloCaptureInstalled = true;
  const seen = new Set();
  const seenAsset = new Set();
  function absolute(url) {
    try { return new URL(url, location.href).href; } catch (e) { return url; }
  }
  function report(raw) {
    try {
      if (!raw || typeof raw !== 'string') return;
      const url = absolute(raw.trim());
      if (!/^https?:/i.test(url)) return;
      const lower = url.toLowerCase();
      if (lower.indexOf('/media-audio-') >= 0 ||
          lower.indexOf('mime_type=audio') >= 0 ||
          lower.indexOf('mimetype=audio') >= 0) return;
      const manifest = lower.indexOf('.m3u8') >= 0 || lower.indexOf('.mpd') >= 0;
      const direct = /\.(mp4|m4v|flv)(\?|#|$)/.test(lower) ||
        lower.indexOf('mime_type=video') >= 0 ||
        lower.indexOf('mimetype=video') >= 0 ||
        lower.indexOf('/media-video-') >= 0 ||
        lower.indexOf('/video/mp4') >= 0 ||
        lower.indexOf('format=mp4') >= 0;
      const segment = lower.indexOf('.m4s') >= 0 ||
        lower.indexOf('.ts') >= 0 || lower.indexOf('/segment') >= 0;
      if (!manifest && !direct) return;
      if (!manifest && segment) return;
      if (seen.has(url)) return;
      seen.add(url);
      window.flutter_inappwebview.callHandler('media', url);
    } catch (e) {}
  }
  function reportAsset(kind, url, extra) {
    try {
      if (!url || typeof url !== 'string') return;
      const resolved = absolute(url.trim());
      if (!/^https?:/i.test(resolved)) return;
      if (seenAsset.has(resolved)) return;
      seenAsset.add(resolved);
      const payload = Object.assign({kind: kind, url: resolved}, extra || {});
      window.flutter_inappwebview.callHandler('asset', JSON.stringify(payload));
    } catch (e) {}
  }
  function reportSubtitle(url) {
    try {
      if (!url) return;
      if (!/\.(vtt|srt|ass|ssa)(\?|#|$)/i.test(url)) return;
      reportAsset('subtitle', url, {});
    } catch (e) {}
  }
  const origFetch = window.fetch;
  if (origFetch) {
    window.fetch = function() {
      try {
        const a = arguments[0];
        const u = a && a.url ? a.url : a;
        report(u); reportSubtitle(u);
      } catch (e) {}
      return origFetch.apply(this, arguments);
    };
  }
  const origOpen = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function(method, url) {
    try { report(url); reportSubtitle(url); } catch (e) {}
    return origOpen.apply(this, arguments);
  };
  const origSet = Element.prototype.setAttribute;
  Element.prototype.setAttribute = function(name, value) {
    try {
      if (name === 'src' && value) { report(value); reportSubtitle(value); }
    } catch (e) {}
    return origSet.apply(this, arguments);
  };
  function walkJson(value, depth) {
    if (!value || depth > 12) return;
    if (typeof value === 'string') { report(value); reportSubtitle(value); return; }
    if (Array.isArray(value)) { value.forEach(function(v) { walkJson(v, depth + 1); }); return; }
    if (typeof value === 'object') {
      Object.keys(value).forEach(function(k) { walkJson(value[k], depth + 1); });
    }
  }
  function scanImages() {
    try {
      document.querySelectorAll('img').forEach(function(img) {
        const w = img.naturalWidth || 0;
        const h = img.naturalHeight || 0;
        if (w >= 200 && h >= 120) {
          reportAsset('image', img.currentSrc || img.src, {width: w, height: h});
        }
      });
      const meta = document.querySelector(
        'meta[property="og:image"], meta[property="og:image:url"], ' +
        'meta[property="og:image:secure_url"]');
      if (meta) reportAsset('image', meta.getAttribute('content'), {});
    } catch (e) {}
  }
  function scanDom() {
    try {
      document.querySelectorAll('video, source').forEach(function(el) {
        report(el.currentSrc || el.src || el.getAttribute('src'));
      });
      const meta = document.querySelector(
        'meta[property="og:video"], meta[property="og:video:url"], ' +
        'meta[property="og:video:secure_url"], meta[name="twitter:player:stream"]');
      if (meta) report(meta.getAttribute('content'));
      document.querySelectorAll('script[type="application/ld+json"]').forEach(function(s) {
        try { walkJson(JSON.parse(s.textContent || ''), 0); } catch (e) {}
      });
    } catch (e) {}
  }
  setInterval(function() {
    try {
      const entries = performance.getEntriesByType('resource');
      for (let i = 0; i < entries.length; i++) {
        report(entries[i].name);
        reportSubtitle(entries[i].name);
      }
    } catch (e) {}
  }, 1500);
  setInterval(scanDom, 2000);
  setInterval(scanImages, 2200);
  setInterval(function() {
    try {
      document.querySelectorAll('video').forEach(function(v) {
        if (v.paused) v.play().catch(function(){});
      });
    } catch (e) {}
  }, 1500);
  document.addEventListener('playing', function(e) {
    try { report(e.target.currentSrc || e.target.src); } catch (e) {}
  }, true);
  document.addEventListener('loadedmetadata', function(e) {
    try { report(e.target.currentSrc || e.target.src); } catch (e) {}
  }, true);
  scanImages();
})();
''';

  @override
  void initState() {
    super.initState();
    _pageUrl = widget.url;
    _addressController.text = widget.url;
    _webView2Missing = !isWebView2Available();
    _searchController.addListener(_onSearchChanged);
    if (!_webView2Missing && widget.url.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _addressFocus.requestFocus();
      });
    }
    if (widget.auto && !_webView2Missing) {
      _autoActive = true;
      _autoStartedAt = DateTime.now();
      _autoTimer = Timer.periodic(
        const Duration(milliseconds: 500),
        (_) => _tickAuto(),
      );
    }
    unawaited(_configureWindow());
  }

  @override
  void dispose() {
    _disposed = true;
    _autoTimer?.cancel();
    _closePopover();
    _searchController.removeListener(_onSearchChanged);
    _addressController.dispose();
    _addressFocus.dispose();
    _searchController.dispose();
    windowManager.removeListener(this);
    unawaited(_restoreWindow());
    super.dispose();
  }

  Future<void> _configureWindow() async {
    try {
      windowManager.addListener(this);
      _savedMaximized = await windowManager.isMaximized();
      _savedSize = await windowManager.getSize();
      _savedPosition = await windowManager.getPosition();
      if (_disposed) return;
      if (_savedMaximized) await windowManager.unmaximize();
      if (_disposed) return;
      await windowManager.setMinimumSize(const Size(1010, 500));
      await windowManager.setSize(const Size(1100, 620));
      await windowManager.center();
      await windowManager.setTitle('用户自定义视频提取');
      await windowManager.setPreventClose(true);
      if (_disposed) {
        await _restoreWindow();
      }
    } catch (e) {
      debugPrint('[UGE] 窗口设置失败: $e');
    }
  }

  Future<void> _restoreWindow() async {
    try {
      await windowManager.setPreventClose(false);
      await windowManager.setMinimumSize(const Size(800, 600));
      await windowManager.setTitle(AppBrand.name);
      if (_savedSize != null || _savedPosition != null || _savedMaximized) {
        if (_savedMaximized) {
          await windowManager.maximize();
        } else {
          if (_savedSize != null) await windowManager.setSize(_savedSize!);
          if (_savedPosition != null) {
            await windowManager.setPosition(_savedPosition!);
          }
        }
      }
    } catch (e) {
      debugPrint('[UGE] 恢复窗口失败: $e');
    }
  }

  @override
  void onWindowClose() {
    if (!_closing) {
      _close();
    }
  }

  Future<void> _close() async {
    if (_closing || !mounted) return;
    _closing = true;
    _closePopover();
    await windowManager.setPreventClose(false).catchError((_) {});
    if (!mounted) return;
    Navigator.of(context).pop<List<CapturedMedia>>(
      List<CapturedMedia>.of(_pending),
    );
  }

  Future<void> _toggleMaximize() async {
    try {
      if (await windowManager.isMaximized()) {
        await windowManager.unmaximize();
      } else {
        await windowManager.maximize();
      }
    } catch (e) {
      debugPrint('[UGE] 最大化切换失败: $e');
    }
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  String get _query => _searchController.text.trim().toLowerCase();

  String _currentUa() {
    switch (_uaMode) {
      case 'safari':
        return _uaSafari;
      case 'chrome':
        return _uaChrome;
      case 'mobile':
        return _uaMobile;
      default:
        return _uaDesktop;
    }
  }

  Future<void> _applyUa() async {
    final ua = _currentUa();
    try {
      await _webController?.setSettings(
        settings: InAppWebViewSettings(
          userAgent: ua,
          javaScriptEnabled: true,
          javaScriptCanOpenWindowsAutomatically: _popupsEnabled,
          supportMultipleWindows: true,
          mediaPlaybackRequiresUserGesture: false,
        ),
      );
      await _webController?.reload();
    } catch (e) {
      debugPrint('[UGE] 应用 User-Agent 失败: $e');
    }
  }

  Future<void> _navigate(String input) async {
    final value = input.trim();
    if (value.isEmpty) return;
    final engine = ref.read(settingsProvider).searchEngine;
    final target = resolveAddressInput(value, engineId: engine);
    if (target.isEmpty) return;
    _addressFocus.unfocus();
    _addressController.text = target;
    await _webController?.loadUrl(
      urlRequest: URLRequest(url: WebUri(target)),
    );
  }

  void _syncAddress(String url) {
    if (url == 'about:blank') return;
    _pageUrl = url;
    if (!_addressFocus.hasFocus) {
      _addressController.text = url;
    }
  }

  Future<void> _updateNavState() async {
    final c = _webController;
    if (c == null) return;
    try {
      final back = await c.canGoBack();
      final forward = await c.canGoForward();
      if (mounted) {
        setState(() {
          _canBack = back;
          _canForward = forward;
        });
      }
    } catch (_) {}
  }

  Future<void> _goBack() async {
    final c = _webController;
    if (c == null) return;
    if (await c.canGoBack()) await c.goBack();
  }

  Future<void> _goForward() async {
    final c = _webController;
    if (c == null) return;
    if (await c.canGoForward()) await c.goForward();
  }

  Future<void> _reload() async {
    await _webController?.reload();
  }

  Future<void> _toggleMute() async {
    _muted = !_muted;
    await _webController?.evaluateJavascript(
      source: _muted
          ? 'document.querySelectorAll("video,audio").forEach(function(m){m.muted=true;});'
          : 'document.querySelectorAll("video,audio").forEach(function(m){m.muted=false;});',
    );
    if (mounted) setState(() {});
  }

  String _fileName(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return '';
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return '';
    var name = segments.last;
    try {
      name = Uri.decodeComponent(name);
    } catch (_) {}
    if (name.length > 64) name = name.substring(0, 64);
    return name;
  }

  String _extOf(String url) {
    final name = _fileName(url);
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  void _onMedia(String url) {
    final kind = detectMediaKind(url);
    if (kind == null) return;
    if (_links.containsKey(url)) return;
    final uri = Uri.tryParse(url);
    final host = uri?.host ?? '';
    final ext = _extOf(url);
    final String title;
    if (kind == 'direct') {
      final name = _fileName(url);
      title = name.isEmpty ? '视频文件' : name;
    } else if (kind == 'hls') {
      title = 'HLS Stream';
    } else {
      title = 'DASH Stream';
    }
    final item = _CapturedItem(
      url: url,
      kind: kind,
      host: host,
      title: title,
    );
    _firstMediaAt ??= DateTime.now();
    if (!mounted) return;
    setState(() => _links[url] = item);
    debugPrint('[UGE] 捕获 $kind ${ext.isEmpty ? '' : '.$ext'} $url');
    if (kind == 'direct') unawaited(_loadSize(item));
  }

  void _onAsset(String raw) {
    if (!mounted) return;
    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      data = Map<String, dynamic>.from(decoded);
    } catch (_) {
      return;
    }
    final kind = data['kind']?.toString() ?? '';
    final url = data['url']?.toString() ?? '';
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final host = uri.host;
    final name = _fileName(url);
    if (kind == 'image') {
      if (_images.containsKey(url) || _images.length >= 300) return;
      final item = _CapturedItem(
        url: url,
        kind: 'image',
        host: host,
        title: name.isEmpty ? '图片' : name,
        width: (data['width'] as num?)?.toInt() ?? 0,
        height: (data['height'] as num?)?.toInt() ?? 0,
      );
      setState(() => _images[url] = item);
      unawaited(_loadSize(item));
    } else if (kind == 'subtitle') {
      if (_subtitles.containsKey(url) || _subtitles.length >= 100) return;
      final item = _CapturedItem(
        url: url,
        kind: 'subtitle',
        host: host,
        title: name.isEmpty ? '字幕' : name,
      );
      setState(() => _subtitles[url] = item);
      unawaited(_loadSize(item));
    }
  }

  Future<void> _loadSize(_CapturedItem item) async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
      final req = await client.headUrl(Uri.parse(item.url));
      if (_pageUrl.isNotEmpty) {
        req.headers.set(HttpHeaders.refererHeader, _pageUrl);
        final cookie = await _cookieHeader();
        if (cookie.isNotEmpty) {
          req.headers.set(HttpHeaders.cookieHeader, cookie);
        }
      }
      final resp = await req.close().timeout(const Duration(seconds: 8));
      final length = resp.contentLength;
      await resp.drain();
      if (length > 0 && mounted) {
        final map = _mapFor(item.kind);
        if (map != null && map.containsKey(item.url)) {
          setState(() => map[item.url] = item.copyWith(bytes: length));
        }
      }
    } catch (_) {
      // HEAD 失败不影响列表展示
    } finally {
      client?.close(force: true);
    }
  }

  Map<String, _CapturedItem>? _mapFor(String kind) {
    if (kind == 'image') return _images;
    if (kind == 'subtitle') return _subtitles;
    return _links;
  }

  Future<String> _cookieHeader() async {
    final page = _pageUrl;
    if (page.isEmpty || page == 'about:blank') return '';
    if (_cookiePage == page && _cookieValue.isNotEmpty) return _cookieValue;
    try {
      final cookies = await CookieManager.instance(
        webViewEnvironment: widget.environment,
      ).getCookies(url: WebUri(page));
      _cookiePage = page;
      _cookieValue = cookies.map((c) => '${c.name}=${c.value}').join('; ');
    } catch (e) {
      debugPrint('[UGE] 获取 Cookie 失败: $e');
    }
    return _cookieValue;
  }

  Future<CapturedMedia> _mediaFromItem(_CapturedItem item) async {
    final pageUrl = _pageUrl.isNotEmpty ? _pageUrl : widget.url;
    final cookie = await _cookieHeader();
    final host = Uri.tryParse(pageUrl)?.host ?? '';
    return CapturedMedia(
      url: item.url,
      kind: item.kind,
      pageUrl: pageUrl,
      title: _title.isNotEmpty ? _title : host,
      referer: pageUrl,
      cookie: cookie,
    );
  }

  Future<void> _addItem(_CapturedItem item) async {
    if (_added.contains(item.url) || _adding.contains(item.url)) return;
    if (item.kind == 'image' || item.kind == 'subtitle') {
      _toast('图片/字幕下载暂未接入队列');
      return;
    }
    _adding.add(item.url);
    if (mounted) setState(() {});
    final media = await _mediaFromItem(item);
    String? error;
    if (widget.onAdd != null) {
      try {
        error = await widget.onAdd!(media);
      } catch (e) {
        error = '$e';
      }
    } else {
      _pending.add(media);
    }
    _adding.remove(item.url);
    if (!mounted) return;
    setState(() {
      if (error == null) _added.add(item.url);
    });
    if (error != null) _toast('添加失败：$error');
  }

  Future<void> _addAll() async {
    if (_addingAll) return;
    final items = _filteredLinks.where((e) => !_added.contains(e.url)).toList();
    if (items.isEmpty) return;
    _addingAll = true;
    if (mounted) setState(() {});
    var failed = 0;
    for (final item in items) {
      await _addItem(item);
      if (!_added.contains(item.url)) failed++;
    }
    _addingAll = false;
    if (mounted) {
      setState(() {});
      if (failed == 0) {
        _toast('已添加 ${items.length} 项到下载队列');
      } else {
        _toast('已添加 ${items.length - failed} 项，失败 $failed 项');
      }
    }
  }

  void _clearMode() {
    _searchController.clear();
    setState(() {
      switch (_mode) {
        case _SidebarMode.links:
          final removed = _links.keys.toSet();
          _added.removeAll(removed);
          _links.clear();
          break;
        case _SidebarMode.images:
          _images.clear();
          break;
        case _SidebarMode.subtitles:
          _subtitles.clear();
          break;
      }
    });
  }

  void _toast(String text) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(text, style: const TextStyle(fontSize: 12)),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  List<_CapturedItem> get _filteredLinks => _filter(_links.values);
  List<_CapturedItem> get _filteredImages => _filter(_images.values);
  List<_CapturedItem> get _filteredSubtitles => _filter(_subtitles.values);

  List<_CapturedItem> _filter(Iterable<_CapturedItem> items) {
    final q = _query;
    final list = items.where((item) {
      if (q.isEmpty) return true;
      return item.title.toLowerCase().contains(q) ||
          item.host.toLowerCase().contains(q) ||
          item.url.toLowerCase().contains(q);
    }).toList();
    return list;
  }

  List<_CapturedItem> get _currentItems {
    switch (_mode) {
      case _SidebarMode.images:
        return _filteredImages;
      case _SidebarMode.subtitles:
        return _filteredSubtitles;
      case _SidebarMode.links:
        return _filteredLinks;
    }
  }

  void _setMode(_SidebarMode mode) {
    _closePopover();
    _searchController.clear();
    setState(() {
      _mode = mode;
      _sidebarVisible = true;
    });
  }

  void _tickAuto() {
    if (!mounted || !_autoActive || _closing) return;
    final now = DateTime.now();
    final first = _firstMediaAt;
    if (first != null) {
      if (now.difference(first) >= const Duration(seconds: 4)) {
        final best = _bestCandidate();
        if (best != null) {
          _autoActive = false;
          _autoTimer?.cancel();
          unawaited(() async {
            await _addItem(best);
            if (mounted) await _close();
          }());
          return;
        }
      }
    } else if (_autoStartedAt != null &&
        now.difference(_autoStartedAt!) >= const Duration(seconds: 18)) {
      _autoActive = false;
      _autoTimer?.cancel();
      if (mounted) setState(() {});
    }
  }

  _CapturedItem? _bestCandidate() {
    for (final kind in const ['hls', 'dash', 'direct']) {
      for (final item in _links.values) {
        if (item.kind == kind) return item;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final chrome = dark ? AppTokens.titleBar : const Color(0xFFF3F3F3);
    final web = dark ? const Color(0xFF1E1E1E) : Colors.white;
    final mac = Platform.isMacOS;
    final isMac = mac;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): _close,
        SingleActivator(
          LogicalKeyboardKey.keyW,
          meta: isMac,
          control: !isMac,
        ): _close,
        SingleActivator(
          LogicalKeyboardKey.keyR,
          meta: isMac,
          control: !isMac,
        ): () => unawaited(_reload()),
        SingleActivator(
          LogicalKeyboardKey.keyL,
          meta: isMac,
          control: !isMac,
        ): () => _addressFocus.requestFocus(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          backgroundColor: web,
          body: Column(
            children: [
              _buildTitleRow(context, chrome),
              _buildToolbar(context, chrome),
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: _buildWebView(web)),
                    if (_sidebarVisible) ...[
                      Container(
                        width: 1,
                        color: dark
                            ? AppTokens.divider
                            : const Color(0xFFD9D9D9),
                      ),
                      SizedBox(
                        width: 300,
                        child: _buildSidebar(context),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 28px 原生标题栏：macOS 只留交通灯拖拽区，Windows 显示图标/标题/caption。
  Widget _buildTitleRow(BuildContext context, Color chrome) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => windowManager.startDragging(),
      onDoubleTap: _toggleMaximize,
      child: Container(
        height: 28,
        color: chrome,
        child: Platform.isMacOS
            ? const SizedBox.expand()
            : Row(
                children: [
                  const SizedBox(width: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.asset(
                      AppBrand.logoAsset,
                      width: 14,
                      height: 14,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    '用户自定义视频提取',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: dark
                          ? AppTokens.textPrimary
                          : AppTokens.textPrimaryLight,
                    ),
                  ),
                  const Spacer(),
                  ..._windowsCaptions(dark, height: 28),
                ],
              ),
      ),
    );
  }

  /// 36px 工具栏：导航 + 地址 + 右侧按钮（对应 nib 的三个 titlebar accessory）。
  Widget _buildToolbar(BuildContext context, Color chrome) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final divider = dark ? AppTokens.divider : const Color(0xFFD6D6D6);
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: chrome,
        border: Border(bottom: BorderSide(color: divider)),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => windowManager.startDragging(),
        onDoubleTap: _toggleMaximize,
        child: Row(
          children: [
            SizedBox(width: Platform.isMacOS ? 92 : 12),
            _buildNavCluster(dark),
            const SizedBox(width: 10),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: _buildAddressBar(dark),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _buildActions(dark),
            const SizedBox(width: 10),
          ],
        ),
      ),
    );
  }

  Widget _buildNavCluster(bool dark) {
    final bg = dark ? AppTokens.panelRaised : const Color(0xFFE9E9E9);
    final fg = dark ? AppTokens.textSecondary : const Color(0xFF3A3A3C);
    final disabled =
        dark ? AppTokens.textTertiary : const Color(0xFFB0B0B5);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 63,
          height: 24,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Row(
            children: [
              Expanded(
                child: _NavButton(
                  icon: Icons.chevron_left,
                  color: _canBack ? fg : disabled,
                  onTap: _canBack ? _goBack : null,
                ),
              ),
              Container(
                width: 1,
                height: 14,
                color: dark ? AppTokens.divider : const Color(0xFFCFCFCF),
              ),
              Expanded(
                child: _NavButton(
                  icon: Icons.chevron_right,
                  color: _canForward ? fg : disabled,
                  onTap: _canForward ? _goForward : null,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Builder(
          builder: (ctx) => _ChromeIcon(
            icon: Icons.book_outlined,
            tooltip: '书签',
            size: 16,
            color: fg,
            onTap: () => _showBookmarks(ctx),
          ),
        ),
      ],
    );
  }

  Widget _buildAddressBar(bool dark) {
    final fill = dark ? const Color(0xFF3A3A3A) : const Color(0xFFE9E9E9);
    final text = dark ? AppTokens.textPrimary : AppTokens.textPrimaryLight;
    final secondary =
        dark ? AppTokens.textSecondary : const Color(0xFF8E8E93);
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 26,
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: fill,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                Row(
                  children: [
                    const SizedBox(width: 8),
                    Icon(Icons.search, size: 13, color: secondary),
                    const SizedBox(width: 5),
                    Expanded(
                      child: TextField(
                        controller: _addressController,
                        focusNode: _addressFocus,
                        style: TextStyle(fontSize: 12.5, color: text),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 7),
                          hintText: '键入地址于此以开始',
                          hintStyle: TextStyle(
                            fontSize: 12.5,
                            color: secondary,
                          ),
                        ),
                        onSubmitted: _navigate,
                      ),
                    ),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.6,
                            color: _ugeAccent,
                          ),
                        ),
                      ),
                  ],
                ),
                if (_loading && _progress > 0)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(6),
                      ),
                      child: LinearProgressIndicator(
                        value: _progress,
                        minHeight: 2,
                        backgroundColor: Colors.transparent,
                        color: _ugeAccent,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 4),
        _ChromeIcon(
          icon: Icons.help_outline,
          tooltip: '帮助',
          size: 16,
          color: secondary,
          onTap: () => _showHelp(),
        ),
      ],
    );
  }

  Widget _buildActions(bool dark) {
    final fg = dark ? AppTokens.textSecondary : const Color(0xFF3A3A3C);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionButton(
          icon: _muted ? Icons.volume_off_outlined : Icons.volume_up_outlined,
          tooltip: _muted ? '取消静音' : '静音',
          color: fg,
          active: _muted,
          onTap: _toggleMute,
        ),
        const SizedBox(width: 2),
        Builder(
          builder: (ctx) => _ActionButton(
            icon: Icons.settings_outlined,
            tooltip: '选项',
            color: fg,
            onTap: () => _showOptions(ctx),
          ),
        ),
        const SizedBox(width: 2),
        _ActionButton(
          icon: Icons.photo_library_outlined,
          tooltip: '图片',
          color: _mode == _SidebarMode.images ? _ugeAccent : fg,
          badge: _images.isNotEmpty ? _images.length : null,
          onTap: () => _setMode(_SidebarMode.images),
        ),
        const SizedBox(width: 2),
        _ActionButton(
          icon: Icons.subtitles_outlined,
          tooltip: '字幕',
          color: _mode == _SidebarMode.subtitles ? _ugeAccent : fg,
          badge: _subtitles.isNotEmpty ? _subtitles.length : null,
          onTap: () => _setMode(_SidebarMode.subtitles),
        ),
        if (_links.isNotEmpty) ...[
          const SizedBox(width: 2),
          _ActionButton(
            icon: Icons.download_outlined,
            tooltip: '下载',
            color: _mode == _SidebarMode.links ? _ugeAccent : fg,
            badge: _links.length,
            onTap: () => _setMode(_SidebarMode.links),
          ),
        ],
        const SizedBox(width: 2),
        _ActionButton(
          icon: Icons.view_sidebar,
          tooltip: _sidebarVisible ? '隐藏边栏' : '显示边栏',
          color: _sidebarVisible ? _ugeAccent : fg,
          onTap: () => setState(() => _sidebarVisible = !_sidebarVisible),
        ),
      ],
    );
  }

  List<Widget> _windowsCaptions(bool dark, {double height = 28}) {
    final fg = dark ? AppTokens.textSecondary : const Color(0xFF3A3A3C);
    return [
      _WinCaption(
        icon: Icons.remove,
        color: fg,
        height: height,
        onTap: () => windowManager.minimize(),
      ),
      _WinCaption(
        icon: Icons.crop_square,
        color: fg,
        height: height,
        onTap: _toggleMaximize,
      ),
      _WinCaption(
        icon: Icons.close,
        color: fg,
        height: height,
        hover: AppTokens.error,
        onTap: _close,
      ),
    ];
  }

  Widget _buildWebView(Color background) {
    if (_webView2Missing) return _buildWebView2Missing(background);
    return InAppWebView(
      webViewEnvironment: widget.environment,
      initialUrlRequest: URLRequest(
        url: WebUri(widget.url.isEmpty ? 'about:blank' : widget.url),
      ),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        userAgent: _currentUa(),
        javaScriptCanOpenWindowsAutomatically: _popupsEnabled,
        supportMultipleWindows: true,
        mediaPlaybackRequiresUserGesture: false,
        allowsBackForwardNavigationGestures: true,
      ),
      initialUserScripts: UnmodifiableListView<UserScript>([
        UserScript(
          source: _captureJs,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
      ]),
      onWebViewCreated: (controller) {
        _webController = controller;
        controller.addJavaScriptHandler(
          handlerName: 'media',
          callback: (args) {
            if (args.isNotEmpty) _onMedia(args.first.toString());
            return true;
          },
        );
        controller.addJavaScriptHandler(
          handlerName: 'asset',
          callback: (args) {
            if (args.isNotEmpty) _onAsset(args.first.toString());
            return true;
          },
        );
      },
      onCreateWindow: (controller, action) async {
        if (!_popupsEnabled) return false;
        final url = action.request.url;
        if (url != null) {
          await controller.loadUrl(urlRequest: URLRequest(url: url));
        }
        return false;
      },
      onLoadStart: (controller, url) {
        if (url != null) _syncAddress(url.toString());
        if (mounted) {
          setState(() {
            _loading = true;
            _progress = 0;
          });
        }
      },
      onLoadStop: (controller, url) {
        if (url != null) _syncAddress(url.toString());
        if (mounted) {
          setState(() {
            _loading = false;
            _progress = 1;
          });
        }
        unawaited(_updateNavState());
        if (_muted) {
          unawaited(controller.evaluateJavascript(
            source:
                'document.querySelectorAll("video,audio").forEach(function(m){m.muted=true;});',
          ));
        }
      },
      onProgressChanged: (controller, progress) {
        if (!mounted) return;
        setState(() {
          _progress = (progress / 100).clamp(0.0, 1.0);
          _loading = progress < 100;
        });
      },
      onUpdateVisitedHistory: (controller, url, isReload) {
        if (url != null) _syncAddress(url.toString());
        unawaited(_updateNavState());
      },
      onTitleChanged: (controller, title) {
        if (title != null && title.isNotEmpty && mounted) {
          setState(() => _title = title);
        }
      },
      onReceivedError: (controller, request, error) {
        debugPrint('[UGE] 加载错误: ${error.description}');
      },
    );
  }

  Widget _buildWebView2Missing(Color background) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final secondary =
        dark ? AppTokens.textSecondary : AppTokens.textSecondaryLight;
    return Container(
      color: background,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 40, color: AppTokens.error),
          const SizedBox(height: 12),
          const Text('未检测到 WebView2 运行时',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(
            '用户自定义视频提取需要微软 WebView2 内核',
            style: TextStyle(fontSize: 12, color: secondary),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: openWebView2DownloadPage,
            icon: const Icon(Icons.download, size: 16),
            label: const Text('去下载 WebView2'),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? const Color(0xFF1F1F1F) : const Color(0xFFF5F5F7);
    return Container(
      color: bg,
      child: Column(
        children: [
          Expanded(child: _buildSidebarBody(dark)),
          _buildSidebarFooter(dark),
        ],
      ),
    );
  }

  Widget _buildSidebarBody(bool dark) {
    if (_mode == _SidebarMode.images) {
      return _buildImagesGrid(dark);
    }
    final items = _currentItems;
    if (items.isEmpty) return const SizedBox.expand();
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _UgeRow(
          key: ValueKey('${_mode.name}:${item.url}'),
          item: item,
          dark: dark,
          added: _added.contains(item.url),
          adding: _adding.contains(item.url),
          showAdd: _mode == _SidebarMode.links,
          onAdd: () => _addItem(item),
          subtitle: _rowSubtitle(item),
        );
      },
    );
  }

  Widget _buildImagesGrid(bool dark) {
    final items = _filteredImages;
    if (items.isEmpty) return const SizedBox.expand();
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 0.82,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _ImageTile(item: item, dark: dark);
      },
    );
  }

  String _rowSubtitle(_CapturedItem item) {
    final parts = <String>[];
    final ext = _extOf(item.url);
    if (item.kind == 'image') {
      if (item.width > 0 && item.height > 0) {
        parts.add('${item.width}×${item.height}');
      }
      if (item.bytes != null) parts.add(_formatBytes(item.bytes!));
      if (ext.isNotEmpty) parts.add(ext.toUpperCase());
    } else if (item.kind == 'subtitle') {
      parts.add('字幕');
      if (item.bytes != null) parts.add(_formatBytes(item.bytes!));
      if (ext.isNotEmpty) parts.add(ext.toUpperCase());
    } else {
      switch (item.kind) {
        case 'hls':
          parts.add('HLS');
          break;
        case 'dash':
          parts.add('DASH');
          break;
        default:
          parts.add('Direct Downloader');
      }
      if (item.bytes != null) parts.add(_formatBytes(item.bytes!));
      if (ext.isNotEmpty) parts.add(ext.toUpperCase());
    }
    return parts.join(' • ');
  }

  Widget _buildSidebarFooter(bool dark) {
    final border = dark ? AppTokens.divider : const Color(0xFFD9D9D9);
    final bg = dark ? const Color(0xFF252525) : const Color(0xFFECECEC);
    final enabled = _mode == _SidebarMode.links && _currentItems.isNotEmpty;
    final secondary =
        dark ? AppTokens.textSecondary : const Color(0xFF8E8E93);
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: bg,
        border: Border(top: BorderSide(color: border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 22,
              decoration: BoxDecoration(
                color: dark ? const Color(0xFF2E2E2E) : Colors.white,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: dark ? const Color(0xFF454545) : const Color(0xFFD1D1D6),
                ),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 5),
                  Icon(Icons.search, size: 11, color: secondary),
                  const SizedBox(width: 3),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      style: TextStyle(
                        fontSize: 11,
                        color: dark
                            ? AppTokens.textPrimary
                            : AppTokens.textPrimaryLight,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 4),
                        hintText: '搜索',
                        hintStyle:
                            TextStyle(fontSize: 11, color: secondary),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _SidebarButton(
            label: '添加全部',
            dark: dark,
            enabled: enabled && !_addingAll,
            onTap: _addAll,
          ),
          const SizedBox(width: 6),
          _SidebarButton(
            label: '清除',
            dark: dark,
            enabled: _currentItems.isNotEmpty,
            onTap: _clearMode,
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // Popovers
  // ------------------------------------------------------------------

  void _closePopover() {
    _popover?.remove();
    _popover = null;
  }

  void _showPopover(
    BuildContext anchor,
    double width,
    Widget child, {
    double maxHeight = 360,
  }) {
    _closePopover();
    final box = anchor.findRenderObject() as RenderBox?;
    if (box == null) return;
    final offset = box.localToGlobal(Offset.zero);
    final screen = MediaQuery.sizeOf(context);
    final left = (offset.dx + box.size.width - width)
        .clamp(8.0, (screen.width - width - 8).clamp(8.0, screen.width))
        .toDouble();
    final top = (offset.dy + box.size.height + 6)
        .clamp(8.0, (screen.height - maxHeight - 8).clamp(8.0, screen.height))
        .toDouble();
    final entry = OverlayEntry(
      builder: (_) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _closePopover,
            ),
          ),
          Positioned(
            left: left,
            top: top,
            width: width,
            child: Material(
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF2C2C2C)
                  : Colors.white,
              elevation: 12,
              shadowColor: Colors.black45,
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
    _popover = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
  }

  void _showBookmarks(BuildContext anchor) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = dark ? AppTokens.textPrimary : AppTokens.textPrimaryLight;
    final secondary =
        dark ? AppTokens.textSecondary : const Color(0xFF8E8E93);
    _showPopover(
      anchor,
      290,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
            child: Row(
              children: [
                Text('书签',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: fg)),
                const Spacer(),
                TextButton(
                  onPressed: _bookmarkCurrent,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 24),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('添加此页', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ),
          Divider(height: 1,
              color: dark ? AppTokens.divider : const Color(0xFFE5E5E5)),
          if (_bookmarks.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('暂无书签',
                  style: TextStyle(fontSize: 11, color: secondary)),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _bookmarks.length,
                itemBuilder: (context, index) {
                  final b = _bookmarks[index];
                  return InkWell(
                    onTap: () {
                      _closePopover();
                      unawaited(_navigate(b.url));
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      child: Row(
                        children: [
                          Icon(Icons.book_outlined,
                              size: 13, color: secondary),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(b.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 11.5, color: fg)),
                                Text(b.url,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 10, color: secondary)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
      maxHeight: 320,
    );
  }

  void _bookmarkCurrent() {
    final url = _pageUrl;
    if (url.isEmpty || url == 'about:blank') {
      _toast('当前没有可添加的页面');
      return;
    }
    final title = _title.isNotEmpty ? _title : url;
    setState(() {
      _bookmarks.removeWhere((b) => b.url == url);
      _bookmarks.insert(0, _Bookmark(title, url));
    });
    _closePopover();
  }

  void _showOptions(BuildContext anchor) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = dark ? AppTokens.textPrimary : AppTokens.textPrimaryLight;
    final secondary =
        dark ? AppTokens.textSecondary : const Color(0xFF8E8E93);
    _showPopover(
      anchor,
      310,
      StatefulBuilder(
        builder: (context, setLocal) {
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('选项',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: fg)),
                const SizedBox(height: 12),
                Text('User-Agent',
                    style: TextStyle(fontSize: 11, color: secondary)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _uaChip('chrome', 'Chrome', dark, setLocal),
                    _uaChip('safari', 'Safari', dark, setLocal),
                    _uaChip('mobile', 'iPhone', dark, setLocal),
                    _uaChip('default', '默认', dark, setLocal),
                  ],
                ),
                const SizedBox(height: 12),
                _toggleRow(
                  '允许弹出窗口',
                  _popupsEnabled,
                  dark,
                  (value) => setLocal(() => _popupsEnabled = value),
                ),
                _toggleRow(
                  '兼容模式',
                  _compatibility,
                  dark,
                  (value) {
                    setLocal(() => _compatibility = value);
                    _uaMode = value ? 'mobile' : 'chrome';
                    unawaited(_applyUa());
                  },
                ),
                _toggleRow(
                  '合并相关 HLS 流',
                  _mergeHls,
                  dark,
                  (value) => setLocal(() => _mergeHls = value),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 26,
                  child: FilledButton(
                    onPressed: () {
                      _closePopover();
                      unawaited(_applyUa());
                    },
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.zero,
                      textStyle: const TextStyle(fontSize: 11),
                    ),
                    child: const Text('应用'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      maxHeight: 360,
    );
  }

  Widget _uaChip(
    String value,
    String label,
    bool dark,
    StateSetter setLocal,
  ) {
    final selected = _uaMode == value;
    return GestureDetector(
      onTap: () {
        setLocal(() => _uaMode = value);
        unawaited(_applyUa());
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? _ugeAccent.withValues(alpha: dark ? 0.28 : 0.12)
              : (dark ? const Color(0xFF3A3A3A) : const Color(0xFFF0F0F0)),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: selected ? _ugeAccent : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: selected
                ? _ugeAccent
                : (dark ? AppTokens.textSecondary : const Color(0xFF3A3A3C)),
          ),
        ),
      ),
    );
  }

  Widget _toggleRow(
    String label,
    bool value,
    bool dark,
    ValueChanged<bool> onChanged,
  ) {
    return SizedBox(
      height: 28,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                color: dark ? AppTokens.textPrimary : AppTokens.textPrimaryLight,
              ),
            ),
          ),
          Transform.scale(
            scale: 0.7,
            child: Switch(
              value: value,
              onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }

  void _showHelp() {
    _closePopover();
    HelpWindow.show(context);
  }
}

// ----------------------------------------------------------------------
// Small chrome widgets
// ----------------------------------------------------------------------

class _NavButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Future<void> Function()? onTap;

  const _NavButton({
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap == null ? null : () => onTap!(),
      child: Center(child: Icon(icon, size: 17, color: color)),
    );
  }
}

class _ChromeIcon extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final double size;
  final Color color;
  final VoidCallback? onTap;

  const _ChromeIcon({
    required this.icon,
    required this.tooltip,
    required this.size,
    required this.color,
    this.onTap,
  });

  @override
  State<_ChromeIcon> createState() => _ChromeIconState();
}

class _ChromeIconState extends State<_ChromeIcon> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _hover
                  ? (Theme.of(context).brightness == Brightness.dark
                      ? AppTokens.hover
                      : const Color(0x0D000000))
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Icon(widget.icon, size: widget.size, color: widget.color),
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final bool active;
  final int? badge;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
    this.active = false,
    this.badge,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            width: 36,
            height: 28,
            decoration: BoxDecoration(
              color: widget.active
                  ? _ugeAccent.withValues(alpha: dark ? 0.22 : 0.10)
                  : (_hover
                      ? (dark
                          ? AppTokens.hover
                          : const Color(0x0D000000))
                      : Colors.transparent),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Stack(
              children: [
                Center(
                  child: Icon(widget.icon, size: 16, color: widget.color),
                ),
                if (widget.badge != null && widget.badge! > 0)
                  Positioned(
                    right: 2,
                    top: 2,
                    child: Container(
                      constraints:
                          const BoxConstraints(minWidth: 12, minHeight: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: _ugeAccent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        widget.badge! > 99 ? '99+' : '${widget.badge}',
                        style: const TextStyle(
                          fontSize: 8,
                          height: 1.1,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WinCaption extends StatefulWidget {
  final IconData icon;
  final Color color;
  final Color? hover;
  final double height;
  final VoidCallback onTap;

  const _WinCaption({
    required this.icon,
    required this.color,
    required this.onTap,
    this.hover,
    this.height = 28,
  });

  @override
  State<_WinCaption> createState() => _WinCaptionState();
}

class _WinCaptionState extends State<_WinCaption> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Container(
          width: 42,
          height: widget.height,
          color: _hover
              ? (widget.hover ?? (dark ? AppTokens.hover : const Color(0x0D000000)))
              : Colors.transparent,
          alignment: Alignment.center,
          child: Icon(
            widget.icon,
            size: 12,
            color: _hover && widget.hover != null ? Colors.white : widget.color,
          ),
        ),
      ),
    );
  }
}

class _SidebarButton extends StatefulWidget {
  final String label;
  final bool dark;
  final bool enabled;
  final VoidCallback onTap;

  const _SidebarButton({
    required this.label,
    required this.dark,
    required this.enabled,
    required this.onTap,
  });

  @override
  State<_SidebarButton> createState() => _SidebarButtonState();
}

class _SidebarButtonState extends State<_SidebarButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final dark = widget.dark;
    final fg = widget.enabled
        ? (dark ? AppTokens.textPrimary : AppTokens.textPrimaryLight)
        : (dark ? AppTokens.textTertiary : const Color(0xFFB0B0B5));
    final bg = dark
        ? (widget.enabled ? const Color(0xFF3A3A3A) : const Color(0xFF2A2A2A))
        : (widget.enabled
            ? (_hover ? Colors.white : const Color(0xFFF7F7F7))
            : const Color(0xFFE4E4E4));
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.enabled ? widget.onTap : null,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Container(
          height: 22,
          constraints: const BoxConstraints(minWidth: 52),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: dark ? const Color(0xFF474747) : const Color(0xFFD1D1D6),
            ),
          ),
          child: Text(widget.label,
              style: TextStyle(fontSize: 11, color: fg)),
        ),
      ),
    );
  }
}

class _UgeRow extends StatefulWidget {
  final _CapturedItem item;
  final bool dark;
  final bool added;
  final bool adding;
  final bool showAdd;
  final String subtitle;
  final VoidCallback onAdd;

  const _UgeRow({
    super.key,
    required this.item,
    required this.dark,
    required this.added,
    required this.adding,
    required this.showAdd,
    required this.subtitle,
    required this.onAdd,
  });

  @override
  State<_UgeRow> createState() => _UgeRowState();
}

class _UgeRowState extends State<_UgeRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final dark = widget.dark;
    final fg = dark ? AppTokens.textPrimary : AppTokens.textPrimaryLight;
    final secondary =
        dark ? AppTokens.textSecondary : const Color(0xFF6E6E73);
    final tertiary =
        dark ? AppTokens.textTertiary : const Color(0xFF8E8E93);
    final divider = dark ? AppTokens.divider : const Color(0xFFE5E5E5);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: _hover
              ? (dark ? const Color(0x14FFFFFF) : const Color(0x0A000000))
              : Colors.transparent,
          border: Border(bottom: BorderSide(color: divider)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(11, 4, 4, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: widget.added ? tertiary : fg,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10.5, color: secondary),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      widget.item.host,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10, color: tertiary),
                    ),
                  ],
                ),
              ),
            ),
            if (widget.showAdd)
              SizedBox(
                width: 27,
                child: Center(
                  child: widget.adding
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: _ugeAccent,
                          ),
                        )
                      : GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: widget.added ? null : widget.onAdd,
                          child: Icon(
                            widget.added
                                ? Icons.check_circle
                                : Icons.add_circle_outline,
                            size: 16,
                            color: widget.added ? tertiary : _ugeAccent,
                          ),
                        ),
                ),
              )
            else
              const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

class _ImageTile extends StatefulWidget {
  final _CapturedItem item;
  final bool dark;

  const _ImageTile({required this.item, required this.dark});

  @override
  State<_ImageTile> createState() => _ImageTileState();
}

class _ImageTileState extends State<_ImageTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final dark = widget.dark;
    final secondary =
        dark ? AppTokens.textSecondary : const Color(0xFF6E6E73);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF2A2A2A) : Colors.white,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: _hover
                ? _ugeAccent.withValues(alpha: 0.5)
                : (dark ? AppTokens.divider : const Color(0xFFE0E0E0)),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Image.network(
                widget.item.url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Center(
                  child: Icon(Icons.image_not_supported_outlined,
                      size: 22, color: secondary),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: dark
                          ? AppTokens.textPrimary
                          : AppTokens.textPrimaryLight,
                    ),
                  ),
                  Text(
                    [
                      if (widget.item.width > 0)
                        '${widget.item.width}×${widget.item.height}',
                      if (widget.item.bytes != null)
                        _formatBytesStatic(widget.item.bytes!),
                    ].join(' • '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 9.5, color: secondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatBytesStatic(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '$bytes B';
}
