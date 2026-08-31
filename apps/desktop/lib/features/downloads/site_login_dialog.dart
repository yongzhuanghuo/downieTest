import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../core/platform/webview2.dart';
import '../../core/storage/settings_storage.dart';
import '../../core/storage/site_cookies.dart';
import '../../core/storage/site_registry.dart';

/// 站点登录弹窗（通用）
///
/// 内置浏览器打开 [SiteConfig.loginUrl]，用户登录后点「完成登录」，
/// 抓取该站 cookie 存成 cookies/{siteId}.txt。
class SiteLoginDialog extends StatefulWidget {
  final SiteConfig site;
  final WebViewEnvironment? environment;

  const SiteLoginDialog({super.key, required this.site, this.environment});

  /// 弹出登录框；返回 true 表示登录成功并已保存 cookie
  static Future<bool> show(BuildContext context, SiteConfig site) async {
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
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SiteLoginDialog(site: site, environment: env),
    );
    return ok ?? false;
  }

  @override
  State<SiteLoginDialog> createState() => _SiteLoginDialogState();
}

class _SiteLoginDialogState extends State<SiteLoginDialog> {
  bool _saving = false;
  bool _loginDetected = false;
  bool _webView2Missing = false;
  InAppWebViewController? _controller;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    // Windows 没装 WebView2 会空白，这里先检测，缺了就提示
    final available = isWebView2Available();
    _webView2Missing = !available;
    debugPrint('[登录] WebView2 可用: $available');
    if (!_webView2Missing) {
      _startLoginPolling();
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _finish() async {
    setState(() => _saving = true);
    try {
      // Windows 上必须传 webViewEnvironment，否则 CookieManager 报 Cannot obtain the WebViewEnvironment
      final allCookies = await CookieManager.instance(
        webViewEnvironment: widget.environment,
      ).getCookies(url: WebUri(widget.site.loginUrl));
      // 登录页里的第三方 iframe 会把别站（YouTube/Netflix 等）的 cookie 也带进来，
      // 按站点域名过滤掉，避免串台。
      final cookies = _filterSiteCookies(allCookies);
      debugPrint(
          '[登录] ${widget.site.name} 抓到 ${allCookies.length} 条（过滤后 ${cookies.length} 条）');
      for (final c in cookies) {
        debugPrint('[登录]   cookie: ${c.name} @ ${c.domain}');
      }
      if (cookies.isEmpty) {
        debugPrint('[登录] ⚠️ 抓到 0 条 cookie —— 很可能没在页面里真正登录！');
      }
      // 检测是否有登录态 cookie（抖音 sessionid / YouTube SID / B站 SESSDATA 等）
      final hasLogin = _hasLoginCookie(cookies);
      if (!hasLogin) {
        debugPrint('[登录] ⚠️ 没发现登录 cookie，可能没真正登录');
        if (mounted) {
          setState(() {
            _saving = false;
            _loginDetected = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('还没登录成功，请先在页面里登录账号（看到头像/昵称）再点完成'),
            ),
          );
          _startLoginPolling(); // 重新监听登录态
        }
        return; // 不关闭弹窗，让用户继续登录
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
          debugPrint(
              '[登录] ✅ 抓到 msToken（${msToken.length} 字符），补进 cookie');
          await _appendMsToken(msToken);
        } else {
          debugPrint('[登录] ⚠️ 没抓到 msToken，抖音解析可能仍报 Fresh cookies');
        }
      } else {
        debugPrint('[登录] ${widget.site.name}（id=${widget.site.id}）非抖音，'
            '跳过 msToken 抓取，不影响其他站点');
      }

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存 Cookie 失败：$e')),
        );
      }
    }
  }

  /// 定时检测页面是否已登录，登录后解锁「完成登录」按钮
  void _startLoginPolling() {
    _pollTimer?.cancel();
    _pollTimer =
        Timer.periodic(const Duration(seconds: 2), (_) => _detectLogin());
  }

  /// 抓 cookie 判断是否有登录态；检测到后解锁按钮并停止轮询
  Future<void> _detectLogin() async {
    if (_loginDetected || _saving) return;
    final c = _controller;
    if (c == null) return;
    try {
      final allCookies = await CookieManager.instance(
        webViewEnvironment: widget.environment,
      ).getCookies(url: WebUri(widget.site.loginUrl));
      final cookies = _filterSiteCookies(allCookies);
      if (_hasLoginCookie(cookies) && mounted) {
        debugPrint('[登录] ✅ 检测到登录态，解锁「完成登录」');
        setState(() => _loginDetected = true);
        _pollTimer?.cancel();
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

  /// 只保留属于当前站点的 cookie，过滤掉登录页里第三方 iframe 带进来的别站 cookie。
  /// cookie 的 domain 可能是 `.douyin.com` / `douyin.com` / `www.douyin.com`，
  /// 统一去掉前导点后按「等于目标域 或 是其子域」匹配。
  List<Cookie> _filterSiteCookies(List<Cookie> cookies) {
    final raw = widget.site.cookieDomain;
    final target =
        (raw.startsWith('.') ? raw.substring(1) : raw).toLowerCase();
    return cookies.where((c) {
      final d = (c.domain ?? '').toLowerCase();
      if (d.isEmpty) return false;
      final norm = d.startsWith('.') ? d.substring(1) : d;
      return norm == target || norm.endsWith('.$target');
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
      final raw = (await c.evaluateJavascript(source: script))?.toString() ?? '';
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
      debugPrint('[Cookie] 验证：文件共 ${lines.length} 行，msToken 行数=${msLines.length}'
          '，msToken 值长度=${msLines.isEmpty ? 0 : msLines.first.length}');
    } catch (e) {
      debugPrint('[Cookie] 追加 msToken 失败: $e');
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      child: SizedBox(
        width: 900,
        height: 650,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: theme.dividerColor)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.login, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '登录 ${widget.site.name}',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: '取消',
                    onPressed: () => Navigator.of(context).pop(false),
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
                          URLRequest(url: WebUri(widget.site.loginUrl)),
                      initialSettings:
                          InAppWebViewSettings(javaScriptEnabled: true),
                      onWebViewCreated: (controller) {
                        _controller = controller;
                        debugPrint('[登录] webview 已创建');
                      },
                      onLoadStart: (controller, url) {
                        debugPrint('[登录] 开始加载: $url');
                      },
                      onLoadStop: (controller, url) {
                        debugPrint('[登录] 加载完成: $url');
                        _detectLogin();
                      },
                      onReceivedError: (controller, request, error) {
                        debugPrint('[登录] 加载错误: ${error.description}');
                      },
                    ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: theme.dividerColor)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '先在页面里登录账号（扫码/短信），登录成功后点「完成登录」',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: (_saving || _webView2Missing || !_loginDetected)
                        ? null
                        : _finish,
                    icon: (_saving || !_loginDetected)
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: Text(
                      _saving
                          ? '保存中...'
                          : _loginDetected
                              ? '完成登录'
                              : '等待登录...',
                    ),
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
