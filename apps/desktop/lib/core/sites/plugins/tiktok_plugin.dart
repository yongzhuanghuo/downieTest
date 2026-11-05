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
        path.startsWith('/v/') ||
        path.startsWith('/shortdrama/episode/');
  }

  @override
  Future<VideoInfo> parse(String url) async {
    http.Client? client;
    try {
      client = await _makeClient();
      final cookie = await SiteCookies.loadCookieHeader('tiktok');
      final shortDrama = shortDramaFromUrl(url);
      if (shortDrama != null) {
        return await _parseShortDrama(
          client,
          url,
          shortDrama.dramaId,
          shortDrama.episode,
          cookie,
        );
      }
      final resolved = await _resolve(client, url);
      final resolvedShortDrama = shortDramaFromUrl(resolved);
      if (resolvedShortDrama != null) {
        return await _parseShortDrama(
          client,
          resolved,
          resolvedShortDrama.dramaId,
          resolvedShortDrama.episode,
          cookie,
        );
      }
      return await _parsePage(client, resolved, cookie);
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

  /// 解析 `/shortdrama/episode/<dramaId>/<episode>`。
  ///
  /// 短剧网页本身会 302 到 /foryou；但官方的
  /// `api/drama/episode/item_list` 不需要签名，可以先拿到单集 item，
  /// 再按普通视频页取播放地址。付费/需登录的集数会返回 requiresLogin，
  /// 让上层弹出 TikTok 登录窗口。
  Future<VideoInfo> _parseShortDrama(
    http.Client client,
    String inputUrl,
    String dramaId,
    int episode,
    String cookie,
  ) async {
    final endpoint =
        Uri.https('www.tiktok.com', '/api/drama/episode/item_list/', {
          'dramaID': dramaId,
          'cursor': '${episode - 1}',
          'count': '1',
          'aid': '1988',
          'language': 'en',
          'region': '',
          'storeRegion': '',
        });
    final response = await client
        .get(endpoint, headers: _apiHeaders(cookie, inputUrl))
        .timeout(const Duration(seconds: 25));
    if (response.statusCode == 429) {
      throw const SitePluginException(
        'TikTok 短剧接口限流，请稍后重试',
        retryable: true,
        fallbackToYtDlp: false,
      );
    }
    if (response.statusCode != 200) {
      throw SitePluginException(
        'TikTok 短剧接口 HTTP ${response.statusCode}',
        retryable: true,
        fallbackToYtDlp: false,
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const SitePluginException(
        'TikTok 短剧数据格式错误',
        retryable: true,
        fallbackToYtDlp: false,
      );
    }
    final status =
        (decoded['statusCode'] as num?)?.toInt() ??
        (decoded['status_code'] as num?)?.toInt() ??
        0;
    if (status != 0) {
      throw SitePluginException(
        'TikTok 短剧接口返回状态 $status',
        retryable: true,
        fallbackToYtDlp: false,
      );
    }
    final items = decoded['itemList'] ?? decoded['item_list'];
    if (items is! List || items.isEmpty || items.first is! Map) {
      throw const SitePluginException(
        'TikTok 没有返回该集信息',
        retryable: true,
        fallbackToYtDlp: false,
      );
    }

    final item = Map<String, dynamic>.from(items.first as Map);
    final itemId = item['id']?.toString() ?? '';
    final author = item['author'] is Map
        ? Map<String, dynamic>.from(item['author'] as Map)
        : const <String, dynamic>{};
    final uniqueId =
        author['uniqueId']?.toString() ?? author['unique_id']?.toString() ?? '';
    final dramaInfo = item['dramaInfo'] is Map
        ? Map<String, dynamic>.from(item['dramaInfo'] as Map)
        : const <String, dynamic>{};
    final dramaName = dramaInfo['dramaName']?.toString().trim() ?? '';
    final desc = item['desc']?.toString().trim() ?? '';
    final title = [
      if (dramaName.isNotEmpty) dramaName,
      'EP$episode',
      if (desc.isNotEmpty) desc,
    ].join(' · ');
    final pageUrl = uniqueId.isNotEmpty && itemId.isNotEmpty
        ? 'https://www.tiktok.com/@${Uri.encodeComponent(uniqueId)}/video/$itemId'
        : inputUrl;

    // 免费集：接口 item 自带播放地址，直接出格式。
    if (itemId.isNotEmpty) {
      try {
        return parseVideoItem(item, pageUrl: pageUrl, titleOverride: title);
      } on SitePluginException {
        // 预览/付费集没有 playAddr，继续用普通视频页兜底。
      }
    }

    // 普通视频页可能带完整播放地址（已登录/已解锁时）。
    if (uniqueId.isNotEmpty && itemId.isNotEmpty) {
      try {
        final info = await _parsePage(
          client,
          pageUrl,
          cookie,
          titleOverride: title,
        );
        if (info.videoId == itemId) return info;
      } on SitePluginException {
        // 统一转成下面的登录提示。
      }
    }

    throw SitePluginException(
      'TikTok 短剧第 $episode 集需要登录后观看，请登录 TikTok 再试',
      retryable: true,
      requiresLogin: true,
      fallbackToYtDlp: false,
    );
  }

  Future<VideoInfo> _parsePage(
    http.Client client,
    String pageUrl,
    String cookie, {
    String? titleOverride,
  }) async {
    final response = await client
        .get(
          Uri.parse(pageUrl),
          headers: {
            'User-Agent': ua,
            'Accept': 'text/html,application/xhtml+xml',
            'Accept-Language': 'en-US,en;q=0.9,zh-CN;q=0.8',
            if (cookie.isNotEmpty) 'Cookie': cookie,
          },
        )
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      throw SitePluginException(
        'TikTok 页面 HTTP ${response.statusCode}',
        retryable: true,
        fallbackToYtDlp: true,
      );
    }
    return parseHydration(
      response.body,
      pageUrl: pageUrl,
      titleOverride: titleOverride,
    );
  }

  Map<String, String> _apiHeaders(String cookie, String referer) => {
    'User-Agent': ua,
    'Accept': 'application/json, text/plain, */*',
    'Accept-Language': 'en-US,en;q=0.9,zh-CN;q=0.8',
    'Referer': referer,
    if (cookie.isNotEmpty) 'Cookie': cookie,
  };

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

  /// 纯函数：识别 `/shortdrama/episode/<dramaId>/<episode>`。
  @visibleForTesting
  static ({String dramaId, int episode})? shortDramaFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length < 4) return null;
    if (segments[0].toLowerCase() != 'shortdrama' ||
        segments[1].toLowerCase() != 'episode') {
      return null;
    }
    final dramaId = segments[2];
    if (!RegExp(r'^\d+$').hasMatch(dramaId)) return null;
    final episode = int.tryParse(segments[3]);
    if (episode == null || episode <= 0) return null;
    return (dramaId: dramaId, episode: episode);
  }

  /// 纯函数：从页面 HTML 解析。独立出来便于用固定样本做单元测试。
  static VideoInfo parseHydration(
    String html, {
    String? pageUrl,
    String? titleOverride,
  }) {
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
    return parseVideoItem(
      Map<String, dynamic>.from(item),
      pageUrl: pageUrl,
      titleOverride: titleOverride,
    );
  }

  /// 纯函数：把页面 itemStruct 或短剧接口 item 转成 [VideoInfo]。
  @visibleForTesting
  static VideoInfo parseVideoItem(
    Map<String, dynamic> map, {
    String? pageUrl,
    String? titleOverride,
  }) {
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
      formats.add(
        FormatOption(
          formatId: url,
          label: label,
          height: height,
          ext: 'mp4',
          fileSize: size,
        ),
      );
    }

    final bitrates = video['bitrateInfo'] ?? video['bitrate_info'];
    if (bitrates is List) {
      for (final raw in bitrates) {
        if (raw is! Map) continue;
        final b = Map<String, dynamic>.from(raw);
        final play = b['PlayAddr'] ?? b['playAddr'];
        final url = firstUrl(play);
        if (url.isEmpty) continue;
        final height = play is Map
            ? ((play['Height'] ?? play['height']) as num?)?.toInt() ?? 0
            : 0;
        final gear = (b['GearName'] ?? b['gear_name'])?.toString() ?? '';
        final label = height > 0
            ? '${height}p'
            : (gear.isNotEmpty ? gear : 'MP4');
        final size = play is Map
            ? int.tryParse(
                (play['DataSize'] ?? play['data_size'])?.toString() ?? '',
              )
            : null;
        add(url, label, height, size);
      }
    }
    if (formats.isEmpty) {
      final playAddr = video['playAddr'] ?? video['play_addr'];
      final downloadAddr = video['downloadAddr'] ?? video['download_addr'];
      final url = firstUrl(playAddr).isNotEmpty
          ? firstUrl(playAddr)
          : firstUrl(downloadAddr);
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
        : (cover is Map ? firstUrl(cover['url_list'] ?? cover['UrlList']) : '');
    final nickname = author['nickname']?.toString() ?? '';
    final duration = (video['duration'] as num?)?.toInt() ?? 0;
    final title = titleOverride?.trim();

    return VideoInfo(
      url: pageUrl ?? 'https://www.tiktok.com/@/video/$id',
      title: title != null && title.isNotEmpty
          ? title
          : (desc.isEmpty ? 'TikTok 视频' : desc),
      duration: duration,
      uploader: nickname,
      thumbnail: coverUrl,
      extractor: 'TikTok',
      videoId: id,
      formats: formats,
    );
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

  Future<String> _resolve(http.Client client, String url) async {
    var current = Uri.parse(url);
    for (var i = 0; i < 5; i++) {
      if (current.path.contains('/video/') ||
          current.path.contains('/shortdrama/episode/')) {
        return current.toString();
      }
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
