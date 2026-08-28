import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../data/models/format_option.dart';
import '../../data/models/video_info.dart';
import '../platform/binary_initializer.dart';
import '../platform/binary_locator.dart';

/// 抖音解析异常
class DouyinParseException implements Exception {
  final String message;
  const DouyinParseException(this.message);

  @override
  String toString() => 'DouyinParseException: $message';
}

/// 抖音解析器（纯 HTTP + a_bogus 签名，无浏览器）
///
/// 抖音给 aweme/detail 接口上了 a_bogus 签名墙，yt-dlp 提取器失效，WebView 拦截
/// 也被升级后的页面打穿。这里走纯 HTTP：短链展开拿 aweme_id → ttwid + msToken →
/// node 子进程生成 a_bogus → 调 aweme/detail 拿播放地址。
///
/// 对应服务端 services/api 的 douyin.py + douyin_sign/（那套是 Python + node，
/// 这里是 Dart + node，逻辑一致）。
class DouyinParser {
  DouyinParser._();

  static const String ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

  /// 解析抖音链接，返回 VideoInfo（extractor='Douyin'，formats 的 formatId 为直链）
  static Future<VideoInfo> parse(String url) async {
    final awemeId = await _expand(url);
    debugPrint('[抖音] aweme_id=$awemeId');

    final ttwid = await _getTtwid();
    final msToken = _getMsToken();
    final aBogus = await _generateABogus(awemeId, msToken);
    debugPrint('[抖音] a_bogus 长度=${aBogus.length}');

    final detail = await _fetchAwemeDetail(awemeId, msToken, aBogus, ttwid);
    return _parseAweme(awemeId, detail);
  }

  /// 短链展开，取 aweme_id。
  /// http 包自动跟随重定向后 request.url 仍是原始短链，所以手动循环追 Location。
  static Future<String> _expand(String url) async {
    final client = http.Client();
    try {
      var current = Uri.parse(url);
      // 短链可能 302 多次（v.douyin.com → www.douyin.com/video/xxx），最多追 5 跳
      for (var i = 0; i < 5; i++) {
        final m = RegExp(r'/video/(\d+)').firstMatch(current.toString());
        if (m != null) return m.group(1)!;
        final req = http.Request('GET', current);
        req.followRedirects = false;
        req.headers['User-Agent'] = ua;
        final resp = await client.send(req);
        final location = resp.headers['location'];
        if (location == null || location.isEmpty) break;
        current = current.resolve(location);
      }
      final m = RegExp(r'(\d{15,})').firstMatch(current.toString());
      if (m == null) throw DouyinParseException('无法从链接提取 aweme_id');
      return m.group(1)!;
    } finally {
      client.close();
    }
  }

  /// 从 ttwid.bytedance.com 拿 ttwid（设备追踪 cookie）
  static Future<String> _getTtwid() async {
    final client = http.Client();
    try {
      final resp = await client.post(
        Uri.parse('https://ttwid.bytedance.com/ttwid/union/register/'),
        headers: {'Content-Type': 'application/json', 'User-Agent': ua},
        body: jsonEncode({
          'region': 'cn',
          'aid': 1768,
          'needFid': false,
          'service': 'www.ixigua.com',
          'migrate_info': {'ticket': '', 'source': 'node'},
          'cbUrlProtocol': 'https',
          'union': true,
        }),
      );
      final cookie = resp.headers['set-cookie'] ?? '';
      final m = RegExp(r'ttwid=([^;]+)').firstMatch(cookie);
      if (m == null) throw DouyinParseException('获取 ttwid 失败');
      return m.group(1)!;
    } finally {
      client.close();
    }
  }

  /// msToken：抖音 web 校验较松，用两个 uuid hex 拼接模拟即可
  static String _getMsToken() {
    const uuid = Uuid();
    return uuid.v4().replaceAll('-', '') + uuid.v4().replaceAll('-', '');
  }

  /// 调 node 子进程跑 abogus.js 生成 a_bogus
  static Future<String> _generateABogus(String awemeId, String msToken) async {
    final nodePath = await BinaryLocator.getNodePath();
    final signDir = await BinaryInitializer.getDouyinSignDir();
    final script = '$signDir/abogus.js';
    final query =
        'device_platform=webapp&aid=6383&channel=channel_pc_web'
        '&aweme_id=$awemeId&msToken=$msToken';

    final result = await Process.run(nodePath, [script, query]).timeout(
      const Duration(seconds: 30),
    );
    if (result.exitCode != 0) {
      throw DouyinParseException(
        'a_bogus 生成失败 rc=${result.exitCode}: ${result.stderr}',
      );
    }
    final ab = (result.stdout as String).trim();
    if (ab.isEmpty) throw DouyinParseException('a_bogus 生成结果为空');
    return ab;
  }

  /// 调 aweme/detail，返回 aweme_detail
  static Future<Map<String, dynamic>> _fetchAwemeDetail(
    String awemeId,
    String msToken,
    String aBogus,
    String ttwid,
  ) async {
    final client = http.Client();
    try {
      final uri = Uri.parse('https://www.douyin.com/aweme/v1/web/aweme/detail/')
          .replace(queryParameters: {
        'device_platform': 'webapp',
        'aid': '6383',
        'channel': 'channel_pc_web',
        'aweme_id': awemeId,
        'msToken': msToken,
        'a_bogus': aBogus,
      });
      final resp = await client.get(uri, headers: {
        'User-Agent': ua,
        'Referer': 'https://www.douyin.com/video/$awemeId',
        'Cookie': 'ttwid=$ttwid',
      });
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final aweme = body['aweme_detail'] as Map<String, dynamic>?;
      if (aweme == null) {
        throw DouyinParseException(
          'aweme/detail 无数据: ${body['status_code']} ${(body['status_msg'] ?? '')}',
        );
      }
      return aweme;
    } finally {
      client.close();
    }
  }

  /// 解析 aweme_detail → VideoInfo
  static VideoInfo _parseAweme(String awemeId, Map<String, dynamic> aweme) {
    final desc = (aweme['desc'] as String?) ?? '';
    final author = (aweme['author'] as Map?)?['nickname'] as String? ?? '';
    final durationMs = (aweme['duration'] as num?)?.toInt() ?? 0;
    final video = (aweme['video'] as Map<String, dynamic>?) ?? const {};

    String firstUrl(dynamic addr) {
      if (addr is Map) {
        final urlList = addr['url_list'];
        if (urlList is List && urlList.isNotEmpty) {
          return urlList.first.toString();
        }
        final uri = addr['uri'];
        if (uri is String && uri.isNotEmpty) return uri;
      }
      return '';
    }

    final cover = firstUrl(video['cover']);
    final playAddr = firstUrl(video['play_addr']);

    final formats = <FormatOption>[];
    final bitRates = video['bit_rate'];
    if (bitRates is List) {
      for (final b in bitRates) {
        if (b is! Map) continue;
        final url = _noWatermark(firstUrl(b['play_addr']));
        if (url.isEmpty) continue;
        final gearName = (b['gear_name'] as String?) ?? '';
        formats.add(FormatOption(
          formatId: url,
          label: gearName.isNotEmpty ? gearName : 'MP4',
          height: 0,
          ext: 'mp4',
          needsMerge: false,
        ));
      }
    }
    if (formats.isEmpty && playAddr.isNotEmpty) {
      formats.add(FormatOption(
        formatId: _noWatermark(playAddr),
        label: '原画 MP4',
        height: 0,
        ext: 'mp4',
      ));
    }

    debugPrint('[抖音] 解析到: desc=$desc author=$author 格式数=${formats.length}');

    return VideoInfo(
      url: 'https://www.douyin.com/video/$awemeId',
      title: desc.isEmpty ? '抖音视频' : desc,
      duration: durationMs > 1000 ? durationMs ~/ 1000 : durationMs,
      uploader: author,
      thumbnail: cover,
      extractor: 'Douyin',
      videoId: awemeId,
      formats: formats,
    );
  }

  /// 去水印：playwm 地址换成 play
  static String _noWatermark(String url) => url.replaceAll('/playwm/', '/play/');
}
