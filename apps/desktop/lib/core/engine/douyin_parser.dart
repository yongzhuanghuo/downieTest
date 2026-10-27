import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../data/models/format_option.dart';
import '../../data/models/video_info.dart';
import '../platform/binary_initializer.dart';
import '../platform/binary_locator.dart';
import '../storage/site_cookies.dart';

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

  /// 登录浏览器拦截到的 aweme_detail 缓存。
  /// key 可以是原始短链、视频页 URL 或 `id:awemeId`。
  static final Map<String, VideoInfo> _captured = {};

  /// 登录窗口的 WebView 拦截到 aweme/detail 后调用。
  /// 查询登录浏览器已经缓存的视频数据。
  static VideoInfo? cachedVideo(String url) {
    final direct = _captured[url];
    if (direct != null) return direct;
    final id = _idFromUrl(url);
    return id == null ? null : _captured['id:$id'];
  }

  static bool cacheCaptured(
    String pageUrl,
    String responseText, {
    String? expectedId,
  }) {
    try {
      final json = jsonDecode(responseText);
      if (json is! Map) return false;
      dynamic aweme = json['aweme_detail'] ?? json['aweme'];
      if (aweme is! Map) {
        final list = json['aweme_list'];
        if (list is List && list.isNotEmpty) aweme = list.first;
      }
      // 直接就是 aweme 对象（含 video.play_addr）的情况
      if (aweme is! Map && json['video'] is Map) aweme = json;
      if (aweme is! Map) return false;
      final map = Map<String, dynamic>.from(aweme);
      final id = map['aweme_id']?.toString() ?? _idFromUrl(pageUrl) ?? '';
      if (id.isEmpty) return false;
      if (expectedId != null &&
          expectedId.isNotEmpty &&
          id != expectedId) {
        debugPrint('[抖音] 忽略非目标视频: $id != $expectedId');
        return false;
      }
      final info = _parseAweme(id, map);
      if (info.formats.isEmpty) return false;
      cacheInfo(pageUrl, info);
      debugPrint('[抖音] 缓存登录浏览器数据: $id 格式数=${info.formats.length}');
      return true;
    } catch (e) {
      debugPrint('[抖音] 解析登录浏览器数据失败: $e');
      return false;
    }
  }

  /// 缓存一条已经解析好的视频信息。
  static void cacheInfo(String pageUrl, VideoInfo info) {
    _captured[pageUrl] = info;
    _captured[info.url] = info;
    if (info.videoId.isNotEmpty) {
      _captured['id:${info.videoId}'] = info;
      _captured['https://www.douyin.com/video/${info.videoId}'] = info;
    }
  }

  /// 兜底缓存：登录浏览器没截到 aweme/detail，但播放器已经发出了
  /// Douyin DASH 的 video/audio 分轨。下载后由 ffmpeg 合并。
  static bool cacheMedia(
    String pageUrl, {
    required String videoUrl,
    required String audioUrl,
    String title = '',
    int height = 0,
  }) {
    if (videoUrl.isEmpty || audioUrl.isEmpty) return false;
    final id = _idFromUrl(pageUrl) ?? '';
    final cleanTitle = title
        .replaceAll(RegExp(r'\s*-\s*抖音\s*$'), '')
        .trim();
    final info = VideoInfo(
      url: id.isEmpty ? pageUrl : 'https://www.douyin.com/video/$id',
      title: cleanTitle.isEmpty ? '抖音视频' : cleanTitle,
      duration: 0,
      uploader: '',
      thumbnail: '',
      extractor: 'Douyin',
      videoId: id,
      formats: [
        FormatOption(
          formatId: '$videoUrl\n$audioUrl',
          label: height > 0 ? '${height}p MP4（合并）' : '原画 MP4（合并）',
          height: height,
          ext: 'mp4',
          needsMerge: true,
        ),
      ],
    );
    cacheInfo(pageUrl, info);
    debugPrint('[抖音] 使用媒体分轨兜底: id=$id height=$height');
    return true;
  }

  /// 解析抖音链接，返回 VideoInfo（extractor='Douyin'，formats 的 formatId 为直链）
  static Future<VideoInfo> parse(String url) async {
    final cached = cachedVideo(url);
    if (cached != null) return cached;

    final awemeId = await _expand(url);
    debugPrint('[抖音] aweme_id=$awemeId');
    final cachedById = _captured['id:$awemeId'];
    if (cachedById != null) return cachedById;

    final ttwid = await _getTtwid();
    // 登录浏览器保存下来的 cookie（可能包含 sessionid / msToken）
    final savedCookie = await SiteCookies.loadCookieHeader('douyin');
    final savedMs = RegExp(r'(?:^|;\s*)msToken=([^;]+)')
        .firstMatch(savedCookie)
        ?.group(1);
    final msToken = savedMs ?? _getMsToken();
    final aBogus = await _generateABogus(awemeId, msToken);
    debugPrint('[抖音] a_bogus 长度=${aBogus.length}，savedCookie=${savedCookie.isNotEmpty}');

    final detail = await _fetchAwemeDetail(
      awemeId,
      msToken,
      aBogus,
      ttwid,
      savedCookie,
    );
    return _parseAweme(awemeId, detail);
  }

  /// 短链展开，取 aweme_id。
  /// http 包自动跟随重定向后 request.url 仍是原始短链，所以手动循环追 Location。
  static Future<String> _expand(String url) async {
    final client = http.Client();
    try {
      final savedCookie = await SiteCookies.loadCookieHeader('douyin');
      var current = Uri.parse(url);
      // 短链可能 302 多次（v.douyin.com → www.douyin.com/video/xxx），最多追 5 跳
      for (var i = 0; i < 5; i++) {
        final id = _idFromUrl(current.toString());
        if (id != null) return id;
        final req = http.Request('GET', current);
        req.followRedirects = false;
        req.headers['User-Agent'] = ua;
        req.headers['Accept'] = 'text/html,application/xhtml+xml';
        req.headers['Accept-Language'] = 'zh-CN,zh;q=0.9';
        if (savedCookie.isNotEmpty) req.headers['Cookie'] = savedCookie;
        final resp = await client.send(req);
        final location = resp.headers['location'];
        if (location == null || location.isEmpty) break;
        current = current.resolve(location);
      }
      final id = _idFromUrl(current.toString());
      if (id != null) return id;
      throw DouyinParseException('无法从链接提取 aweme_id');
    } finally {
      client.close();
    }
  }

  static String? _idFromUrl(String url) {
    final patterns = [
      RegExp(r'/video/(\d+)'),
      RegExp(r'/note/(\d+)'),
      RegExp(r'/vsdetail/(\d+)'),
      RegExp(r'[?&](?:modal_id|vid|aweme_id)=(\d+)'),
    ];
    for (final pattern in patterns) {
      final m = pattern.firstMatch(url);
      if (m != null) return m.group(1);
    }
    // 最后才用「任意 15 位以上数字」，避免误取时间戳等
    final fallback = RegExp(r'(\d{15,})').firstMatch(url);
    return fallback?.group(1);
  }

  /// 从链接提取 aweme_id（供登录窗口做目标校验）。
  static String? videoIdFromUrl(String url) => _idFromUrl(url);

  /// 只匹配明确的视频页参数，不做「任意 15 位数字」兜底。
  /// 用于校验登录浏览器抓到的是不是当前视频，避免短链里的数字误判。
  static String? pageVideoId(String url) {
    final patterns = [
      RegExp(r'/(?:video|note|vsdetail)/(\d+)'),
      RegExp(r'[?&](?:modal_id|vid|aweme_id)=(\d+)'),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(url);
      if (match != null) return match.group(1);
    }
    return null;
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
    String savedCookie,
  ) async {
    final client = http.Client();
    try {
      final hasSavedTtwid =
          RegExp(r'(?:^|;\s*)ttwid=').hasMatch(savedCookie);
      final cookie = hasSavedTtwid
          ? savedCookie
          : ['ttwid=$ttwid', if (savedCookie.isNotEmpty) savedCookie].join('; ');
      final uri = Uri.parse('https://www.douyin.com/aweme/v1/web/aweme/detail/')
          .replace(queryParameters: {
        'device_platform': 'webapp',
        'aid': '6383',
        'channel': 'channel_pc_web',
        'aweme_id': awemeId,
        'msToken': msToken,
        'a_bogus': aBogus,
      });
      final uifid = RegExp(r'(?:^|;\s*)(?:UIFID|uifid)=([^;]+)')
          .firstMatch(savedCookie)
          ?.group(1);
      final resp = await client.get(uri, headers: {
        'User-Agent': ua,
        'Referer': 'https://www.douyin.com/video/$awemeId',
        'Origin': 'https://www.douyin.com',
        'Accept': 'application/json, text/plain, */*',
        'Accept-Language': 'zh-CN,zh;q=0.9',
        'Sec-Fetch-Site': 'same-origin',
        'Sec-Fetch-Mode': 'cors',
        'Sec-Fetch-Dest': 'empty',
        if (uifid != null && uifid.isNotEmpty) 'UIFID': uifid,
        'Cookie': cookie,
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
    final authorInfo = aweme['author'] ?? aweme['authorInfo'];
    final authorRaw = authorInfo is Map ? authorInfo['nickname'] : null;
    final author = authorRaw is String ? authorRaw : '';
    final durationMs = (aweme['duration'] as num?)?.toInt() ?? 0;
    final video = (aweme['video'] as Map<String, dynamic>?) ?? const {};

    String firstUrl(dynamic addr) {
      if (addr is List) {
        for (final item in addr) {
          final url = firstUrl(item);
          if (url.isNotEmpty) return url;
        }
        return '';
      }
      if (addr is Map) {
        final urlList = addr['url_list'];
        if (urlList is List) {
          for (final item in urlList) {
            final url = item?.toString() ?? '';
            if (url.startsWith('http')) return url;
          }
        }
        for (final key in ['src', 'uri']) {
          final value = addr[key];
          if (value is String && value.startsWith('http')) return value;
        }
      }
      if (addr is String && addr.startsWith('http')) return addr;
      return '';
    }

    int heightOf(dynamic addr, Map b) {
      final raw = (addr is Map ? addr['height'] : null) ?? b['height'];
      return raw is num ? raw.toInt() : 0;
    }

    String labelFor(Map b, int height) {
      final h265 = b['is_bytevc1'] == 1 || b['is_h265'] == 1;
      final suffix = h265 ? ' H.265' : '';
      if (height > 0) return '${height}p$suffix';
      final gear = (b['gear_name'] as String?) ?? '';
      return gear.isNotEmpty ? '$gear$suffix' : 'MP4$suffix';
    }

    final formats = <FormatOption>[];
    final seen = <String>{};
    void addFormat(String url, String label, int height) {
      final normalized = _noWatermark(url);
      if (normalized.isEmpty || !seen.add(normalized)) return;
      formats.add(FormatOption(
        formatId: normalized,
        label: label,
        height: height,
        ext: 'mp4',
        needsMerge: false,
      ));
    }

    final cover = firstUrl(video['cover']);
    final bitRates = video['bit_rate'];
    if (bitRates is List) {
      for (final b in bitRates) {
        if (b is! Map) continue;
        final addr = b['play_addr'] ?? b['playAddr'];
        final url = firstUrl(addr);
        if (url.isEmpty) continue;
        final height = heightOf(addr, b);
        addFormat(url, labelFor(b, height), height);
      }
    }
    if (formats.isEmpty) {
      for (final key in ['play_addr_h264', 'play_addr', 'play_addr_265']) {
        final addr = video[key];
        final url = firstUrl(addr);
        if (url.isEmpty) continue;
        final height = addr is Map && addr['height'] is num
            ? (addr['height'] as num).toInt()
            : 0;
        addFormat(url, height > 0 ? '${height}p' : '原画 MP4', height);
        if (formats.isNotEmpty) break;
      }
    }
    if (formats.isEmpty) {
      final url = firstUrl(video['playAddr'] ?? video['play_addr']);
      if (url.isNotEmpty) addFormat(url, '原画 MP4', 0);
    }
    formats.sort((a, b) => b.height.compareTo(a.height));

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
