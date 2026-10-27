import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../../../data/models/format_option.dart';
import '../../../data/models/video_info.dart';
import '../../engine/douyin_downloader.dart';
import '../../storage/settings_storage.dart';
import '../../storage/site_cookies.dart';
import '../site_plugin.dart';

/// 快手原生插件。
///
/// 快手网页把视频详情放在 `window.__APOLLO_STATE__`（部分版本是
/// `__INITIAL_STATE__`），其中 `VisionVideoDetailPhoto` 节点包含
/// photoUrl / manifest / caption。页面结构会变，解析失败时回退 yt-dlp/UGE。
class KuaishouPlugin extends SitePlugin {
  @override
  String get id => 'Kuaishou';

  @override
  String get displayName => '快手';

  @override
  int get priority => 70;

  static const String ua =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/126.0.0.0 Safari/537.36';

  @override
  bool matches(Uri uri, String rawInput) {
    final host = uri.host.toLowerCase();
    if (host == 'v.kuaishou.com' || host.endsWith('.v.kuaishou.com')) {
      return true;
    }
    if (host != 'kuaishou.com' && !host.endsWith('.kuaishou.com')) {
      return false;
    }
    final path = uri.path.toLowerCase();
    return path.startsWith('/short-video/') ||
        path.startsWith('/fw/photo/') ||
        path.startsWith('/photo/');
  }

  @override
  Future<VideoInfo> parse(String url) async {
    http.Client? client;
    try {
      client = _makeClient();
      final cookie = await SiteCookies.loadCookieHeader('kuaishou');
      final response = await client.get(
        Uri.parse(url),
        headers: {
          'User-Agent': ua,
          'Accept': 'text/html,application/xhtml+xml',
          'Accept-Language': 'zh-CN,zh;q=0.9',
          if (cookie.isNotEmpty) 'Cookie': cookie,
        },
      ).timeout(const Duration(seconds: 25));
      if (response.statusCode != 200) {
        throw SitePluginException(
          '快手页面 HTTP ${response.statusCode}',
          retryable: true,
          fallbackToYtDlp: true,
        );
      }
      return parseHtml(response.body, pageUrl: url);
    } on SitePluginException {
      rethrow;
    } catch (e) {
      throw SitePluginException(
        '快手解析失败: $e',
        retryable: true,
        fallbackToYtDlp: true,
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
        referer: 'https://www.kuaishou.com/',
        cookieSiteId: 'kuaishou',
      );
    } on DouyinDownloadException catch (e) {
      throw SitePluginException(e.message, retryable: false);
    }
  }

  static VideoInfo parseHtml(String html, {String? pageUrl}) {
    final state = _extractState(html);
    if (state == null) {
      throw const SitePluginException(
        '快手页面没有 __APOLLO_STATE__/__INITIAL_STATE__',
        retryable: true,
        fallbackToYtDlp: true,
      );
    }

    String? title;
    String? playUrl;
    String? cover;
    int height = 0;
    int duration = 0;
    String? photoId;

    void walk(dynamic value, int depth) {
      if (depth > 18 || value == null) return;
      if (value is List) {
        for (final item in value) {
          walk(item, depth + 1);
        }
        return;
      }
      if (value is! Map) return;
      final map = Map<String, dynamic>.from(value);
      final caption = map['caption'] ?? map['title'] ?? map['desc'];
      if (caption is String && caption.trim().isNotEmpty) {
        title ??= caption.trim();
      }
      final id = map['photoId'] ?? map['id'];
      if (id is String && id.isNotEmpty) photoId ??= id;
      final h = map['height'];
      if (h is num && h > height) height = h.toInt();
      final d = map['duration'];
      if (d is num && d > duration) {
        duration = d > 1000 ? d.toInt() ~/ 1000 : d.toInt();
      }
      final candidates = [
        map['photoUrl'],
        map['playUrl'],
        map['srcNoMark'],
        map['videoUrl'],
      ];
      for (final candidate in candidates) {
        if (candidate is String &&
            candidate.startsWith('http') &&
            playUrl == null) {
          playUrl = candidate;
        }
      }
      final manifest = map['manifest'];
      if (manifest is String && manifest.isNotEmpty) {
        try {
          walk(jsonDecode(manifest), depth + 1);
        } catch (_) {}
      } else if (manifest is Map) {
        walk(manifest, depth + 1);
      }
      final coverValue = map['coverUrl'] ?? map['cover'];
      if (cover is! String && coverValue is String) {
        cover = coverValue;
      }
      for (final child in map.values) {
        if (child is Map || child is List) walk(child, depth + 1);
      }
    }

    // 优先只走当前视频的 VisionVideoDetailPhoto 节点，避免先命中推荐视频。
    if (state is Map) {
      final client = state['defaultClient'] ?? state['initialState'];
      if (client is Map) {
        for (final entry in client.entries) {
          if (entry.key.toString().contains('VisionVideoDetailPhoto')) {
            walk(entry.value, 0);
          }
        }
      }
    }
    if (playUrl == null) walk(state, 0);
    final url = playUrl;
    if (url == null || url.isEmpty) {
      throw const SitePluginException(
        '快手页面没有播放地址',
        retryable: true,
        fallbackToYtDlp: true,
      );
    }
    final formats = <FormatOption>[
      FormatOption(
        formatId: url,
        label: height > 0 ? '原画 ${height}P' : '原画 MP4',
        height: height,
        ext: 'mp4',
      ),
    ];
    final id = photoId ?? '';
    return VideoInfo(
      url: pageUrl ?? 'https://www.kuaishou.com/short-video/$id',
      title: title?.isNotEmpty == true ? title! : '快手视频',
      duration: duration,
      uploader: '',
      thumbnail: cover ?? '',
      extractor: 'Kuaishou',
      videoId: id,
      formats: formats,
    );
  }

  static dynamic _extractState(String html) {
    for (final name in ['__APOLLO_STATE__', '__INITIAL_STATE__']) {
      final match = RegExp(
        'window\\.$name\\s*=\\s*([\\s\\S]*?);?\\s*</script>',
      ).firstMatch(html);
      if (match == null) continue;
      try {
        return jsonDecode(match.group(1)!.trim());
      } catch (_) {}
    }
    return null;
  }

  http.Client _makeClient() {
    final proxy = SettingsStorage.instance.current.proxy;
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
