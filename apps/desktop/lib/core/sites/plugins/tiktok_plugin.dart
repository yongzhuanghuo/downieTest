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

/// TikTok 原生插件。
///
/// 页面内嵌 `__UNIVERSAL_DATA_FOR_REHYDRATION__`，里面
/// `webapp.video-detail.itemInfo.itemStruct` 有无水印 playAddr/downloadAddr
/// 和 bitrateInfo 多画质。TikTok 的 CDN 需要桌面 UA + Referer。
class TikTokPlugin extends SitePlugin {
  @override
  String get id => 'TikTok';

  @override
  String get displayName => 'TikTok';

  @override
  int get priority => 80;

  static const String ua =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/126.0.0.0 Safari/537.36';

  @override
  bool matches(Uri uri, String rawInput) {
    final host = uri.host.toLowerCase();
    if (host == 'vm.tiktok.com' ||
        host == 'vt.tiktok.com' ||
        host == 'm.tiktok.com') {
      return true;
    }
    if (host != 'tiktok.com' && !host.endsWith('.tiktok.com')) return false;
    final path = uri.path.toLowerCase();
    return path.contains('/video/') ||
        path.startsWith('/t/') ||
        path.startsWith('/v/');
  }

  @override
  Future<VideoInfo> parse(String url) async {
    http.Client? client;
    try {
      client = _makeClient();
      final resolved = await _resolve(client, url);
      final cookie = await SiteCookies.loadCookieHeader('tiktok');
      final response = await client.get(
        Uri.parse(resolved),
        headers: {
          'User-Agent': ua,
          'Accept': 'text/html,application/xhtml+xml',
          'Accept-Language': 'en-US,en;q=0.9,zh-CN;q=0.8',
          if (cookie.isNotEmpty) 'Cookie': cookie,
        },
      ).timeout(const Duration(seconds: 25));
      if (response.statusCode != 200) {
        throw SitePluginException(
          'TikTok 页面 HTTP ${response.statusCode}',
          retryable: true,
          fallbackToYtDlp: true,
        );
      }
      return parseHydration(response.body, pageUrl: resolved);
    } on SitePluginException {
      rethrow;
    } catch (e) {
      throw SitePluginException(
        'TikTok 解析失败: $e',
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
        referer: 'https://www.tiktok.com/',
        cookieSiteId: 'tiktok',
      );
    } on DouyinDownloadException catch (e) {
      throw SitePluginException(e.message, retryable: false);
    }
  }

  /// 纯函数：从页面 HTML 解析。独立出来便于用固定样本做单元测试。
  static VideoInfo parseHydration(String html, {String? pageUrl}) {
    final match = RegExp(
      r'<script[^>]+id="__UNIVERSAL_DATA_FOR_REHYDRATION__"[^>]*>([\s\S]*?)</script>',
    ).firstMatch(html);
    if (match == null) {
      throw const SitePluginException(
        'TikTok 页面没有 __UNIVERSAL_DATA_FOR_REHYDRATION__',
        retryable: true,
        fallbackToYtDlp: true,
      );
    }
    final decoded = jsonDecode(match.group(1)!);
    if (decoded is! Map) {
      throw const SitePluginException(
        'TikTok 页面数据格式错误',
        retryable: false,
        fallbackToYtDlp: true,
      );
    }
    final scope = decoded['__DEFAULT_SCOPE__'];
    final detail = scope is Map ? scope['webapp.video-detail'] : null;
    final info = detail is Map ? detail['itemInfo'] : null;
    final item = info is Map ? info['itemStruct'] : null;
    if (item is! Map) {
      throw const SitePluginException(
        'TikTok 页面没有视频数据（可能需要登录/地区限制）',
        retryable: true,
        requiresLogin: true,
        fallbackToYtDlp: true,
      );
    }
    final map = Map<String, dynamic>.from(item);
    final video = map['video'] is Map
        ? Map<String, dynamic>.from(map['video'] as Map)
        : const <String, dynamic>{};
    final author = map['author'] is Map
        ? Map<String, dynamic>.from(map['author'] as Map)
        : const <String, dynamic>{};
    final id = map['id']?.toString() ?? video['id']?.toString() ?? '';
    if (id.isEmpty) {
      throw const SitePluginException(
        'TikTok 视频 ID 缺失',
        retryable: false,
        fallbackToYtDlp: true,
      );
    }

    String firstUrl(dynamic mapOrList) {
      if (mapOrList is List) {
        for (final item in mapOrList) {
          final url = firstUrl(item);
          if (url.isNotEmpty) return url;
        }
        return '';
      }
      if (mapOrList is Map) {
        final urls = mapOrList['UrlList'] ?? mapOrList['url_list'];
        final nested = firstUrl(urls);
        if (nested.isNotEmpty) return nested;
      }
      if (mapOrList is String && mapOrList.startsWith('http')) {
        return mapOrList;
      }
      return '';
    }

    final formats = <FormatOption>[];
    final seen = <String>{};
    void add(String url, String label, int height, int? size) {
      if (url.isEmpty || !seen.add(url)) return;
      formats.add(FormatOption(
        formatId: url,
        label: label,
        height: height,
        ext: 'mp4',
        fileSize: size,
      ));
    }

    final bitrates = video['bitrateInfo'];
    if (bitrates is List) {
      for (final raw in bitrates) {
        if (raw is! Map) continue;
        final b = Map<String, dynamic>.from(raw);
        final play = b['PlayAddr'];
        final url = firstUrl(play);
        if (url.isEmpty) continue;
        final height = play is Map
            ? (play['Height'] as num?)?.toInt() ?? 0
            : 0;
        final bitrate = (b['Bitrate'] as num?)?.toInt();
        final gear = b['GearName']?.toString() ?? '';
        final label = height > 0
            ? '${height}p'
            : (gear.isNotEmpty ? gear : 'MP4');
        final size = play is Map
            ? int.tryParse(play['DataSize']?.toString() ?? '')
            : null;
        add(url, label, height, size);
      }
    }
    if (formats.isEmpty) {
      final url = firstUrl(video['playAddr']).isNotEmpty
          ? firstUrl(video['playAddr'])
          : firstUrl(video['downloadAddr']);
      final height = (video['height'] as num?)?.toInt() ?? 0;
      add(url, height > 0 ? '${height}p' : '原画 MP4', height, null);
    }
    formats.sort((a, b) => b.height.compareTo(a.height));
    if (formats.isEmpty) {
      throw const SitePluginException(
        'TikTok 没有可用的播放地址',
        retryable: true,
        fallbackToYtDlp: true,
      );
    }

    final desc = map['desc']?.toString() ?? '';
    final cover = video['cover'];
    final coverUrl = cover is String
        ? cover
        : (cover is Map ? firstUrl(cover['url_list']) : '');
    final nickname = author['nickname']?.toString() ?? '';
    final duration = (video['duration'] as num?)?.toInt() ?? 0;

    return VideoInfo(
      url: pageUrl ?? 'https://www.tiktok.com/@/video/$id',
      title: desc.isEmpty ? 'TikTok 视频' : desc,
      duration: duration,
      uploader: nickname,
      thumbnail: coverUrl,
      extractor: 'TikTok',
      videoId: id,
      formats: formats,
    );
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

  Future<String> _resolve(http.Client client, String url) async {
    var current = Uri.parse(url);
    for (var i = 0; i < 5; i++) {
      if (current.path.contains('/video/')) return current.toString();
      final request = http.Request('GET', current)..followRedirects = false;
      request.headers['User-Agent'] = ua;
      request.headers['Accept'] = 'text/html,application/xhtml+xml';
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 15));
      final location = response.headers['location'];
      if (location == null || location.isEmpty) break;
      current = current.resolve(location);
    }
    return current.toString();
  }
}
