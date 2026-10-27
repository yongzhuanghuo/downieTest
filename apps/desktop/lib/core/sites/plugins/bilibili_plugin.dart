import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../data/models/download_progress.dart';
import '../../../data/models/format_option.dart';
import '../../../data/models/video_info.dart';
import '../../ffmpeg/ffmpeg_runner.dart';
import '../../storage/site_cookies.dart';
import '../bilibili/bilibili_wbi.dart';
import '../site_plugin.dart';

/// Bilibili 普通视频插件。
///
/// 流程：b23.tv 短链展开 → finger/spi 取 buvid → nav 取 WBI key →
/// 签名调 wbi/view 拿 cid → 签名调 wbi/playurl 拿 DASH 流 →
/// 下载视频/音频后用 ffmpeg 合并。
///
/// 番剧（/bangumi/play/）走 pgc 接口；勾选「展开播放列表」时 ss 链接
/// 会解析整季并逐集入队。番剧由 [BilibiliBangumiPlugin] 单独注册，
/// 保证下载阶段能按 extractor 找回插件。
class BilibiliPlugin extends SitePlugin {
  @override
  String get id => 'Bilibili';

  @override
  String get displayName => '哔哩哔哩';

  @override
  int get priority => 90;

  static const String _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
  static const String _referer = 'https://www.bilibili.com/';
  static const String _api = 'https://api.bilibili.com';

  @override
  bool matches(Uri uri, String rawInput) {
    final host = uri.host.toLowerCase();
    if (host == 'b23.tv' || host.endsWith('.b23.tv')) return true;
    if (host == 'player.bilibili.com') {
      return uri.queryParameters.containsKey('bvid') ||
          uri.queryParameters.containsKey('aid') ||
          uri.queryParameters.containsKey('avid');
    }
    if (host == 'bilibili.com' || host.endsWith('.bilibili.com')) {
      return uri.path.startsWith('/video/') ||
          uri.path.startsWith('/bangumi/play/');
    }
    return false;
  }

  @override
  Future<VideoInfo> parse(String url) async {
    var resolved = await _expandShortLink(url);
    // 嵌入播放器：player.bilibili.com/player.html?bvid=... / aid=...
    final inputUri = Uri.parse(resolved);
    if (inputUri.host.toLowerCase() == 'player.bilibili.com') {
      final bvid = inputUri.queryParameters['bvid'];
      final aid = inputUri.queryParameters['aid'] ??
          inputUri.queryParameters['avid'];
      if (bvid != null && bvid.isNotEmpty) {
        resolved = 'https://www.bilibili.com/video/$bvid';
      } else if (aid != null && aid.isNotEmpty) {
        resolved = 'https://www.bilibili.com/video/av$aid';
      }
    }
    final uri = Uri.parse(resolved);

    // 番剧：ep/ss 走 pgc 接口
    if (uri.path.startsWith('/bangumi/play/')) {
      final cookie = await _cookieHeader();
      return _parseBangumi(uri, cookie);
    }

    final bv = RegExp(r'/video/(BV[0-9A-Za-z]+)').firstMatch(uri.path);
    final av = RegExp(r'/video/av(\d+)', caseSensitive: false)
        .firstMatch(uri.path);
    if (bv == null && av == null) {
      throw const SitePluginException(
        '该 B 站链接不是普通视频，交给 yt-dlp 处理',
        fallbackToYtDlp: true,
      );
    }

    final bvid = bv?.group(1);
    final aid = av?.group(1);
    final pageNo = int.tryParse(uri.queryParameters['p'] ?? '1') ?? 1;

    final cookie = await _cookieHeader();
    final wbi = await _fetchWbi(cookie);

    final view = await _getJson(
      '/x/web-interface/wbi/view?${wbi.sign({
        if (bvid != null) 'bvid': bvid,
        if (aid != null) 'aid': aid,
      })}',
      cookie,
    );
    _throwIfError(view);

    final data = view['data'] as Map<String, dynamic>?;
    if (data == null) {
      throw const SitePluginException('B 站返回数据为空', retryable: false);
    }

    final pages = (data['pages'] as List?) ?? const [];
    final index =
        pages.isEmpty ? 0 : (pageNo - 1).clamp(0, pages.length - 1).toInt();
    final pageData = pages.isNotEmpty
        ? (pages[index] as Map<String, dynamic>)
        : data;
    final cid =
        (pageData['cid'] as num?)?.toInt() ?? (data['cid'] as num?)?.toInt();
    if (cid == null) {
      throw const SitePluginException('无法获取 B 站 cid', retryable: false);
    }

    final play = await _getJson(
      '/x/player/wbi/playurl?${wbi.sign({
        if (bvid != null) 'bvid': bvid,
        if (aid != null) 'avid': aid,
        'cid': cid,
        'qn': 127,
        'fnval': 4048,
        'fourk': 1,
        'fnver': 0,
      })}',
      cookie,
    );
    _throwIfError(play);

    final playData = play['data'] as Map<String, dynamic>?;
    if (playData == null) {
      throw const SitePluginException('B 站播放信息为空', retryable: false);
    }

    final formats = _buildFormats(playData, data, pageData);
    if (formats.isEmpty) {
      throw const SitePluginException('B 站没有可用的视频流', retryable: false);
    }

    final title = (data['title'] as String?) ?? 'B 站视频';
    final part = (pageData['part'] as String?) ?? '';
    final displayTitle =
        pages.length > 1 && part.isNotEmpty ? '$title - $part' : title;
    final owner = (data['owner'] as Map?)?['name'] as String? ?? '';
    final duration = (pageData['duration'] as num?)?.toInt() ??
        (data['duration'] as num?)?.toInt() ??
        0;

    var pic = (data['pic'] as String?) ?? '';
    if (pic.startsWith('http://')) {
      pic = 'https://${pic.substring(7)}';
    }

    return VideoInfo(
      url: 'https://www.bilibili.com/video/${bvid ?? 'av$aid'}',
      title: displayTitle,
      duration: duration,
      uploader: owner,
      thumbnail: pic,
      extractor: id,
      videoId: bvid ?? 'av$aid',
      formats: formats,
      subtitleLangs: _subtitleLangs(playData),
      rawJson: data,
    );
  }

  @override
  Future<String> download(PluginDownloadRequest request) async {
    Map<String, dynamic> spec;
    try {
      spec = jsonDecode(request.task.formatId) as Map<String, dynamic>;
    } catch (_) {
      throw const SitePluginException('B 站下载参数无效', retryable: false);
    }

    final cookie = await _cookieHeader();
    final audioOnly = spec['audioOnly'] == true;
    final audioUrl = spec['a']?.toString() ?? '';
    final audioBackup = spec['ba']?.toString() ?? '';

    // durl/直链兜底：没有独立音频流，直接下到输出文件
    if (!audioOnly && audioUrl.isEmpty) {
      await _downloadStream(
        url: spec['v']?.toString() ?? '',
        backupUrl: spec['bv']?.toString() ?? '',
        path: request.outputPath,
        cookie: cookie,
        stage: DownloadStage.downloading,
        onProgress: request.onProgress,
        shouldCancel: request.shouldCancel,
      );
      return request.outputPath;
    }

    if (audioOnly) {
      final audioPath = '${request.outputPath}.audio.m4s';
      try {
        await _downloadStream(
          url: audioUrl,
          backupUrl: audioBackup,
          path: audioPath,
          cookie: cookie,
          stage: DownloadStage.downloadingAudio,
          onProgress: request.onProgress,
          shouldCancel: request.shouldCancel,
        );
        return await FFmpegRunner.convertToMp3(
          inputPath: audioPath,
          outputPath: request.outputPath,
        );
      } finally {
        await _deleteQuietly(audioPath);
      }
    }

    final videoPath = '${request.outputPath}.video.m4s';
    final audioPath = '${request.outputPath}.audio.m4s';
    try {
      await _downloadStream(
        url: spec['v']?.toString() ?? '',
        backupUrl: spec['bv']?.toString() ?? '',
        path: videoPath,
        cookie: cookie,
        stage: DownloadStage.downloadingVideo,
        onProgress: request.onProgress,
        shouldCancel: request.shouldCancel,
      );
      await _downloadStream(
        url: audioUrl,
        backupUrl: audioBackup,
        path: audioPath,
        cookie: cookie,
        stage: DownloadStage.downloadingAudio,
        onProgress: request.onProgress,
        shouldCancel: request.shouldCancel,
      );
      await FFmpegRunner.mergeVideoAudio(
        videoPath: videoPath,
        audioPath: audioPath,
        outputPath: request.outputPath,
        onProgress: (p) => request.onProgress(DownloadProgress(
          downloadedBytes: 0,
          totalBytes: null,
          speed: 0,
          percent: 0.9 + p * 0.1,
          stage: DownloadStage.merging,
        )),
      );
      return request.outputPath;
    } finally {
      await _deleteQuietly(videoPath);
      await _deleteQuietly(audioPath);
    }
  }

  /// 是否是整季番剧链接（/bangumi/play/ss<id>）。
  static bool looksLikeSeason(String url) =>
      RegExp(r'/bangumi/play/ss\d+').hasMatch(url);

  /// 整季解析：ss 链接逐集取播放信息，返回可直接入队的条目。
  /// 单集 ep 链接返回一条，调用方按普通视频处理。
  Future<List<VideoInfo>> parseSeason(String url) async {
    final resolved = await _expandShortLink(url);
    final uri = Uri.parse(resolved);
    final match = RegExp(r'/bangumi/play/(ep|ss)(\d+)').firstMatch(uri.path);
    if (match == null) return const [];

    final kind = match.group(1)!;
    final id = match.group(2)!;
    if (kind == 'ep') return [await _parseBangumi(uri, await _cookieHeader())];

    final cookie = await _cookieHeader();
    final seasonJson =
        await _getJson('/pgc/view/web/season?season_id=$id', cookie);
    _throwIfError(seasonJson);
    final result = seasonJson['result'] as Map<String, dynamic>?;
    if (result == null) {
      throw const SitePluginException('B 站番剧信息为空', retryable: false);
    }
    final episodes = _episodeMaps(result);
    if (episodes.isEmpty) {
      throw const SitePluginException('B 站番剧没有可下载的剧集', retryable: false);
    }

    final infos = <VideoInfo>[];
    for (final ep in episodes) {
      try {
        infos.add(await _buildBangumiEpisode(result, ep, cookie));
      } catch (e) {
        // 锁定/地区限制/需要大会员的单集跳过，不影响整季其他集。
        debugPrint('[B站番剧] 跳过一集: $e');
      }
    }
    if (infos.isEmpty) {
      throw const SitePluginException(
        '该番剧没有可下载的剧集（可能需要大会员或登录）',
        requiresLogin: true,
        retryable: false,
      );
    }
    return infos;
  }

  /// 纯函数：从 season 接口结果提取剧集页地址（按接口顺序、去重）。
  static List<String> episodeUrlsFromSeason(Map<String, dynamic> json) {
    final result = json['result'] is Map
        ? Map<String, dynamic>.from(json['result'] as Map)
        : json;
    final urls = <String>[];
    final seen = <String>{};
    for (final ep in _episodeMaps(result)) {
      final id = (ep['id'] ?? ep['ep_id'])?.toString() ?? '';
      if (id.isEmpty || id == '0' || !seen.add(id)) continue;
      urls.add('https://www.bilibili.com/bangumi/play/ep$id');
    }
    return urls;
  }

  static List<Map<String, dynamic>> _episodeMaps(Map<String, dynamic> result) {
    final top = (result['episodes'] as List?) ?? const <dynamic>[];
    final raw = top.isNotEmpty
        ? top
        : ((result['sections'] as List?) ?? const <dynamic>[])
            .whereType<Map>()
            .expand((section) =>
                (section['episodes'] as List?) ?? const <dynamic>[])
            .toList();
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// 番剧解析：支持 /bangumi/play/ep<id> 和 /bangumi/play/ss<id>。
  /// ss 链接默认取第一集；勾选「展开播放列表」时走 [parseSeason] 整季入队。
  Future<VideoInfo> _parseBangumi(Uri uri, String cookie) async {
    final match = RegExp(r'/bangumi/play/(ep|ss)(\d+)').firstMatch(uri.path);
    if (match == null) {
      throw const SitePluginException('无法识别 B 站番剧链接', retryable: false);
    }
    final kind = match.group(1)!;
    final id = match.group(2)!;

    final seasonPath = kind == 'ep'
        ? '/pgc/view/web/season?ep_id=$id'
        : '/pgc/view/web/season?season_id=$id';
    final seasonJson = await _getJson(seasonPath, cookie);
    _throwIfError(seasonJson);

    final result = seasonJson['result'] as Map<String, dynamic>?;
    if (result == null) {
      throw const SitePluginException('B 站番剧信息为空', retryable: false);
    }
    final episodes = _episodeMaps(result);
    if (episodes.isEmpty) {
      throw const SitePluginException('B 站番剧没有可下载的剧集', retryable: false);
    }

    Map<String, dynamic>? ep;
    if (kind == 'ep') {
      for (final e in episodes) {
        if (e['id']?.toString() == id || e['ep_id']?.toString() == id) {
          ep = e;
          break;
        }
      }
    }
    ep ??= episodes.first;
    return _buildBangumiEpisode(result, ep, cookie);
  }

  Future<VideoInfo> _buildBangumiEpisode(
    Map<String, dynamic> result,
    Map<String, dynamic> ep,
    String cookie,
  ) async {
    final epId = (ep['id'] ?? ep['ep_id'])?.toString() ?? '';
    final cid = _int(ep['cid']);
    if (cid <= 0) {
      throw const SitePluginException('无法获取番剧 cid', retryable: false);
    }

    final playJson = await _getJson(
      '/pgc/player/web/playurl?ep_id=$epId&cid=$cid&qn=127&fnval=4048&fourk=1',
      cookie,
    );
    _throwIfError(playJson);

    final playResult = playJson['result'] as Map<String, dynamic>?;
    if (playResult == null) {
      throw const SitePluginException('B 站番剧播放信息为空', retryable: false);
    }

    final formats = _buildFormats(playResult, result, ep);
    if (formats.isEmpty) {
      throw const SitePluginException('该番剧没有可用的视频流（可能需要大会员）', retryable: false);
    }

    final seasonTitle = (result['title'] as String?) ?? 'B 站番剧';
    final epNo = (ep['title'] as String?) ?? '';
    final epName = (ep['long_title'] as String?) ?? '';
    final epTitle = <String>[epNo, epName].where((e) => e.isNotEmpty).join(' ');
    var cover = (ep['cover'] ?? result['cover'] ?? '').toString();
    if (cover.startsWith('http://')) {
      cover = 'https://${cover.substring(7)}';
    }
    final upName = (result['up_info'] as Map?)?['uname'] as String? ?? '';

    return VideoInfo(
      url: 'https://www.bilibili.com/bangumi/play/ep$epId',
      title: epTitle.isEmpty ? seasonTitle : '$seasonTitle - $epTitle',
      duration: _int(ep['duration']),
      uploader: upName,
      thumbnail: cover,
      extractor: 'BilibiliBangumi',
      videoId: 'ep$epId',
      formats: formats,
      subtitleLangs: _subtitleLangs(playResult),
      rawJson: <String, dynamic>{'season': result, 'episode': ep},
    );
  }

  // ==================== 解析辅助 ====================

  List<FormatOption> _buildFormats(
    Map<String, dynamic> playData,
    Map<String, dynamic> videoData,
    Map<String, dynamic> pageData,
  ) {
    final duration = (pageData['duration'] as num?)?.toInt() ??
        (videoData['duration'] as num?)?.toInt() ??
        ((playData['timelength'] as num?)?.toInt() ?? 0) ~/ 1000;
    final qNames = _qualityNames(playData);

    final dash = playData['dash'] as Map<String, dynamic>?;
    if (dash != null) {
      final audios = ((dash['audio'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList()
        ..sort((a, b) => _int(b['bandwidth']).compareTo(_int(a['bandwidth'])));
      if (audios.isEmpty) return const [];

      final audio = audios.first;
      final audioUrl = _streamUrl(audio);
      final audioBackup = _streamBackup(audio);
      final audioBw = _int(audio['bandwidth']);

      final videos = ((dash['video'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .where((v) => _int(v['height']) > 0)
          .toList();
      final byHeight = <int, Map<String, dynamic>>{};
      for (final v in videos) {
        final h = _int(v['height']);
        final existing = byHeight[h];
        if (existing == null || _betterVideo(v, existing)) byHeight[h] = v;
      }

      final formats = <FormatOption>[];
      final heights = byHeight.keys.toList()..sort((a, b) => b.compareTo(a));
      for (final h in heights) {
        final v = byHeight[h]!;
        final videoUrl = _streamUrl(v);
        if (videoUrl.isEmpty) continue;

        final codecId = _int(v['codecid']);
        final qName = qNames[_int(v['id'])] ?? '';
        final label = <String>[
          qName.isNotEmpty ? qName : '${h}P',
          _codecName(codecId),
        ].where((e) => e.isNotEmpty).join(' ');
        final bw = _int(v['bandwidth']);

        formats.add(FormatOption(
          formatId: jsonEncode({
            'v': videoUrl,
            'a': audioUrl,
            'bv': _streamBackup(v),
            'ba': audioBackup,
            'h': h,
            'codec': codecId,
            'duration': duration,
          }),
          label: label,
          height: h,
          ext: 'mp4',
          needsMerge: true,
          fileSize: _estimateSize(bw + audioBw, duration),
          vbr: bw > 0 ? bw ~/ 1000 : null,
          abr: audioBw > 0 ? audioBw ~/ 1000 : null,
          fps: _intOrNull(v['frameRate'] ?? v['frame_rate']),
        ));
      }

      if (audioUrl.isNotEmpty) {
        formats.add(FormatOption(
          formatId: jsonEncode({
            'a': audioUrl,
            'ba': audioBackup,
            'audioOnly': true,
            'duration': duration,
          }),
          label: 'MP3 音频',
          height: 0,
          ext: 'mp3',
          audioOnly: true,
          fileSize: _estimateSize(audioBw, duration),
          abr: audioBw > 0 ? audioBw ~/ 1000 : null,
        ));
      }
      return formats;
    }

    // 非 DASH 兜底：单段 durl 可以直接直链下载。
    final durl = (playData['durl'] as List?) ?? const [];
    if (durl.length == 1 && durl.first is Map<String, dynamic>) {
      final d = durl.first as Map<String, dynamic>;
      final url = (d['url'] as String?) ?? '';
      if (url.isNotEmpty) {
        final ext = url.split('?').first.endsWith('.mp4') ? 'mp4' : 'flv';
        return [
          FormatOption(
            formatId: jsonEncode({'v': url, 'duration': duration}),
            label: qNames[_int(playData['quality'])] ?? 'B 站视频',
            height: 0,
            ext: ext,
          ),
        ];
      }
    }
    return const [];
  }

  bool _betterVideo(Map<String, dynamic> a, Map<String, dynamic> b) {
    final aAvc = _int(a['codecid']) == 7;
    final bAvc = _int(b['codecid']) == 7;
    if (aAvc != bAvc) return aAvc;
    return _int(a['bandwidth']) > _int(b['bandwidth']);
  }

  Map<int, String> _qualityNames(Map<String, dynamic> playData) {
    final ids = (playData['accept_quality'] as List?) ?? const [];
    final names = (playData['accept_description'] as List?) ?? const [];
    final map = <int, String>{};
    for (var i = 0; i < ids.length && i < names.length; i++) {
      map[_int(ids[i])] = names[i].toString();
    }
    return map;
  }

  List<String> _subtitleLangs(Map<String, dynamic> playData) {
    final subtitle = playData['subtitle'];
    if (subtitle is! Map) return const [];
    final subs = subtitle['subtitles'];
    if (subs is! List) return const [];
    return subs
        .whereType<Map>()
        .map((e) => (e['lan_doc'] ?? e['lan'] ?? '').toString())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  // ==================== 网络辅助 ====================

  Future<String> _expandShortLink(String url) async {
    var current = Uri.parse(url);
    if (current.host != 'b23.tv' && !current.host.endsWith('.b23.tv')) {
      return url;
    }
    final client = http.Client();
    try {
      for (var i = 0; i < 5; i++) {
        final req = http.Request('GET', current)..followRedirects = false;
        req.headers['User-Agent'] = _ua;
        final resp = await client.send(req).timeout(const Duration(seconds: 15));
        await resp.stream.drain<void>();
        final location = resp.headers['location'];
        if (location == null || location.isEmpty) break;
        current = current.resolve(location);
        final host = current.host.toLowerCase();
        if (host != 'b23.tv' && !host.endsWith('.b23.tv')) break;
      }
      return current.toString();
    } finally {
      client.close();
    }
  }

  Future<String> _cookieHeader() async {
    final saved = await SiteCookies.loadCookieHeader('bilibili');
    try {
      final spi = await _getJson('/x/frontend/finger/spi', saved);
      final data = spi['data'] as Map<String, dynamic>?;
      final b3 = data?['b_3']?.toString() ?? '';
      final b4 = data?['b_4']?.toString() ?? '';
      final hasB3 = saved.split(';').any((p) => p.trim().startsWith('buvid3='));
      final hasB4 = saved.split(';').any((p) => p.trim().startsWith('buvid4='));
      return <String>[
        if (saved.isNotEmpty) saved,
        if (!hasB3 && b3.isNotEmpty) 'buvid3=$b3',
        if (!hasB4 && b4.isNotEmpty) 'buvid4=$b4',
      ].join('; ');
    } catch (e) {
      debugPrint('[Bilibili] finger/spi 失败，使用已保存 cookie: $e');
      return saved;
    }
  }

  Future<BilibiliWbi> _fetchWbi(String cookie) async {
    final nav = await _getJson('/x/web-interface/nav', cookie);
    final data = nav['data'] as Map<String, dynamic>?;
    final wbi = data?['wbi_img'] as Map<String, dynamic>?;
    final img = wbi?['img_url']?.toString() ?? '';
    final sub = wbi?['sub_url']?.toString() ?? '';
    if (img.isEmpty || sub.isEmpty) {
      throw const SitePluginException('无法获取 B 站 WBI key', retryable: false);
    }
    return BilibiliWbi(imgUrl: img, subUrl: sub);
  }

  Future<Map<String, dynamic>> _getJson(String path, String cookie) async {
    final client = http.Client();
    try {
      final resp = await client.get(
        Uri.parse('$_api$path'),
        headers: {
          'User-Agent': _ua,
          'Referer': _referer,
          'Accept': 'application/json, text/plain, */*',
          if (cookie.isNotEmpty) 'Cookie': cookie,
        },
      ).timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) {
        throw SitePluginException(
          'B 站接口 HTTP ${resp.statusCode}（可能被风控）',
          retryable: resp.statusCode >= 500,
          requiresLogin: resp.statusCode == 403 || resp.statusCode == 412,
        );
      }
      final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        throw const SitePluginException(
          'B 站返回了非 JSON 响应（可能被风控）',
          retryable: false,
          requiresLogin: true,
        );
      }
      return decoded;
    } on FormatException {
      throw const SitePluginException(
        'B 站返回了非 JSON 响应（可能被风控）',
        retryable: false,
        requiresLogin: true,
      );
    } on SitePluginException {
      rethrow;
    } catch (e) {
      throw SitePluginException('B 站请求失败: $e', retryable: true);
    } finally {
      client.close();
    }
  }

  void _throwIfError(Map<String, dynamic> json) {
    final code = _int(json['code']);
    if (code == 0) return;
    final msg = json['message']?.toString() ?? '未知错误';

    late final String friendly;
    if (code == -404) {
      friendly = '视频不存在或已被删除';
    } else if (code == -403) {
      friendly = '该视频需要登录、会员或地区权限';
    } else if (code == -412) {
      friendly = 'B 站风控拦截，请登录后重试';
    } else if (code == -101) {
      friendly = '需要登录 B 站';
    } else if (code == 87007 || code == -10403) {
      friendly = '该番剧需要大会员或登录';
    } else {
      friendly = 'B 站接口错误: $code $msg';
    }

    throw SitePluginException(
      friendly,
      retryable: code >= 500 || code == -1,
      requiresLogin: code == -401 ||
          code == -403 ||
          code == -412 ||
          code == -101 ||
          code == 87007 ||
          code == -10403,
    );
  }

  Future<void> _downloadStream({
    required String url,
    required String backupUrl,
    required String path,
    required String cookie,
    required DownloadStage stage,
    required void Function(DownloadProgress) onProgress,
    required bool Function() shouldCancel,
  }) async {
    if (url.isEmpty) {
      throw const SitePluginException('B 站视频流地址为空', retryable: false);
    }

    final candidates = <String>[url, if (backupUrl.isNotEmpty) backupUrl];
    SitePluginException? lastError;
    for (final candidate in candidates) {
      final client = http.Client();
      try {
        final req = http.Request('GET', Uri.parse(candidate));
        req.headers['User-Agent'] = _ua;
        req.headers['Referer'] = _referer;
        if (cookie.isNotEmpty) req.headers['Cookie'] = cookie;

        final resp = await client.send(req).timeout(const Duration(seconds: 30));
        if (resp.statusCode != 200) {
          lastError = SitePluginException(
            'B 站下载失败 HTTP ${resp.statusCode}',
            retryable: resp.statusCode >= 500,
            requiresLogin:
                resp.statusCode == 403 || resp.statusCode == 412,
          );
          continue;
        }

        final total = resp.contentLength;
        final sink = File(path).openWrite();
        var downloaded = 0;
        final sw = Stopwatch()..start();
        try {
          await for (final chunk in resp.stream) {
            if (shouldCancel()) {
              throw const SitePluginException('已取消', retryable: false);
            }
            sink.add(chunk);
            downloaded += chunk.length;
            final elapsed = sw.elapsedMilliseconds / 1000.0;
            onProgress(DownloadProgress(
              downloadedBytes: downloaded,
              totalBytes: total,
              speed: elapsed > 0 ? downloaded / elapsed : 0,
              percent: total != null && total > 0 ? downloaded / total : null,
              stage: stage,
            ));
          }
          await sink.flush();
          await sink.close();
          return;
        } catch (e) {
          await sink.close();
          rethrow;
        }
      } on SitePluginException catch (e) {
        // 用户取消：直接抛出；其他错误继续试备用地址
        if (shouldCancel()) rethrow;
        lastError = e;
      } catch (e) {
        lastError = SitePluginException('B 站下载失败: $e', retryable: true);
      } finally {
        client.close();
      }
    }
    throw lastError ?? const SitePluginException('B 站下载失败', retryable: true);
  }

  Future<void> _deleteQuietly(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {
      // 忽略清理失败
    }
  }

  // ==================== 小工具 ====================

  int _int(Object? value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  int? _intOrNull(Object? value) {
    if (value is num) return value.toInt();
    if (value is String) return double.tryParse(value)?.toInt();
    return null;
  }

  String _streamUrl(Map<String, dynamic> m) =>
      (m['baseUrl'] ?? m['base_url'] ?? '').toString();

  String _streamBackup(Map<String, dynamic> m) {
    final list = m['backupUrl'] ?? m['backup_url'];
    if (list is List && list.isNotEmpty) return list.first.toString();
    return '';
  }

  int? _estimateSize(int bitsPerSecond, int seconds) {
    if (bitsPerSecond <= 0 || seconds <= 0) return null;
    return (bitsPerSecond * seconds / 8).round();
  }

  String _codecName(int codecId) {
    switch (codecId) {
      case 7:
        return 'AVC';
      case 12:
        return 'HEVC';
      case 13:
        return 'AV1';
      default:
        return codecId > 0 ? 'codec$codecId' : '';
    }
  }
}

/// 番剧单独注册：只匹配 /bangumi/play/(ep|ss)，解析和下载复用 [BilibiliPlugin]。
/// 独立 id 让站点覆盖表、分站子目录和下载分发与 Downie 的
/// BilibiliBangumiDownloader 对应。
class BilibiliBangumiPlugin extends BilibiliPlugin {
  @override
  String get id => 'BilibiliBangumi';

  @override
  int get priority => 91;

  @override
  bool matches(Uri uri, String rawInput) {
    final host = uri.host.toLowerCase();
    if (host != 'bilibili.com' && !host.endsWith('.bilibili.com')) {
      return false;
    }
    return RegExp(r'/bangumi/play/(ep|ss)\d+').hasMatch(uri.path);
  }
}
