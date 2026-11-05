import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../../../data/models/format_option.dart';
import '../../../data/models/video_info.dart';
import '../../engine/douyin_downloader.dart';
import '../../platform/system_proxy.dart';
import '../../storage/settings_storage.dart';
import '../../storage/site_cookies.dart';
import '../site_plugin.dart';

/// 小红书原生插件。
///
/// 网页版笔记（包括手机分享短链跳转后的页面）会在 `<meta property="og:video">`
/// 里给出无水印视频直链；标题/封面/时长也都在 og 标签里。
/// 短链 xhslink.cn / xhslink.com 由 HTTP 客户端自动跟随 302。
class XiaohongshuPlugin extends SitePlugin {
  @override
  String get id => 'Xiaohongshu';

  @override
  String get displayName => '小红书';

  @override
  int get priority => 75;

  static const String ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/126.0.0.0 Safari/537.36';

  @override
  bool matches(Uri uri, String rawInput) {
    final host = uri.host.toLowerCase();
    return host == 'xiaohongshu.com' ||
        host.endsWith('.xiaohongshu.com') ||
        host == 'xhslink.com' ||
        host.endsWith('.xhslink.com') ||
        host == 'xhslink.cn' ||
        host.endsWith('.xhslink.cn');
  }

  @override
  Future<VideoInfo> parse(String url) async {
    http.Client? client;
    try {
      client = await _makeClient();
      final cookie = await SiteCookies.loadCookieHeader('xiaohongshu');
      final response = await client
          .get(
            Uri.parse(url),
            headers: {
              'User-Agent': ua,
              'Accept':
                  'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
              'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
              'Accept-Encoding': 'identity',
              'Connection': 'keep-alive',
              'Referer': 'https://www.xiaohongshu.com/',
              if (cookie.isNotEmpty) 'Cookie': cookie,
            },
          )
          .timeout(const Duration(seconds: 25));
      if (response.statusCode != 200) {
        throw SitePluginException(
          '小红书页面 HTTP ${response.statusCode}',
          retryable: true,
          fallbackToYtDlp: false,
        );
      }
      final resolved = response.request?.url.toString() ?? url;
      try {
        return parseHtml(
          response.body,
          pageUrl: resolved,
          hasCookie: cookie.isNotEmpty,
        );
      } on SitePluginException {
        // Dart 的 HTTP 指纹偶尔会被小红书换成登录页/首页；用系统 curl
        // 再取一次（和浏览器一致，能拿到分享短链的 302 与 og:video）。
        final fallback = await _curlFetch(url);
        if (fallback == null) rethrow;
        return parseHtml(
          fallback,
          pageUrl: resolved,
          hasCookie: cookie.isNotEmpty,
        );
      }
    } on SitePluginException {
      rethrow;
    } catch (e) {
      throw SitePluginException(
        '小红书解析失败: $e',
        retryable: true,
        fallbackToYtDlp: false,
      );
    } finally {
      client?.close();
    }
  }

  @override
  Future<String> download(PluginDownloadRequest request) async {
    try {
      return await DouyinDownloader.download(
        url: request.task.formatId,
        outputPath: request.outputPath,
        onProgress: request.onProgress,
        shouldCancel: request.shouldCancel,
        referer: 'https://www.xiaohongshu.com/',
        cookieSiteId: 'xiaohongshu',
      );
    } on DouyinDownloadException catch (e) {
      throw SitePluginException(e.message, retryable: false);
    }
  }

  /// 纯函数：从笔记 HTML 解析。独立出来便于用固定样本做单测。
  static VideoInfo parseHtml(
    String html, {
    String? pageUrl,
    bool hasCookie = false,
  }) {
    final videoUrl = _meta(html, 'og:video');
    if (videoUrl == null || videoUrl.isEmpty) {
      final looksLikeLogin =
          html.contains('登录') &&
          (html.contains('小红书') || html.contains('xiaohongshu'));
      throw SitePluginException(
        looksLikeLogin ? '小红书需要登录后才能解析，请登录小红书再试' : '小红书笔记里没有视频（可能是图片笔记）',
        retryable: true,
        requiresLogin: looksLikeLogin,
        fallbackToYtDlp: false,
      );
    }

    final title = _meta(html, 'og:title')?.trim();
    final cover = _firstCover(html);
    final duration = _parseDuration(_meta(html, 'og:videotime'));
    final resolved = pageUrl ?? 'https://www.xiaohongshu.com/';
    final noteId = RegExp(
      r'/(?:discovery/item|explore)/([0-9a-zA-Z]+)',
    ).firstMatch(resolved)?.group(1);
    final id = noteId ?? resolved.hashCode.abs().toString();

    return VideoInfo(
      url: resolved,
      title: (title == null || title.isEmpty)
          ? '小红书视频'
          : title.replaceAll(RegExp(r'\s*-\s*小红书.*$'), '').trim(),
      duration: duration,
      uploader: '',
      thumbnail: cover ?? '',
      extractor: 'Xiaohongshu',
      videoId: id,
      formats: [
        FormatOption(
          formatId: videoUrl,
          label: '原画 MP4',
          height: 0,
          ext: 'mp4',
        ),
      ],
    );
  }

  static String? _meta(String html, String property) {
    final tagRe = RegExp(
      '''<meta[^>]+(?:property|name)\\s*=\\s*["']${RegExp.escape(property)}["'][^>]*>''',
      caseSensitive: false,
    );
    for (final tagMatch in tagRe.allMatches(html)) {
      final tag = tagMatch.group(0)!;
      final content = RegExp(
        '''content\\s*=\\s*["']([^"']*)["']''',
        caseSensitive: false,
      ).firstMatch(tag);
      if (content != null) return _decodeHtml(content.group(1)!);
    }
    return null;
  }

  static String? _firstCover(String html) {
    final tagRe = RegExp(
      '''<meta[^>]+(?:property|name)\\s*=\\s*["']og:image["'][^>]*>''',
      caseSensitive: false,
    );
    String? fallback;
    for (final tagMatch in tagRe.allMatches(html)) {
      final content = RegExp(
        '''content\\s*=\\s*["']([^"']*)["']''',
        caseSensitive: false,
      ).firstMatch(tagMatch.group(0)!);
      if (content == null) continue;
      final url = _decodeHtml(content.group(1)!);
      if (url.isEmpty) continue;
      fallback ??= url;
      if (url.contains('sns-webpic') || url.contains('xhscdn.com')) {
        return url;
      }
    }
    return fallback;
  }

  static int _parseDuration(String? value) {
    if (value == null || value.isEmpty) return 0;
    final parts = value.split(':');
    if (parts.length == 2) {
      final m = int.tryParse(parts[0]) ?? 0;
      final s = int.tryParse(parts[1]) ?? 0;
      return m * 60 + s;
    }
    if (parts.length == 3) {
      final h = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts[1]) ?? 0;
      final s = int.tryParse(parts[2]) ?? 0;
      return h * 3600 + m * 60 + s;
    }
    return 0;
  }

  static String _decodeHtml(String value) => value
      .replaceAll('&amp;', '&')
      .replaceAll('&#39;', "'")
      .replaceAll('&quot;', '"')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');

  /// 用系统 curl 再取一次小红书页面。
  ///
  /// 小红书的边缘节点会按 TLS/客户端指纹返回不同的页面：同样的链接，
  /// curl 能拿到 302 和 og:video，Dart 的 HttpClient 有时只拿到登录页/首页。
  Future<String?> _curlFetch(String url) async {
    try {
      final cookieFile = await SiteCookies.cookieFile('xiaohongshu');
      final hasCookie =
          await cookieFile.exists() && await cookieFile.length() > 0;
      final configured = SettingsStorage.instance.current.proxy.trim();
      final proxy = configured.isNotEmpty
          ? SystemProxy.normalize(configured)
          : (await SystemProxy.detect() ?? '');
      final args = <String>[
        '-sS',
        '-L',
        '--max-time',
        '25',
        '-A',
        ua,
        '-H',
        'Accept: text/html,application/xhtml+xml',
        '-H',
        'Accept-Language: zh-CN,zh;q=0.9,en;q=0.8',
        '-H',
        'Accept-Encoding: identity',
        '-H',
        'Referer: https://www.xiaohongshu.com/',
        if (hasCookie) ...['-b', cookieFile.path],
        if (proxy.isNotEmpty) ...['--proxy', proxy],
        url,
      ];
      final result = await Process.run(
        Platform.isWindows ? 'curl.exe' : 'curl',
        args,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      if (result.exitCode != 0) {
        debugPrint('[小红书] curl 获取失败: ${result.stderr}');
        return null;
      }
      final body = (result.stdout as String).trim();
      return body.isEmpty ? null : body;
    } catch (e) {
      debugPrint('[小红书] curl 不可用: $e');
      return null;
    }
  }

  Future<http.Client> _makeClient() async {
    final configured = SettingsStorage.instance.current.proxy.trim();
    final proxy = configured.isNotEmpty
        ? SystemProxy.normalize(configured)
        : (await SystemProxy.detect() ?? '');
    if (proxy.isEmpty) return http.Client();
    try {
      final uri = Uri.parse(proxy);
      if (uri.scheme != 'http' && uri.scheme != 'https') {
        return http.Client();
      }
      final io = HttpClient();
      io.findProxy = (_) => 'PROXY ${uri.host}:${uri.port}';
      return IOClient(io);
    } catch (_) {
      return http.Client();
    }
  }
}
