import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../../../data/models/format_option.dart';
import '../../../data/models/video_info.dart';
import '../../engine/douyin_downloader.dart';
import '../../ffmpeg/ffmpeg_runner.dart';
import '../../storage/settings_storage.dart';
import '../../storage/site_cookies.dart';
import '../site_plugin.dart';

/// 微博原生插件。
///
/// 微博把视频播放地址放在 `weibo.com/ajax/statuses/show` 的
/// `page_info.media_info` / `Component_Play_Playinfo` 中。接口需要登录/访客
/// cookie；没有 cookie 时抛 requiresLogin，让内置登录浏览器接管。
class WeiboPlugin extends SitePlugin {
  @override
  String get id => 'Weibo';

  @override
  String get displayName => '微博';

  @override
  int get priority => 75;

  static const String ua =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/126.0.0.0 Safari/537.36';

  @override
  bool matches(Uri uri, String rawInput) {
    final host = uri.host.toLowerCase();
    if (host != 'weibo.com' &&
        !host.endsWith('.weibo.com') &&
        host != 'weibo.cn' &&
        !host.endsWith('.weibo.cn')) {
      return false;
    }
    final path = uri.path.toLowerCase();
    if (path.contains('/tv/show/') ||
        path.contains('/tv/v/') ||
        path.startsWith('/show/') ||
        path.startsWith('/player/')) {
      return true;
    }
    // 微博正文链接 /<uid>/<mid>
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    return segments.length >= 2 &&
        RegExp(r'^[A-Za-z0-9]{5,}$').hasMatch(segments.last);
  }

  @override
  Future<VideoInfo> parse(String url) async {
    http.Client? client;
    try {
      final uri = Uri.parse(url);
      final id = _extractId(uri);
      if (id == null || id.isEmpty) {
        throw const SitePluginException(
          '无法从微博链接提取视频 ID',
          retryable: false,
          fallbackToYtDlp: true,
        );
      }
      client = _makeClient();
      final cookie = await SiteCookies.loadCookieHeader('weibo');
      final response = await client.get(
        Uri.https('weibo.com', '/ajax/statuses/show', {'id': id}),
        headers: {
          'User-Agent': ua,
          'Accept': 'application/json, text/plain, */*',
          'Referer': 'https://weibo.com/',
          if (cookie.isNotEmpty) 'Cookie': cookie,
        },
      ).timeout(const Duration(seconds: 25));
      if (response.statusCode == 401 ||
          response.statusCode == 403 ||
          response.statusCode == 302) {
        throw const SitePluginException(
          '微博需要登录',
          retryable: false,
          requiresLogin: true,
        );
      }
      final body = response.body.trim();
      if (body.startsWith('<')) {
        throw const SitePluginException(
          '微博返回登录/访客页面',
          retryable: false,
          requiresLogin: true,
        );
      }
      if (response.statusCode != 200) {
        throw SitePluginException(
          '微博接口 HTTP ${response.statusCode}',
          retryable: true,
          fallbackToYtDlp: true,
        );
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        throw const SitePluginException(
          '微博接口返回格式错误',
          retryable: true,
          requiresLogin: true,
          fallbackToYtDlp: true,
        );
      }
      return parseStatus(
        Map<String, dynamic>.from(decoded),
        id: id,
        pageUrl: url,
      );
    } on SitePluginException {
      rethrow;
    } catch (e) {
      throw SitePluginException(
        '微博解析失败: $e',
        retryable: true,
        fallbackToYtDlp: true,
      );
    } finally {
      client?.close();
    }
  }

  @override
  Future<String> download(PluginDownloadRequest request) async {
    final url = request.task.formatId;
    final cookie = await SiteCookies.loadCookieHeader('weibo');
    try {
      if (url.toLowerCase().contains('.m3u8')) {
        return await FFmpegRunner.downloadUrl(
          url: url,
          outputPath: request.outputPath,
          referer: 'https://weibo.com/',
          cookie: cookie,
          userAgent: ua,
          onProgress: request.onProgress,
          shouldCancel: request.shouldCancel,
        );
      }
      return await DouyinDownloader.download(
        url: url,
        outputPath: request.outputPath,
        onProgress: request.onProgress,
        shouldCancel: request.shouldCancel,
        referer: 'https://weibo.com/',
        cookieSiteId: 'weibo',
      );
    } on DouyinDownloadException catch (e) {
      throw SitePluginException(e.message, retryable: false);
    } catch (e) {
      throw SitePluginException('微博下载失败: $e', retryable: false);
    }
  }

  static VideoInfo parseStatus(
    Map<String, dynamic> json, {
    required String id,
    String? pageUrl,
  }) {
    final media = <String, String>{}; // key -> url
    String? title;
    String? cover;
    int duration = 0;

    final seenUrls = <String>{};
    void addUrl(String key, String url) {
      if (!url.startsWith('http')) return;
      if (!(url.contains('.mp4') ||
          url.contains('.m3u8') ||
          url.contains('.flv') ||
          url.contains('video'))) {
        return;
      }
      if (!seenUrls.add(url)) return;
      media.putIfAbsent(key, () => url);
    }

    void walk(dynamic value, int depth) {
      if (depth > 14 || value == null) return;
      if (value is List) {
        for (final item in value) {
          walk(item, depth + 1);
        }
        return;
      }
      if (value is! Map) return;
      final map = Map<String, dynamic>.from(value);
      final text = map['text_raw'] ?? map['title'] ?? map['desc'];
      if (text is String && text.trim().isNotEmpty) {
        title ??= text.replaceAll(RegExp(r'<[^>]+>'), '').trim();
      }
      final pic = map['page_pic'] ?? map['cover'] ?? map['pic'];
      if (cover == null) {
        if (pic is String && pic.startsWith('http')) {
          cover = pic;
        } else if (pic is Map && pic['url'] is String) {
          cover = pic['url'] as String;
        }
      }
      final d = map['duration'];
      if (d is num && d > duration) {
        duration = d > 1000 ? d.toInt() ~/ 1000 : d.toInt();
      }
      for (final key in const [
        'stream_url_hd',
        'stream_url',
        'video_url',
        'mp4_720p_mp4',
        'mp4_hd_url',
        'mp4_sd_url',
        'mp4_ld_mp4',
        'play_url',
      ]) {
        final value = map[key];
        if (value is String) addUrl(key, value);
      }
      for (final child in map.values) {
        if (child is Map || child is List) walk(child, depth + 1);
      }
    }

    walk(json, 0);
    if (media.isEmpty) {
      throw const SitePluginException(
        '微博没有可用的视频地址（可能需要登录或不是视频微博）',
        retryable: true,
        requiresLogin: true,
        fallbackToYtDlp: true,
      );
    }
    final formats = <FormatOption>[];
    for (final entry in media.entries) {
      final key = entry.key;
      final height = key.contains('720') || key.contains('hd')
          ? 720
          : (key.contains('sd') || key.contains('ld') ? 480 : 0);
      final label = height >= 720
          ? '高清 MP4'
          : (height > 0 ? '标清 MP4' : '原画');
      formats.add(FormatOption(
        formatId: entry.value,
        label: label,
        height: height,
        ext: 'mp4',
        needsMerge: entry.value.contains('.m3u8'),
      ));
    }
    formats.sort((a, b) => b.height.compareTo(a.height));
    return VideoInfo(
      url: pageUrl ?? 'https://weibo.com/tv/show/$id',
      title: title?.isNotEmpty == true ? title! : '微博视频',
      duration: duration,
      uploader: _uploader(json),
      thumbnail: cover ?? '',
      extractor: 'Weibo',
      videoId: id,
      formats: formats,
    );
  }

  static String _uploader(Map<String, dynamic> json) {
    final user = json['user'];
    if (user is Map) {
      final name = user['screen_name'] ?? user['name'];
      if (name is String) return name;
    }
    return '';
  }

  static String? _extractId(Uri uri) {
    final fid = uri.queryParameters['fid'];
    if (fid != null && fid.isNotEmpty) return fid;
    for (final pattern in [
      RegExp(r'/show/([0-9a-fA-F:]+)'),
      RegExp(r'/tv/show/([0-9a-fA-F:]+)'),
      RegExp(r'/tv/v/[A-Za-z0-9]+\?.*fid=([0-9a-fA-F:]+)'),
    ]) {
      final match = pattern.firstMatch(uri.toString());
      if (match != null) return match.group(1);
    }
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length >= 2 &&
        RegExp(r'^[A-Za-z0-9]{5,}$').hasMatch(segments.last)) {
      return segments.last;
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
