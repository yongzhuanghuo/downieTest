import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../data/models/format_option.dart';
import '../../data/models/video_info.dart';

/// 抖音 HTTP 提取器（绕过 yt-dlp 和 WebView）
///
/// 抖音视频数据在分享页（`iesdouyin.com/share/video/{id}`）的服务端渲染
/// HTML 里（window._ROUTER_DATA），用移动端 UA 直接 HTTP 请求即可拿到，
/// 无需登录、无需签名。视频页（`douyin.com/video/{id}`）走 MSE 播放器，
/// 没有可抓的 SSR 数据，所以一定要抓分享页。
class DouyinHttpExtractor {
  DouyinHttpExtractor._();

  /// 移动端 UA（关键：桌面 UA 拿不到完整的 _ROUTER_DATA）
  static const String mobileUA =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 '
      'Safari/604.1';

  /// 从短链/长链解析视频 ID（跟随重定向拿最终 URL 里的数字 ID）
  static Future<String?> resolveId(String url) async {
    try {
      final client = http.Client();
      final req = http.Request('GET', Uri.parse(url));
      req.headers['User-Agent'] = mobileUA;
      req.followRedirects = true;
      final resp = await client.send(req);
      final finalUrl = resp.request?.url.toString() ?? url;
      debugPrint('[抖音HTTP] 短链解析到: $finalUrl');
      // 抖音视频 ID 是 19 位；15 位以上避免误匹配 ts= 等 10 位参数
      final m = RegExp(r'/(\d{15,})').firstMatch(finalUrl);
      final id = m?.group(1);
      client.close();
      return id;
    } catch (e) {
      debugPrint('[抖音HTTP] 短链解析失败: $e');
      return null;
    }
  }

  /// 从分享页抓视频信息，构造 [VideoInfo]
  static Future<VideoInfo> fetch(String id, String originalUrl) async {
    final shareUrl = 'https://www.iesdouyin.com/share/video/$id';
    debugPrint('[抖音HTTP] 抓分享页: $shareUrl');
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(shareUrl));
      req.headers['User-Agent'] = mobileUA;
      final resp = await client.send(req);
      final html = await resp.stream.bytesToString();
      debugPrint('[抖音HTTP] 分享页 HTTP ${resp.statusCode}，HTML 长度 ${html.length}');
      if (resp.statusCode != 200) {
        throw Exception('分享页 HTTP ${resp.statusCode}');
      }

      final json = _extractRouterData(html);
      if (json == null) {
        throw Exception('未找到 _ROUTER_DATA / RENDER_DATA');
      }

      final item = _findVideoItem(json);
      if (item == null) {
        throw Exception('未找到视频数据（无 play_addr）');
      }

      return _buildVideoInfo(item, originalUrl);
    } finally {
      client.close();
    }
  }

  /// 从分享页 HTML 提取 _ROUTER_DATA JSON（分享页是 window._ROUTER_DATA，RENDER_DATA 兜底）
  static Map<String, dynamic>? _extractRouterData(String html) {
    // 1. window._ROUTER_DATA = {...};（分享页 SSR 的实际形式，优先）
    final routerData = RegExp(
      r'window\._ROUTER_DATA\s*=\s*(\{.*?\})\s*</script>',
      dotAll: true,
    ).firstMatch(html);
    if (routerData != null) {
      try {
        debugPrint('[抖音HTTP] 找到 window._ROUTER_DATA');
        return jsonDecode(routerData.group(1)!) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('[抖音HTTP] _ROUTER_DATA 解析失败: $e');
      }
    }

    // 2. <script id="RENDER_DATA" type="application/json">URL-encoded JSON</script>（兜底）
    final renderData =
        RegExp(r'id="RENDER_DATA"[^>]*>(.*?)</script>', dotAll: true)
            .firstMatch(html);
    if (renderData != null) {
      try {
        final decoded = Uri.decodeComponent(renderData.group(1)!.trim());
        debugPrint('[抖音HTTP] 找到 RENDER_DATA，解码后长度 ${decoded.length}');
        return jsonDecode(decoded) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('[抖音HTTP] RENDER_DATA 解析失败: $e');
      }
    }

    return null;
  }

  /// 递归查找包含 video.play_addr 的对象（抖音 item）
  static Map<String, dynamic>? _findVideoItem(dynamic obj) {
    if (obj is Map<String, dynamic>) {
      final v = obj['video'];
      if (v is Map && v.containsKey('play_addr')) {
        return obj;
      }
      for (final val in obj.values) {
        final r = _findVideoItem(val);
        if (r != null) return r;
      }
    } else if (obj is List) {
      for (final item in obj) {
        final r = _findVideoItem(item);
        if (r != null) return r;
      }
    }
    return null;
  }

  static VideoInfo _buildVideoInfo(
    Map<String, dynamic> item,
    String originalUrl,
  ) {
    final desc = (item['desc'] as String?) ?? '';
    final author = item['author'] is Map
        ? (item['author'] as Map)['nickname'] as String?
        : null;
    final durationMs = (item['duration'] as num?)?.toInt() ?? 0;
    final video = (item['video'] as Map?) ?? const {};

    String firstUrl(dynamic addr) {
      if (addr is Map) {
        final urlList = addr['url_list'];
        if (urlList is List && urlList.isNotEmpty) {
          return urlList.first.toString();
        }
      }
      return '';
    }

    final cover = firstUrl(video['cover']);
    final playAddr = firstUrl(video['play_addr']);

    // 各清晰度：video.bit_rate[]，每个有 play_addr.url_list[0]
    final formats = <FormatOption>[];
    final bitRates = video['bit_rate'];
    if (bitRates is List) {
      for (final b in bitRates) {
        if (b is! Map) continue;
        final url = firstUrl(b['play_addr']);
        if (url.isEmpty) continue;
        final gearName = (b['gear_name'] as String?) ?? '';
        final height = _parseHeight(gearName);
        formats.add(FormatOption(
          formatId: _noWatermark(url),
          label: height > 0
              ? '${height}P MP4'
              : (gearName.isNotEmpty ? gearName : 'MP4'),
          height: height,
          ext: 'mp4',
          needsMerge: false,
        ));
      }
    }
    // 没有 bit_rate 时用主播放地址兜底
    if (formats.isEmpty && playAddr.isNotEmpty) {
      formats.add(FormatOption(
        formatId: _noWatermark(playAddr),
        label: '原画 MP4',
        height: 0,
        ext: 'mp4',
      ));
    }

    return VideoInfo(
      url: originalUrl,
      title: desc.isEmpty ? '抖音视频' : desc,
      duration: durationMs > 1000 ? durationMs ~/ 1000 : durationMs,
      uploader: author ?? '',
      thumbnail: cover,
      extractor: 'Douyin',
      videoId: item['aweme_id']?.toString() ?? '',
      formats: formats,
    );
  }

  /// 去水印：把播放地址路径里的 /playwm/ 替换成 /play/
  static String _noWatermark(String url) => url.replaceAll('/playwm/', '/play/');

  static int _parseHeight(String gearName) {
    final parts = gearName.split('x');
    if (parts.length >= 2) {
      final h = int.tryParse(parts[1].trim());
      if (h != null && h > 0) return h;
    }
    return 0;
  }
}
