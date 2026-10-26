import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../data/models/format_option.dart';
import '../../data/models/video_info.dart';
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

    try {
      final response = await http.get(
        uri,
        headers: {
          'User-Agent': _ua,
          'Referer': pageUrl,
          'Accept': 'text/html,application/xhtml+xml',
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
            'cookie': '',
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
    }
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
      final key = _attribute(raw, 'property') ?? _attribute(raw, 'name');
      if (key == null) continue;
      if (!const {
        'og:video',
        'og:video:url',
        'og:video:secure_url',
        'twitter:player:stream',
      }.contains(key.toLowerCase())) {
        continue;
      }
      final content = _attribute(raw, 'content');
      if (content != null) add(content);
    }

    for (final match in RegExp(
      r'''<(?:video|source)\b[^>]*\bsrc\s*=\s*["']([^"']+)''',
      caseSensitive: false,
    ).allMatches(html)) {
      add(match.group(1)!);
    }

    // JSON-LD / 内联脚本里的 contentUrl
    for (final match in RegExp(
      r'''["']contentUrl["']\s*:\s*["']([^"']+)''',
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
