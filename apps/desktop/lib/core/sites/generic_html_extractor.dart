import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../../data/models/format_option.dart';
import '../../data/models/video_info.dart';
import '../storage/settings_storage.dart';
import '../storage/site_cookies.dart';
import 'plugins/generic_web_plugin.dart';

/// 通用 HTML 媒体提取：在 yt-dlp 之前尝试从页面 HTML 里找媒体地址。
///
/// 覆盖三类常见页面：
/// - og:video / twitter:player:stream
/// - <video src> / <source src>
/// - JSON-LD contentUrl / 脚本里的 m3u8/mpd/mp4 地址
///
/// 这是 yt-dlp 和用户自定义视频提取之外的第三层兜底，不依赖站点专用 API。
class GenericHtmlExtractor {
  GenericHtmlExtractor._();

  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

  static Future<VideoInfo?> tryParse(String pageUrl) async {
    final uri = Uri.tryParse(pageUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;

    http.Client? client;
    try {
      final cookie = await SiteCookies.loadCookieHeaderForUrl(pageUrl);
      client = await _createClient();
      final response = await client.get(
        uri,
        headers: {
          'User-Agent': _ua,
          'Referer': pageUrl,
          'Accept': 'text/html,application/xhtml+xml',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
          if (cookie.isNotEmpty) 'Cookie': cookie,
        },
      ).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return null;
      final contentType = response.headers['content-type'] ?? '';
      if (contentType.isNotEmpty && !contentType.contains('html')) {
        return null;
      }
      final body = utf8.decode(response.bodyBytes, allowMalformed: true);
      final mediaUrls = extractMediaUrls(body, pageUrl);
      if (mediaUrls.isEmpty) return null;

      final title = _meta(body, const ['og:title', 'twitter:title']) ??
          _titleTag(body) ??
          uri.host;
      final thumbnail = _meta(body, const ['og:image', 'twitter:image']) ?? '';
      final formats = <FormatOption>[];
      for (final mediaUrl in mediaUrls.take(8)) {
        final kind = detectMediaKind(mediaUrl);
        if (kind == null) continue;
        formats.add(FormatOption(
          formatId: jsonEncode({
            'url': mediaUrl,
            'kind': kind,
            'referer': pageUrl,
            'cookie': cookie,
          }),
          label: '网页提取 ${kind.toUpperCase()}',
          height: 0,
          ext: kind == 'hls' || kind == 'dash' ? 'mp4' : 'mp4',
        ));
      }
      if (formats.isEmpty) return null;
      return VideoInfo(
        url: pageUrl,
        title: title,
        duration: 0,
        uploader: uri.host,
        thumbnail: thumbnail,
        extractor: 'GenericWeb',
        videoId: pageUrl.hashCode.abs().toString(),
        formats: formats,
      );
    } catch (_) {
      return null;
    } finally {
      client?.close();
    }
  }

  /// 建立一个走用户代理设置的 HTTP 客户端。
  ///
  /// Dart 的 HttpClient 只支持 HTTP(S) 代理；socks5 配置交给 yt-dlp 处理，
  /// 这里直接连接，避免把 SOCKS 地址误当 HTTP 代理。
  static Future<http.Client> _createClient() async {
    final proxy = SettingsStorage.instance.current.proxy;
    final proxyUri = Uri.tryParse(proxy);
    if (proxyUri == null ||
        proxyUri.host.isEmpty ||
        (proxyUri.scheme != 'http' && proxyUri.scheme != 'https')) {
      return http.Client();
    }
    final port = proxyUri.hasPort
        ? proxyUri.port
        : (proxyUri.scheme == 'https' ? 443 : 80);
    final io = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..findProxy = ((_) => 'PROXY ${proxyUri.host}:$port');
    return IOClient(io);
  }

  /// 从 HTML 里提取并去重媒体地址，按页面出现顺序返回。
  static List<String> extractMediaUrls(String html, String pageUrl) {
    final page = Uri.tryParse(pageUrl);
    if (page == null) return const [];

    final found = <String>[];

    void add(String raw) {
      var value = raw
          .replaceAll(r'\/', '/')
          .replaceAll('&amp;', '&')
          .replaceAll('&#38;', '&')
          .trim();
      if (value.isEmpty) return;
      if (value.startsWith('//')) {
        value = '${page.scheme}:$value';
      } else if (value.startsWith('/')) {
        value = page.resolve(value).toString();
      } else if (!value.startsWith('http://') &&
          !value.startsWith('https://')) {
        value = page.resolve(value).toString();
      }
      if (detectMediaKind(value) == null) return;
      if (!found.contains(value)) found.add(value);
    }

    // og:video / twitter:player:stream / video 标签
    for (final tag in RegExp(r'<meta\b[^>]*>', caseSensitive: false)
        .allMatches(html)) {
      final raw = tag.group(0)!;
      final key = _attribute(raw, 'property') ??
          _attribute(raw, 'name') ??
          _attribute(raw, 'itemprop');
      if (key == null) continue;
      if (!const {
        'og:video',
        'og:video:url',
        'og:video:secure_url',
        'twitter:player:stream',
        'contenturl',
      }.contains(key.toLowerCase())) {
        continue;
      }
      final content = _attribute(raw, 'content');
      if (content != null) add(content);
    }

    // 普通 src 与懒加载 data-src。
    for (final match in RegExp(
      r'''<(?:video|source)\b[^>]*\b(?:src|data-src|data-video-src|data-url)\s*=\s*["']([^"']+)''',
      caseSensitive: false,
    ).allMatches(html)) {
      add(match.group(1)!);
    }

    // JSON-LD / 内联脚本里的媒体字段。
    for (final match in RegExp(
      r'''["'](?:contentUrl|videoUrl|video_url|playUrl|play_url|hlsUrl|hls_url|mp4Url|mp4_url|streamUrl|stream_url)["']\s*:\s*["']([^"']+)''',
      caseSensitive: false,
    ).allMatches(html)) {
      add(match.group(1)!);
    }

    // 任意脚本/属性里的直链（转义斜杠已在此处兼容）
    for (final match in RegExp(
      r'''https?:(?:\\?/){2}[^\s"'<>]+?\.(?:m3u8|mpd|mp4|flv|m4v)(?:\?[^\s"'<>]*)?''',
      caseSensitive: false,
    ).allMatches(html)) {
      add(match.group(0)!);
    }

    return found;
  }

  static String? _meta(String html, List<String> keys) {
    for (final tag in RegExp(r'<meta\b[^>]*>', caseSensitive: false)
        .allMatches(html)) {
      final raw = tag.group(0)!;
      final key = _attribute(raw, 'property') ?? _attribute(raw, 'name');
      if (key == null) continue;
      if (!keys.contains(key.toLowerCase())) continue;
      final content = _attribute(raw, 'content');
      if (content != null && content.isNotEmpty) return content;
    }
    return null;
  }

  static String? _titleTag(String html) {
    final match = RegExp(
      r'<title[^>]*>([^<]+)</title>',
      caseSensitive: false,
    ).firstMatch(html);
    final value = match?.group(1)?.trim();
    return value == null || value.isEmpty
        ? null
        : value.replaceAll(RegExp(r'\s+'), ' ');
  }

  static String? _attribute(String tag, String name) {
    final match = RegExp(
      '$name\\s*=\\s*["\']([^"\']*)["\']',
      caseSensitive: false,
    ).firstMatch(tag);
    return match?.group(1);
  }
}
