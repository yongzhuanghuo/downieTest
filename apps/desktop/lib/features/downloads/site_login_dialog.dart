import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../core/engine/douyin_parser.dart';
import '../../core/platform/webview2.dart';
import '../../core/platform/window_close_coordinator.dart';
import '../../core/storage/settings_storage.dart';
import '../../core/storage/site_cookies.dart';
import '../../core/storage/site_registry.dart';
import '../../shared/theme/design_tokens.dart';

/// 站点登录弹窗（通用）
///
/// 内置浏览器打开 [SiteConfig.loginUrl]，用户登录后点「完成登录」，
/// 抓取该站 cookie 存成 cookies/{siteId}.txt。
class SiteLoginDialog extends StatefulWidget {
  final SiteConfig site;
  final WebViewEnvironment? environment;

  /// 需要登录的原始页面；为空时打开站点首页。
  final String? initialUrl;

  const SiteLoginDialog({
    super.key,
    required this.site,
    this.environment,
    this.initialUrl,
  });

  /// 弹出登录框；返回 true 表示登录成功并已保存 cookie
  static Future<bool> show(
    BuildContext context,
    SiteConfig site, {
    String? initialUrl,
  }) async {
    // 安装版装在 Program Files（只读），WebView2 默认在 exe 旁建用户数据目录会失败导致白屏。
    // 把用户数据目录指到可写的 AppData，修复安装版白屏。
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
        debugPrint('[登录] WebView2 环境创建失败: $e');
      }
    }
    // 不用 showDialog：它的缩放转场会让 macOS 平台视图（WKWebView）
    // 的点击坐标偏移，表现为页面能看但按钮点不动。这里只做淡入。
    final ok = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierLabel: '登录',
      barrierColor: Colors.transparent,
      transitionDuration: Duration.zero,
      pageBuilder: (_, __, ___) => Center(
        child: SiteLoginDialog(
          site: site,
          environment: env,
          initialUrl: initialUrl,
        ),
      ),
      transitionBuilder: (_, __, ___, child) => child,
    );
    return ok ?? false;
  }

  @override
  State<SiteLoginDialog> createState() => _SiteLoginDialogState();
}

class _SiteLoginDialogState extends State<SiteLoginDialog> {
  bool _saving = false;
  bool _closing = false;
  bool _loginDetected = false;
  bool _webView2Missing = false;
  bool _pageLoading = true;
  InAppWebViewController? _controller;
  Timer? _pollTimer;
  Timer? _douyinProbeTimer;
  bool _probingDouyin = false;
  bool _douyinReady = false;
  bool _finishPending = false;
  int _douyinProbes = 0;
  String? _douyinStatus;
  String _douyinVideoUrl = '';
  String _douyinAudioUrl = '';
  int _douyinVideoHeight = 0;
  String _currentPageTitle = '';
  bool _reloadedAfterLogin = false;
  String _currentPageUrl = '';

  String get _loginUrl => widget.initialUrl ?? widget.site.loginUrl;

  /// 抖音等站点会按 UA 返回不同的登录页；用桌面 Chrome UA 才能出现
  /// 短信/扫码等完整控件。
  static const String _chromeUA =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/126.0.0.0 Safari/537.36';

  /// Google 会拒绝「嵌入式 Chrome」登录（“此浏览器或应用可能不安全”）。
  /// WKWebView 本身就是 Safari 内核，登录窗口默认改用 Safari UA；
  /// Downie 的 XULoginHelper 也是用 Safari UA 打开登录页。
  static const String _safariUA =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) '
      'Version/26.0 Safari/605.1.15';

  static const String _edgeUA =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/126.0.0.0 Safari/537.36 Edg/126.0.0.0';

  String get _loginUserAgent {
    // 抖音必须用 Chrome UA 才出完整登录控件；其余站点用平台原生浏览器 UA，
    // 避免 Google 把登录窗口识别成不安全的嵌入式浏览器。
    if (widget.site.id == 'douyin') return _chromeUA;
    return Platform.isMacOS ? _safariUA : _edgeUA;
  }

  /// 抖音登录页会自己请求 aweme/detail；截获后可直接拿到视频数据，
  /// 不再依赖登录后的 HTTP 签名/风控。
  static const String _douyinHook = r'''
(function () {
  if (window.__downie6AwemeHook) return;
  window.__downie6AwemeHook = true;
  function isAweme(url) {
    var u = String(url || '');
    return u.indexOf('aweme/detail') >= 0 ||
           u.indexOf('aweme/post') >= 0;
  }
  function pageAwemeId() {
    var m = String(location.pathname || '').match(/\/(?:video|note|vsdetail)\/(\d+)/);
    return m ? m[1] : '';
  }
  function urlAwemeId(url) {
    var m = String(url || '').match(/[?&]aweme_id=(\d+)/);
    return m ? m[1] : '';
  }
  function put(url, text) {
    try {
      var u = String(url || '');
      if (!text || !isAweme(u)) return;
      var pageId = pageAwemeId();
      var urlId = urlAwemeId(u);
      // 详情页会预取相关视频；只认当前视频的 aweme_id，避免缓存串片。
      if (u.indexOf('aweme/detail') >= 0) {
        if (pageId && urlId && pageId !== urlId) return;
      } else if (u.indexOf('aweme/post') >= 0) {
        // aweme/post 只是兜底，不能覆盖已经抓到的 detail
        if (window.__downie6_aweme) return;
        if (pageId && urlId && pageId !== urlId) return;
      } else {
        return;
      }
      window.__downie6_aweme = text;
      window.__downie6_awemeUrl = u;
      window.__downie6_awemeAt = Date.now();
    } catch (e) {}
  }
  function xhrBody(xhr) {
    try {
      var rt = xhr.responseType;
      if (!rt || rt === 'text') return xhr.responseText;
      if (rt === 'json') return JSON.stringify(xhr.response);
    } catch (e) {}
    return '';
  }
  var of = window.fetch;
  if (of) {
    window.fetch = function () {
      var args = arguments;
      var u = (typeof args[0] === 'string') ? args[0] : (args[0] && args[0].url);
      return of.apply(this, args).then(function (resp) {
        try {
          if (isAweme(u)) {
            resp.clone().text().then(function (t) { put(u, t); }).catch(function(){});
          }
        } catch (e) {}
        return resp;
      });
    };
  }
  var oo = XMLHttpRequest.prototype.open;
  var os = XMLHttpRequest.prototype.send;
  var osh = XMLHttpRequest.prototype.setRequestHeader;
  XMLHttpRequest.prototype.open = function (m, u) {
    this.__downie6Url = u;
    return oo.apply(this, arguments);
  };
  XMLHttpRequest.prototype.setRequestHeader = function (name, value) {
    try {
      if (String(name).toLowerCase() === 'uifid') {
        window.__downie6_uifid = String(value);
      }
    } catch (e) {}
    return osh.apply(this, arguments);
  };
  XMLHttpRequest.prototype.send = function () {
    var self = this;
    this.addEventListener('load', function () {
      put(self.__downie6Url, xhrBody(self));
    });
    return os.apply(this, arguments);
  };
})();
''';

  @override
  void initState() {
    super.initState();
    WindowCloseCoordinator.instance.push(this, _close);
    // Windows 没装 WebView2 会空白，这里先检测，缺了就提示
    final available = isWebView2Available();
    _webView2Missing = !available;
    if (_webView2Missing) _pageLoading = false;
    debugPrint('[登录] WebView2 可用: $available');
    if (!_webView2Missing) {
      _startLoginPolling();
    }
  }

  @override
  void dispose() {
    WindowCloseCoordinator.instance.pop(this);
    _pollTimer?.cancel();
    _douyinProbeTimer?.cancel();
    super.dispose();
  }

  /// Cmd+W / 系统关闭只关登录窗口，不关主窗口。
  void _close() {
    if (_closing || !mounted) return;
    _closing = true;
    Navigator.of(context).pop(false);
  }

  Future<void> _finish() async {
    setState(() => _saving = true);
    try {
      if (widget.site.id == 'douyin') {
        // Downie 的登录浏览器会一直监听 aweme/detail / 媒体资源，等页面真正
        // 拿到视频数据才结束。WKWebView 里这个请求可能要 30 秒左右才发出，
        // 用户登录后立刻点 ✓ 也必须继续等，不能只等几秒就放弃。
        if (mounted) {
          setState(() => _douyinStatus = '正在获取视频信息…');
        }
        await _waitForDouyin();
        if (!mounted) return;
        final ready = _hasCachedDouyin;
        if (!ready && _cacheDouyinMediaFallback()) {
          debugPrint('[登录] 抖音使用媒体资源兜底（视频+音频分轨）');
        }
        if (!_hasCachedDouyin) {
          _finishPending = true;
          if (mounted) {
            setState(() {
              _saving = false;
              _douyinStatus = '仍在获取视频信息…拿到后会自动继续';
            });
          }
          debugPrint('[登录] 抖音仍未拿到视频数据，保持登录窗口继续监听');
          return;
        }
        debugPrint('[登录] 抖音缓存状态: true');
        if (mounted) {
          setState(() => _douyinStatus = '正在保存登录状态…');
        }
      }
      // Windows 上必须传 webViewEnvironment，否则 CookieManager 报 Cannot obtain the WebViewEnvironment
      final cookies = await _collectCookies();
      debugPrint('[登录] ${widget.site.name} 抓到 ${cookies.length} 条站点 cookie');
      for (final c in cookies) {
        debugPrint('[登录]   cookie: ${c.name} @ ${c.domain}');
      }
      if (widget.site.id == 'douyin') {
        final hasUifid = cookies.any((c) => c.name.toUpperCase() == 'UIFID');
        debugPrint(
          '[登录] 抖音 UIFID cookie: ${hasUifid ? '✓' : '×（等待页面安全 SDK 写入）'}',
        );
      }
      if (cookies.isEmpty) {
        debugPrint('[登录] ⚠️ 抓到 0 条 cookie，无法继续');
        if (mounted) {
          setState(() {
            _saving = false;
            _loginDetected = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('没有抓到任何 Cookie，请等页面加载完或先登录再点完成')),
          );
          _startLoginPolling();
        }
        return;
      }
      // Downie 的登录窗只要页面有 Cookie 就允许点 Done（“Consider Logged In”），
      // 不强制要求识别到登录态 cookie。YouTube 的 bot 检查页就是这种情况：
      // 没登录但已有访客 Cookie，直接用这些 Cookie 重试往往就能过。
      final hasLogin = _hasLoginCookie(cookies);
      if (!hasLogin) {
        debugPrint(
          '[登录] 没发现登录 cookie，但已有 ${cookies.length} 条站点 cookie，按 Downie 行为继续',
        );
      }
      await SiteCookies.saveCookies(widget.site.id, cookies);

      // ---------- 补抓 msToken（抖音反爬核心） ----------
      // 抖音的 msToken 存在 localStorage（key 通常是 xmst），不在 cookie 里；
      // yt-dlp 抖音提取器会检查 cookie 里的 msToken，缺失就报
      // "Fresh cookies (not necessarily logged in) are needed"。
      // 登录态 cookie 再全，没 msToken 也会被拒，所以这里从 localStorage
      // 抓出来，追加一行成 cookie 写进文件。仅抖音需要，其他站点跳过。
      if (widget.site.id == 'douyin') {
        debugPrint('[登录] 抖音站点 → 尝试补抓 msToken');
        final msToken = await _extractMsToken();
        if (msToken != null && msToken.isNotEmpty) {
          debugPrint('[登录] ✅ 抓到 msToken（${msToken.length} 字符），补进 cookie');
          await _appendMsToken(msToken);
        } else {
          debugPrint('[登录] ⚠️ 没抓到 msToken，抖音解析可能仍报 Fresh cookies');
        }
        // Argus 风控会检查 UIFID；浏览器通常把它放在 localStorage，
        // 而不是 cookie。登录完成后补进 cookie 文件，HTTP 解析时再带成 header。
        await _appendStorageCookies(const [
          'UIFID',
          'uifid',
          'UIFID_TEMP',
          'webid',
          's_v_web_id',
        ]);
      } else {
        debugPrint(
          '[登录] ${widget.site.name}（id=${widget.site.id}）非抖音，'
          '跳过 msToken 抓取，不影响其他站点',
        );
      }

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存 Cookie 失败：$e')));
      }
    }
  }

  /// 定时检测页面是否已登录，登录后解锁「完成登录」按钮
  void _startLoginPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _detectLogin(),
    );
  }

  /// 抓 cookie 判断是否有登录态 / 是否已有站点 Cookie。
  ///
  /// Downie 的按钮在「Has Cookie」时就会解锁；我们同样让有 Cookie 就能点，
  /// 不要求一定识别到 session/sid 这类登录态。
  Future<void> _detectLogin() async {
    if (_loginDetected || _saving) return;
    final c = _controller;
    if (c == null) return;
    try {
      final cookies = await _collectCookies();
      final hasLogin = _hasLoginCookie(cookies);
      if (!mounted) return;
      if (hasLogin && !_loginDetected) {
        setState(() => _loginDetected = true);
        debugPrint('[登录] ✅ 检测到登录态');
        _pollTimer?.cancel();
        _startDouyinCapture();
        _maybeReloadAfterLogin();
      }
    } catch (e) {
      debugPrint('[登录] 检测登录态失败: $e');
    }
  }

  /// 判断 cookie 里是否有登录态（抖音 sessionid / YouTube SID / B站 SESSDATA 等）
  bool _hasLoginCookie(List<Cookie> cookies) {
    return cookies.any((c) {
      final n = c.name.toLowerCase();
      return n.contains('session') ||
          n.contains('sid') ||
          n.contains('sess') ||
          n.contains('login');
    });
  }

  /// 抓取站点主域 + 额外域名的 cookie。
  ///
  /// YouTube 的登录态分散在 `.youtube.com` 和 `.google.com`，只读原视频
  /// URL（youtu.be）会漏掉登录 cookie；这里对每个域名都取一次再合并。
  Future<List<Cookie>> _collectCookies() async {
    final manager = CookieManager.instance(
      webViewEnvironment: widget.environment,
    );
    final urls = <String>{_loginUrl};
    for (final raw in widget.site.allCookieDomains) {
      final bare = (raw.startsWith('.') ? raw.substring(1) : raw).toLowerCase();
      urls.add('https://www.$bare/');
    }
    final merged = <String, Cookie>{};
    for (final url in urls) {
      try {
        final all = await manager.getCookies(url: WebUri(url));
        for (final c in _filterSiteCookies(all)) {
          merged['${c.name}|${c.domain}|${c.path}'] = c;
        }
      } catch (e) {
        debugPrint('[登录] 抓取 $url cookie 失败: $e');
      }
    }
    return merged.values.toList();
  }

  /// 只保留属于当前站点的 cookie，过滤掉登录页里第三方 iframe 带进来的别站 cookie。
  /// cookie 的 domain 可能是 `.douyin.com` / `douyin.com` / `www.douyin.com`，
  /// 统一去掉前导点后按「等于目标域 或 是其子域」匹配。
  List<Cookie> _filterSiteCookies(List<Cookie> cookies) {
    final targets = widget.site.allCookieDomains
        .map((d) => (d.startsWith('.') ? d.substring(1) : d).toLowerCase())
        .toList();
    return cookies.where((c) {
      final d = (c.domain ?? '').toLowerCase();
      if (d.isEmpty) return false;
      final norm = d.startsWith('.') ? d.substring(1) : d;
      return targets.any(
        (target) => norm == target || norm.endsWith('.$target'),
      );
    }).toList();
  }

  /// 从 WebView 的 localStorage 抓抖音 msToken
  ///
  /// 抖音把 msToken 存在 localStorage，key 通常是 `xmst`（也可能 `msToken`）。
  /// 探测多个 key，都找不到时返回 null 并在日志里列出所有 key 名方便排查。
  Future<String?> _extractMsToken() async {
    final c = _controller;
    if (c == null) return null;
    final script = r'''
      JSON.stringify((() => {
        try {
          const keys = ['xmst', 'msToken', 'ms_token'];
          for (const k of keys) {
            const v = localStorage.getItem(k);
            if (v && v.length > 10) return {found: k, token: v};
          }
          const all = [];
          for (let i = 0; i < localStorage.length; i++) all.push(localStorage.key(i));
          return {found: null, token: null, keys: all};
        } catch (e) {
          return {found: null, token: null, keys: ['__js_error__']};
        }
      })())
    ''';
    try {
      final raw =
          (await c.evaluateJavascript(source: script))?.toString() ?? '';
      // evaluateJavascript 对字符串返回值可能带 JSON 引号，去掉后再解析
      final jsonStr = raw.startsWith('"') && raw.endsWith('"')
          ? raw.substring(1, raw.length - 1)
          : raw;
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final found = map['found'] as String?;
      final token = map['token'] as String?;
      if (found != null) {
        debugPrint('[登录] msToken 的 localStorage key = $found');
      } else {
        final keys = (map['keys'] as List?)?.join(', ') ?? '';
        debugPrint('[登录] localStorage 键: $keys');
      }
      return token;
    } catch (e) {
      debugPrint('[登录] 读 localStorage 失败: $e');
      return null;
    }
  }

  /// 把 msToken 追加一行到 cookie 文件（Netscape 格式，等价于一个 cookie）
  Future<void> _appendMsToken(String token) async {
    try {
      final f = await SiteCookies.cookieFile(widget.site.id);
      final line =
          '${widget.site.cookieDomain}\tTRUE\t/\tFALSE\t0\tmsToken\t$token\n';
      await File(f.path).writeAsString(line, mode: FileMode.append);
      // 读回文件验证写入成功（含行数、是否真的有 msToken 行）
      final lines = await File(f.path).readAsLines();
      final msLines = lines.where((l) => l.contains('\tmsToken\t')).toList();
      debugPrint('[Cookie] 已追加 msToken 到 ${f.path}');
      debugPrint(
        '[Cookie] 验证：文件共 ${lines.length} 行，msToken 行数=${msLines.length}'
        '，msToken 值长度=${msLines.isEmpty ? 0 : msLines.first.length}',
      );
    } catch (e) {
      debugPrint('[Cookie] 追加 msToken 失败: $e');
    }
  }

  /// 登录后如果页面停在首页，再打开一次短链；如果已经在视频页，
  /// 不要打断页面自己的 aweme/detail 请求。
  void _maybeReloadAfterLogin() {
    if (widget.site.id != 'douyin' ||
        !_loginDetected ||
        _reloadedAfterLogin ||
        _pageLoading) {
      return;
    }
    final onVideoPage = RegExp(
      r'/(?:video|note)/\d+',
    ).hasMatch(_currentPageUrl);
    _reloadedAfterLogin = true;
    if (onVideoPage) return;
    final controller = _controller;
    if (controller == null) return;
    debugPrint('[登录] 登录后重开短链: $_loginUrl');
    unawaited(
      controller.loadUrl(urlRequest: URLRequest(url: WebUri(_loginUrl))),
    );
  }

  /// 页面加载后持续轮询。抖音的 aweme/detail 可能比页面 onLoadStop 晚
  /// 30 秒左右才发出（要先过验证、加载播放器 bundle），所以不能只探测几次。
  void _startDouyinCapture() {
    if (widget.site.id != 'douyin' || _douyinReady) return;
    _douyinProbeTimer?.cancel();
    unawaited(_probeDouyin());
    _douyinProbeTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) {
      if (!mounted || _douyinReady) {
        _douyinProbeTimer?.cancel();
        return;
      }
      unawaited(_probeDouyin());
    });
  }

  bool get _hasCachedDouyin {
    if (DouyinParser.cachedVideo(_loginUrl) != null) return true;
    final initial = widget.initialUrl;
    if (initial != null && DouyinParser.cachedVideo(initial) != null) {
      return true;
    }
    return _currentPageUrl.isNotEmpty &&
        DouyinParser.cachedVideo(_currentPageUrl) != null;
  }

  /// 等待 aweme/detail 响应；用户点 ✓ 后最多等 75 秒，超时后保持窗口
  /// 继续监听，一旦拿到数据会自动再次执行完成流程。
  Future<void> _waitForDouyin() async {
    _startDouyinCapture();
    final deadline = DateTime.now().add(const Duration(seconds: 75));
    var lastStatus = DateTime.now();
    while (mounted && DateTime.now().isBefore(deadline)) {
      if (_hasCachedDouyin) return;
      await _probeDouyin(verbose: false);
      if (_hasCachedDouyin) return;
      if (DateTime.now().difference(lastStatus).inSeconds >= 10) {
        lastStatus = DateTime.now();
        if (mounted) {
          setState(() => _douyinStatus = '正在获取视频信息…页面首次加载可能需要 30 秒');
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }

  /// 读取登录 WebView 截获的 aweme/detail，写入解析缓存。
  Future<void> _probeDouyin({bool verbose = false}) async {
    if (widget.site.id != 'douyin') return;
    final c = _controller;
    if (c == null || _probingDouyin) return;
    _probingDouyin = true;
    try {
      final raw =
          (await c.evaluateJavascript(
            source: r'''
        JSON.stringify((() => {
          const out = {
            href: location.href,
            data: window.__downie6_aweme || '',
            hook: !!window.__downie6AwemeHook,
            uifid: (window.__downie6_uifid || '').length,
            title: document.title || '',
            height: 0,
            detail: '',
            media: []
          };
          try {
            const entries = performance.getEntriesByType('resource')
              .map(e => e.name);
            const details = entries.filter(
              u => /aweme\/(detail|post)|replay_list/.test(u));
            if (details.length) out.detail = details[details.length - 1];
            out.media = Array.from(new Set(entries.filter(
              u => /\/media-(video|audio)-/.test(u)))).slice(0, 16);
          } catch (e) {}
          try {
            const videos = Array.from(document.querySelectorAll('video'));
            videos.sort((a, b) =>
              (b.videoWidth * b.videoHeight) - (a.videoWidth * a.videoHeight));
            const v = videos[0];
            if (v) {
              out.height = v.videoHeight || 0;
              if (v.paused) v.play().catch(function(){});
            }
          } catch (e) {}
          return out;
        })())
      ''',
          )).toString() ??
          '';
      final map = jsonDecode(_unwrap(raw)) as Map<String, dynamic>;
      _douyinProbes++;
      final data = (map['data'] as String?) ?? '';
      final href = (map['href'] as String?) ?? '';
      final title = (map['title'] as String?) ?? '';
      final detail = (map['detail'] as String?) ?? '';
      final height = (map['height'] as num?)?.toInt() ?? 0;
      final media = (map['media'] as List?)?.cast<String>() ?? const <String>[];
      if (title.isNotEmpty) _currentPageTitle = title;
      if (height > 0) _douyinVideoHeight = height;
      if (height > 0) {
        for (final u in media) {
          // 锁定第一对分轨：相关视频预览会晚于主视频发请求，取最后一个
          // 可能拿到别的视频。主视频的请求总是最先出现。
          if (u.contains('/media-video-') && _douyinVideoUrl.isEmpty) {
            _douyinVideoUrl = u;
          }
          if (u.contains('/media-audio-') && _douyinAudioUrl.isEmpty) {
            _douyinAudioUrl = u;
          }
        }
      }
      if (data.isNotEmpty) {
        final expectedId =
            DouyinParser.pageVideoId(href) ??
            DouyinParser.pageVideoId(_currentPageUrl) ??
            DouyinParser.pageVideoId(_loginUrl);
        var cached = DouyinParser.cacheCaptured(
          _loginUrl,
          data,
          expectedId: expectedId,
        );
        if (widget.initialUrl != null) {
          cached =
              DouyinParser.cacheCaptured(
                widget.initialUrl!,
                data,
                expectedId: expectedId,
              ) ||
              cached;
        }
        if (href.isNotEmpty) {
          cached =
              DouyinParser.cacheCaptured(href, data, expectedId: expectedId) ||
              cached;
        }
        if (cached) {
          _douyinReady = true;
          _douyinProbeTimer?.cancel();
          debugPrint('[登录] ✅ 抖音数据已捕获（${data.length} 字符）');
          if (mounted) setState(() => _douyinStatus = null);
          if (_finishPending && mounted && !_saving) {
            _finishPending = false;
            unawaited(_finish());
          }
          return;
        }
        debugPrint('[登录] 抖音数据解析失败（${data.length} 字符）');
      }
      if (_finishPending && _cacheDouyinMediaFallback()) {
        _finishPending = false;
        _douyinReady = true;
        _douyinProbeTimer?.cancel();
        debugPrint('[登录] 抖音用媒体分轨兜底完成');
        if (mounted) setState(() => _douyinStatus = null);
        if (mounted && !_saving) unawaited(_finish());
        return;
      }
      if (verbose || _douyinProbes % 5 == 0) {
        debugPrint(
          '[登录] 抖音等待 #$_douyinProbes: href=$href '
          'data=${data.length} hook=${map['hook']} '
          'uifid=${map['uifid']} '
          '${detail.isNotEmpty ? 'detail=✓' : 'detail=×'} '
          'media=${media.length} title=$title',
        );
      }
      // 如果注入的 hook 没生效，补一次，后续请求仍能抓到。
      if (map['hook'] != true) {
        unawaited(c.evaluateJavascript(source: _douyinHook));
      }
    } catch (e) {
      debugPrint('[登录] 读取抖音数据失败: $e');
    } finally {
      _probingDouyin = false;
    }
  }

  /// 兜底：aweme/detail 响应始终没拿到，但播放器已经发出了视频/音频分轨
  /// （Douyin 的 media-video / media-audio），用它们下载后交给 ffmpeg 合并。
  bool _cacheDouyinMediaFallback() {
    if (_douyinVideoUrl.isEmpty || _douyinAudioUrl.isEmpty) return false;
    var ok = DouyinParser.cacheMedia(
      _currentPageUrl.isNotEmpty ? _currentPageUrl : _loginUrl,
      videoUrl: _douyinVideoUrl,
      audioUrl: _douyinAudioUrl,
      title: _currentPageTitle,
      height: _douyinVideoHeight,
    );
    ok =
        DouyinParser.cacheMedia(
          _loginUrl,
          videoUrl: _douyinVideoUrl,
          audioUrl: _douyinAudioUrl,
          title: _currentPageTitle,
          height: _douyinVideoHeight,
        ) ||
        ok;
    final initial = widget.initialUrl;
    if (initial != null) {
      ok =
          DouyinParser.cacheMedia(
            initial,
            videoUrl: _douyinVideoUrl,
            audioUrl: _douyinAudioUrl,
            title: _currentPageTitle,
            height: _douyinVideoHeight,
          ) ||
          ok;
    }
    return ok;
  }

  String _unwrap(String raw) {
    if (raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"')) {
      return raw.substring(1, raw.length - 1);
    }
    return raw;
  }

  /// 从 localStorage 找安全 token 补进 cookie 文件（已有同名 cookie 则跳过）。
  Future<void> _appendStorageCookies(List<String> keys) async {
    final c = _controller;
    if (c == null) return;
    final existing = await SiteCookies.loadCookieHeader(widget.site.id);
    final missing = keys.where((key) {
      final pattern = RegExp(
        '(?:^|;\\s*)${RegExp.escape(key)}=',
        caseSensitive: false,
      );
      return !pattern.hasMatch(existing);
    }).toList();
    if (missing.isEmpty) return;

    final keysJson = jsonEncode(missing);
    final script =
        '''
      JSON.stringify((() => {
        try {
          const out = {};
          for (const k of $keysJson) {
            const v = localStorage.getItem(k);
            if (v && v.length > 3) out[k] = v;
          }
          return out;
        } catch (e) { return {}; }
      })())
    ''';
    try {
      final raw =
          (await c.evaluateJavascript(source: script))?.toString() ?? '';
      final jsonStr = raw.startsWith('"') && raw.endsWith('"')
          ? raw.substring(1, raw.length - 1)
          : raw;
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      if (map.isEmpty) return;
      final f = await SiteCookies.cookieFile(widget.site.id);
      final buf = StringBuffer();
      map.forEach((key, value) {
        final v = value.toString();
        if (v.isEmpty) return;
        buf.writeln('${widget.site.cookieDomain}\tTRUE\t/\tFALSE\t0\t$key\t$v');
      });
      if (buf.length == 0) return;
      await File(f.path).writeAsString(buf.toString(), mode: FileMode.append);
      debugPrint('[Cookie] 已追加 localStorage token: ${map.keys.join(', ')}');
    } catch (e) {
      debugPrint('[Cookie] 追加 localStorage token 失败: $e');
    }
  }

  /// Windows 缺 WebView2 时显示的提示（引导用户去安装）
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
              '登录页需要微软 WebView2 内核才能显示，请安装后重新登录',
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

  Future<void> _showLoginInfo(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('登录浏览器'),
        content: const Text(
          '在打开的网页里完成登录或验证码。页面有 Cookie 后，右上角的 ✓ 就会变绿；'
          '即使站点没检测到登录，也可以点它保存当前 Cookie 并继续'
          '（与 Downie 的 Consider Logged In 一致）。',
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final toolbar = dark ? AppTokens.titleBar : AppTokens.titleBarLight;
    final divider = dark ? AppTokens.divider : AppTokens.dividerLight;
    final foreground = dark
        ? AppTokens.textPrimary
        : AppTokens.textPrimaryLight;
    final secondary = dark
        ? AppTokens.textSecondary
        : AppTokens.textSecondaryLight;
    final host = Uri.tryParse(widget.site.loginUrl)?.host ?? widget.site.name;
    // 与 Downie 一致：勾始终可点；没 Cookie 时点击会提示等待，而不是灰掉。
    final canFinish = !_saving && !_webView2Missing;
    final screen = MediaQuery.sizeOf(context);
    final width = (screen.width - 24).clamp(560.0, 1120.0).toDouble();
    final height = (screen.height - 24).clamp(420.0, 700.0).toDouble();

    // 不用 Dialog：Dialog 的缩放/内边距动画和裁剪层会让 macOS 上的
    // WKWebView 点击坐标错位（页面能看，按钮点不动）。这里直接用 Material。
    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: dark ? AppTokens.window : AppTokens.panelLight,
          borderRadius: BorderRadius.circular(AppRadius.window),
          border: Border.all(color: divider),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 32,
              offset: Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              height: 46,
              color: toolbar,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Row(
                children: [
                  if (Platform.isMacOS) ...[
                    _TrafficLights(onClose: _close),
                    const SizedBox(width: AppSpacing.lg),
                  ] else ...[
                    const SizedBox(width: AppSpacing.xs),
                  ],
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            '登录到 $host',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: foreground,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Tooltip(
                          message: '登录完成或页面已有 Cookie 后，点右上角 ✓ 保存并继续',
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => _showLoginInfo(context),
                            child: Icon(
                              Icons.info_outline,
                              size: 14,
                              color: secondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (_douyinStatus != null) ...[
                    Flexible(
                      child: Text(
                        _douyinStatus!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: TextStyle(fontSize: 11, color: secondary),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                  ],
                  if (_pageLoading) ...[
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 1.6),
                    ),
                    const SizedBox(width: AppSpacing.md),
                  ],
                  _LoginCheckButton(
                    enabled: canFinish,
                    saving: _saving,
                    onTap: _finish,
                  ),
                  if (!Platform.isMacOS) ...[
                    const SizedBox(width: AppSpacing.sm),
                    IconButton(
                      onPressed: _close,
                      tooltip: '关闭',
                      icon: Icon(Icons.close, size: 16, color: secondary),
                    ),
                  ],
                ],
              ),
            ),
            Divider(height: 1, color: divider),
            Expanded(
              child: ColoredBox(
                color: dark ? AppTokens.window : Colors.white,
                child: _webView2Missing
                    ? _buildWebView2Missing(theme)
                    : InAppWebView(
                        webViewEnvironment: widget.environment,
                        initialUrlRequest: URLRequest(url: WebUri(_loginUrl)),
                        initialSettings: InAppWebViewSettings(
                          javaScriptEnabled: true,
                          userAgent: _loginUserAgent,
                          javaScriptCanOpenWindowsAutomatically: true,
                          mediaPlaybackRequiresUserGesture: false,
                        ),
                        initialUserScripts: widget.site.id == 'douyin'
                            ? UnmodifiableListView<UserScript>([
                                UserScript(
                                  source: _douyinHook,
                                  injectionTime:
                                      UserScriptInjectionTime.AT_DOCUMENT_START,
                                ),
                              ])
                            : null,
                        onWebViewCreated: (controller) {
                          _controller = controller;
                          debugPrint('[登录] webview 已创建');
                        },
                        onLoadStart: (controller, url) {
                          debugPrint('[登录] 开始加载: $url');
                          if (url != null) _currentPageUrl = url.toString();
                          if (mounted && !_pageLoading) {
                            setState(() => _pageLoading = true);
                          }
                        },
                        onLoadStop: (controller, url) {
                          debugPrint('[登录] 加载完成: $url');
                          if (url != null) _currentPageUrl = url.toString();
                          if (mounted && _pageLoading) {
                            setState(() => _pageLoading = false);
                          }
                          _detectLogin();
                          _maybeReloadAfterLogin();
                          _startDouyinCapture();
                        },
                        onReceivedError: (controller, request, error) {
                          debugPrint('[登录] 加载错误: ${error.description}');
                          if (mounted && _pageLoading) {
                            setState(() => _pageLoading = false);
                          }
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrafficLights extends StatelessWidget {
  final VoidCallback onClose;

  const _TrafficLights({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _dot(const Color(0xFFFF5F57), onTap: onClose),
        const SizedBox(width: 8),
        _dot(const Color(0xFFFEBC2E)),
        const SizedBox(width: 8),
        _dot(const Color(0xFF28C840)),
      ],
    );
  }

  Widget _dot(Color color, {VoidCallback? onTap}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
      ),
    );
  }
}

class _LoginCheckButton extends StatelessWidget {
  final bool enabled;
  final bool saving;
  final VoidCallback onTap;

  const _LoginCheckButton({
    required this.enabled,
    required this.saving,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = enabled
        ? (dark ? AppTokens.success : AppTokens.successLight)
        : (dark ? const Color(0xFF3A3A3A) : const Color(0xFFE3E3E5));
    final color = enabled
        ? Colors.white
        : (dark ? AppTokens.textTertiary : AppTokens.textTertiaryLight);
    return Tooltip(
      message: enabled ? '完成登录（已有 Cookie 即可继续）' : '页面加载后可用',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 78,
          height: 30,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(15),
          ),
          alignment: Alignment.center,
          child: saving
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                )
              : Icon(Icons.check, size: 18, color: color),
        ),
      ),
    );
  }
}
