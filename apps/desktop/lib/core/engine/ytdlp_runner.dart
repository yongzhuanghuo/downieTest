import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../data/models/download_progress.dart';
import '../../data/models/format_option.dart';
import '../../data/models/video_info.dart';
import '../ffmpeg/ffmpeg_runner.dart';
import '../platform/binary_locator.dart';
import '../platform/system_proxy.dart';
import '../storage/settings_storage.dart';
import '../storage/site_cookies.dart';
import 'chunked_http_downloader.dart';

/// yt-dlp 解析异常
class YtDlpException implements Exception {
  final String message;
  final int? exitCode;
  final String? stderr;

  const YtDlpException(this.message, {this.exitCode, this.stderr});

  @override
  String toString() => 'YtDlpException: $message';
}

/// 是否为 YouTube 链接（引擎层不依赖 features 层）。
bool _isYouTubeUrl(String url) {
  final lower = url.toLowerCase();
  return lower.contains('youtube.com') || lower.contains('youtu.be');
}

/// 实际生效的 HTTP 分块大小（MB，0=不分块）。
///
/// YouTube 的直链下载会被服务器按连接限速，表现为下载几十秒后速度骤降。
/// Downie 对 YouTube 固定用 10 MiB 分块来绕开这种限速（普通 HTTP 用 2 MB）。
/// 这里只对 YouTube 自动启用；用户显式设置了分块大小时以用户设置为准。
@visibleForTesting
int effectiveHttpChunkSizeMb(String url, int configuredMb) {
  if (configuredMb > 0) return configuredMb;
  return _isYouTubeUrl(url) ? 10 : 0;
}

/// YouTube 需要的额外 yt-dlp 参数（纯函数，便于测试）。
///
/// 2026 起 YouTube 用 n-sig 挑战过滤视频格式：没有 JS runtime + EJS 时
/// `-F` 只剩 storyboard。`web_safari` 还能拿到不依赖 GVS PO Token 的
/// HLS 格式，所以显式加入 client 列表。
@visibleForTesting
List<String> buildYouTubeArgs(String url, {String? nodePath}) {
  if (!_isYouTubeUrl(url)) return const [];
  return [
    if (nodePath != null && nodePath.isNotEmpty)
      ...['--js-runtimes', 'node:$nodePath'],
    '--extractor-args', 'youtube:player_client=default,web_safari',
  ];
}

/// 配置了浏览器 Cookie 时，YouTube 不再使用任何 Netscape cookie 文件。
///
/// 只跳过 `youtube.txt` 不够：站点 cookie 文件（例如 `douyin.txt`）可能
/// 混入旧的/跨域 YouTube cookie，和浏览器 Cookie 一起传给 yt-dlp 时会
/// 覆盖浏览器登录态，导致明明浏览器已登录仍然报 bot check。
@visibleForTesting
List<String> filterCookiePathsForSite(
  List<String> paths, {
  required String url,
  required String browser,
}) {
  if (browser.isEmpty || !_isYouTubeUrl(url)) return paths;
  return const [];
}

/// yt-dlp 引擎封装
///
/// 提供视频解析与下载能力。所有方法均通过子进程调用 yt-dlp 二进制。
class YtDlpRunner {
  YtDlpRunner._();

  /// 获取 yt-dlp 版本
  static Future<String> getVersion() async {
    final result = await _runCommand(['--version']);
    if (result.exitCode != 0) {
      throw YtDlpException(
        '获取版本失败',
        exitCode: result.exitCode,
        stderr: result.stderr,
      );
    }
    return result.stdout.trim();
  }

  /// 更新 yt-dlp 到最新版
  ///
  /// `yt-dlp -U` 内部会对比当前版本，只有发现新版才下载替换自己；
  /// 已是最新时直接返回「已是最新版」，不会重复下载。
  /// 返回 (是否成功, 更新后版本, 提示信息)。
  ///
  /// 注意：只有打包版内嵌的 standalone 二进制支持 `-U` 自更新；
  /// 开发态走 PATH 的 brew/pip 版会被禁用（提示用 pip 更新），返回失败即可静默跳过。
  static Future<({bool ok, String version, String message})> update() async {
    final before = await getVersion();
    // SABR 版是固定 fork 构建，`yt-dlp -U` 会把它换回正式版并丢失 YouTube
    // SABR 下载能力；必须随 App 一起更新。
    if (BinaryLocator.ytDlpBuildId.isNotEmpty) {
      return (
        ok: false,
        version: before,
        message: '当前为 SABR 构建，请随 App 更新（不支持 yt-dlp -U）',
      );
    }
    final result = await _runCommand(['-U', '--no-warnings']);
    final after = await getVersion();
    if (result.exitCode != 0) {
      return (
        ok: false,
        version: before,
        message: '更新失败: ${_extractErrorMessage(result.stderr)}',
      );
    }
    if (after == before && !result.stdout.contains('Updated')) {
      return (ok: true, version: after, message: '已是最新版 $after');
    }
    return (ok: true, version: after, message: '已更新到 $after');
  }

  /// 解析视频信息（不下载）
  ///
  /// [url] 视频 URL
  /// 返回包含标题、时长、格式列表等信息的 [VideoInfo]
  static Future<VideoInfo> parse(String url) async {
    // 站点登录 cookie（解析阶段也可能需要，如抖音）
    final cookiePaths = await SiteCookies.allCookieFilePaths();
    debugPrint(
      '[解析] cookie: ${cookiePaths.isEmpty ? '无' : cookiePaths.join(', ')}',
    );
    for (final cp in cookiePaths) {
      try {
        final lines = await File(cp).readAsLines();
        final names = lines
            .where((l) => l.isNotEmpty && !l.startsWith('#'))
            .map((l) => l.split('\t').length >= 6 ? l.split('\t')[5] : '?')
            .toList();
        // 关键登录态/反爬 cookie 概览：抖音缺 msToken 就是 Fresh cookies 的直接原因
        final hasMsToken = names.contains('msToken');
        final hasSession = names.any(
          (n) =>
              n.contains('session') ||
              n.contains('sid_') ||
              n.contains('login_time'),
        );
        debugPrint(
          '[解析]   $cp 共 ${names.length} 条，'
          'msToken=${hasMsToken ? '有' : '❌无'}，'
          '登录态cookie=${hasSession ? '有' : '❌无'}',
        );
        debugPrint('[解析]   名字: ${names.join(', ')}');
      } catch (e) {
        debugPrint('[解析]   读 cookie 文件失败: $e');
      }
    }
    final proxy = await _resolveProxy();
    // 使用 --dump-json 输出单行 JSON。
    // 不支持的长尾页面会卡到网络超时；这里最多等 15 秒，让 UI 尽快
    // 提示「用户自定义提取」，而不是一直转圈。
    //
    // YouTube 例外：浏览器 Cookie 提取（Edge 实测约 19s）、多个 player
    // 配置请求、n-sig/EJS 求解叠加后实测要 50～60s。15 秒硬超时会让
    // YouTube 每次都报「解析超时」，所以单独放宽到 90 秒。
    final timeout = _isYouTubeUrl(url)
        ? const Duration(seconds: 90)
        : const Duration(seconds: 15);
    final result = await _runCommand(
      [
        '--dump-json',
        '--no-warnings',
        '--no-playlist',
        '--socket-timeout', '8',
        if (proxy.isNotEmpty) ...['--proxy', proxy],
        ...await _youtubeArgs(url),
        ..._cookieArgs(cookiePaths, url: url),
        url,
      ],
      timeout: timeout,
    );

    if (result.exitCode != 0) {
      // YouTube 的 --dump-json 阶段报 Requested format is not available，
      // 说明播放器响应里一个可下载格式都没有（常见于风控/未登录，只剩
      // storyboard）。映射成登录提示，让 UI 弹登录窗口，而不是误导成
      // 「所选画质不可用」。
      if (_isYouTubeUrl(url) &&
          result.stderr.contains('Requested format is not available')) {
        throw YtDlpException(
          '解析失败: YouTube 未返回可下载格式，需要登录/验证',
          exitCode: result.exitCode,
          stderr: result.stderr,
        );
      }
      throw YtDlpException(
        '解析失败: ${_extractErrorMessage(result.stderr)}',
        exitCode: result.exitCode,
        stderr: result.stderr,
      );
    }

    final stdout = result.stdout.trim();
    if (stdout.isEmpty) {
      throw const YtDlpException('解析返回空结果');
    }

    // yt-dlp 对含多个 <video> 的页面（如奈飞被 generic extractor 兜底）会输出
    // 多行 JSON，每行一个 entry；逐行解析，取第一个能解析成功的 JSON 对象。
    Map<String, dynamic>? json;
    String? lastError;
    for (final line in stdout.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      try {
        json = jsonDecode(trimmed) as Map<String, dynamic>;
        break;
      } catch (e) {
        lastError = e.toString();
      }
    }
    if (json == null) {
      throw YtDlpException('JSON 解析失败: $lastError');
    }

    return _parseVideoInfo(url, json);
  }

  /// URL 是否像播放列表（用户勾选「展开播放列表」时才用）。
  static bool looksLikePlaylist(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final query = uri.queryParameters;
    if (query.containsKey('list') || query.containsKey('playlist')) {
      return true;
    }
    final path = uri.path.toLowerCase();
    return path.contains('/playlist') ||
        path.contains('/sets/') ||
        path.contains('/album/') ||
        path.contains('/show/');
  }

  /// 展开播放列表（只取条目信息，不逐个解析格式）。
  ///
  /// 每个条目使用 `bv*+ba/b` 作为下载格式，由 yt-dlp 在下载时选最佳流。
  static Future<List<VideoInfo>> parsePlaylist(String url) async {
    final cookiePaths = await SiteCookies.allCookieFilePaths();
    final proxy = await _resolveProxy();
    final result = await _runCommand([
      '--flat-playlist',
      '--dump-json',
      '--no-warnings',
      '--yes-playlist',
      if (proxy.isNotEmpty) ...['--proxy', proxy],
      ...await _youtubeArgs(url),
      ..._cookieArgs(cookiePaths, url: url),
      url,
    ]);
    if (result.exitCode != 0) {
      throw YtDlpException(
        '播放列表解析失败: ${_extractErrorMessage(result.stderr)}',
        exitCode: result.exitCode,
        stderr: result.stderr,
      );
    }
    return parsePlaylistJson(result.stdout, url);
  }

  /// 解析 `--flat-playlist --dump-json` 的多行输出（纯函数，便于测试）。
  static List<VideoInfo> parsePlaylistJson(
    String stdout,
    String playlistUrl, {
    int limit = 200,
  }) {
    final result = <VideoInfo>[];
    final seen = <String>{};
    for (final line in stdout.split('\n')) {
      if (result.length >= limit) break;
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      Map<String, dynamic> json;
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is! Map) continue;
        json = Map<String, dynamic>.from(decoded);
      } catch (_) {
        continue;
      }

      var webpage = (json['webpage_url'] ?? json['url'])?.toString() ?? '';
      if (webpage.startsWith('/')) {
        final base = Uri.tryParse(playlistUrl);
        if (base != null) webpage = base.resolve(webpage).toString();
      }
      if (!webpage.startsWith('http')) continue;
      if (!seen.add(webpage)) continue;

      result.add(
        VideoInfo(
          url: webpage,
          title: json['title'] as String? ?? '未命名视频',
          duration: (json['duration'] as num?)?.toInt() ?? 0,
          uploader:
              json['uploader'] as String? ?? json['channel'] as String? ?? '',
          thumbnail: _playlistThumbnail(json),
          extractor:
              json['extractor_key'] as String? ??
              json['extractor'] as String? ??
              'Unknown',
          videoId: json['id']?.toString() ?? '',
          formats: const [
            FormatOption(
              formatId: 'bv*+ba/b',
              label: '最佳画质',
              height: 0,
              ext: 'mp4',
              needsMerge: true,
            ),
          ],
          playlistTitle: json['playlist_title'] as String? ?? '',
          rawJson: json,
        ),
      );
    }
    return result;
  }

  static String _playlistThumbnail(Map<String, dynamic> json) {
    final direct = json['thumbnail']?.toString();
    if (direct != null && direct.isNotEmpty) return direct;
    final thumbs = json['thumbnails'];
    if (thumbs is List && thumbs.isNotEmpty) {
      final last = thumbs.last;
      if (last is Map) return last['url']?.toString() ?? '';
    }
    return '';
  }

  /// 下载视频
  ///
  /// [url] 视频 URL
  /// [formatId] yt-dlp 格式 ID（如 "137+140"）
  /// [outputPath] 输出文件路径模板（不含扩展名，yt-dlp 会自动加扩展名）
  /// [onProgress] 进度回调
  /// [shouldCancel] 取消检查器，返回 true 时终止下载
  static Future<String> download({
    required String url,
    required String formatId,
    required String outputPath,
    required void Function(DownloadProgress) onProgress,
    bool Function()? shouldCancel,
    bool audioOnly = false,
    bool downloadSubtitles = false,
    bool downloadCover = false,
    int throttleKbps = 0,
    int connections = 0,
    String? logPath,
    String? referer,
    String? userAgent,
    String? cookieHeader,
    bool passCookies = true,
    bool forceNativeFragments = false,
  }) async {
    final ytDlpPath = await BinaryLocator.getYtDlpPath();
    final ffmpegPath = await BinaryLocator.getFFmpegPath();

    // 占位任务解析失败后点「重试」时 formatId 仍为空，yt-dlp 会直接报
    // "Requested format is not available"；回退到最佳画质，别让用户卡死。
    final effectiveFormatId = formatId.trim().isEmpty ? 'bv*+ba/b' : formatId;

    debugPrint('[YtDlp] ytDlpPath: $ytDlpPath');
    debugPrint('[YtDlp] ffmpegPath: $ffmpegPath');
    debugPrint('[YtDlp] formatId: $effectiveFormatId');

    // 验证 ffmpeg 可执行（合并音视频流必需）
    String actualFfmpegPath = ffmpegPath;
    if (effectiveFormatId.contains('+')) {
      bool ffOk = false;
      try {
        final ffCheck = Process.runSync(ffmpegPath, ['-version']);
        ffOk = ffCheck.exitCode == 0;
        debugPrint('[YtDlp] ffmpeg 可执行: exitCode=${ffCheck.exitCode}');
      } catch (e) {
        debugPrint('[YtDlp] ⚠️ ffmpeg 不可执行: $e');
      }
      if (!ffOk) {
        // 尝试从 PATH 查找
        try {
          final which = await Process.run('which', ['ffmpeg']);
          if (which.exitCode == 0) {
            actualFfmpegPath = (which.stdout as String).trim();
            debugPrint('[YtDlp] 从 PATH 找到 ffmpeg: $actualFfmpegPath');
          }
        } catch (_) {}
        // 再次验证
        try {
          final recheck = Process.runSync(actualFfmpegPath, ['-version']);
          if (recheck.exitCode != 0) {
            throw YtDlpException('ffmpeg 不可用，无法合并音视频流。路径: $actualFfmpegPath');
          }
        } catch (e) {
          throw YtDlpException('ffmpeg 不可用，无法合并音视频流。请确认 ffmpeg 已安装。');
        }
      }
    }

    // 站点登录 cookie：把所有已登录站点的 cookies.txt 都传给 yt-dlp（按域名自动匹配）。
    // 自定义提取已经带了页面原生 Cookie 时不再叠加站点/浏览器 Cookie，
    // 否则两套登录态会互相覆盖。
    final cookiePaths = passCookies
        ? await SiteCookies.allCookieFilePaths()
        : const <String>[];
    debugPrint(
      '[YtDlp] 下载使用 cookie: ${cookiePaths.isEmpty ? '无' : cookiePaths.join(', ')}',
    );

    final settings = SettingsStorage.instance.current;
    final proxy = await _resolveProxy();
    debugPrint('[YtDlp] proxy: ${proxy.isEmpty ? 'direct' : proxy}');
    final effectiveConnections = connections > 0
        ? connections
        : settings.connectionsPerDownload;
    final subtitleLangs = settings.subtitleLangs.replaceAll(RegExp(r'\s+'), '');
    final chunkSizeMb = effectiveHttpChunkSizeMb(url, settings.chunkSizeMb);

    // YouTube 的整文件直链优先走多连接 Range 下载；HLS/DASH 分片、
    // 字幕/封面/重编码等仍交给 yt-dlp 子进程。
    if (_isYouTubeUrl(url) &&
        !audioOnly &&
        !downloadSubtitles &&
        !downloadCover &&
        !settings.forceReencode &&
        !settings.saveMetadataJson) {
      try {
        final chunked = await _tryChunkedYouTubeDownload(
          url: url,
          formatId: effectiveFormatId,
          outputPath: outputPath,
          onProgress: onProgress,
          shouldCancel: () => shouldCancel?.call() ?? false,
          proxy: proxy,
          connections: effectiveConnections,
          chunkSizeMb: chunkSizeMb,
          logPath: logPath,
        );
        if (chunked != null) {
          debugPrint('[YtDlp] YouTube 分块直链下载完成: $chunked');
          return chunked;
        }
      } on DownloadCancelledException {
        throw const YtDlpException('已取消');
      } on FFmpegException catch (e) {
        // 已经下载完再回退会白白重下一遍；合并失败直接报错。
        throw YtDlpException('分块下载完成但合并失败：${e.message}');
      } on ChunkedDownloadException catch (e) {
        debugPrint('[YtDlp] YouTube 分块直链失败，回退 yt-dlp: $e');
      } catch (e) {
        debugPrint('[YtDlp] YouTube 分块直链异常，回退 yt-dlp: $e');
      }
    }

    final args = <String>[
      '--newline', // 每行一个进度，便于解析
      '--no-warnings',
      '--no-playlist',
      '--socket-timeout', '15',
      if (proxy.isNotEmpty) ...['--proxy', proxy],
      '-f', effectiveFormatId,
      '-o', outputPath,
      '--ffmpeg-location', actualFfmpegPath,
      // 自定义提取的 HLS/DASH：强制用原生分片下载器，--concurrent-fragments 才生效。
      // 默认的 ffmpeg HLS 下载是单连接顺序拉流，会慢一个数量级。
      if (forceNativeFragments) ...['--downloader', 'dash,m3u8:native'],
      if (referer != null && referer.trim().isNotEmpty) ...[
        '--referer',
        referer.trim(),
      ],
      if (userAgent != null && userAgent.trim().isNotEmpty) ...[
        '--user-agent',
        userAgent.trim(),
      ],
      if (cookieHeader != null && cookieHeader.trim().isNotEmpty) ...[
        '--add-header',
        'Cookie: ${cookieHeader.trim()}',
      ],
      if (effectiveConnections > 1) ...[
        '--concurrent-fragments',
        '$effectiveConnections',
      ],
      if (chunkSizeMb > 0) ...['--http-chunk-size', '${chunkSizeMb}M'],
      if ((throttleKbps > 0 ? throttleKbps : settings.throttleKbps) > 0) ...[
        '--limit-rate',
        '${throttleKbps > 0 ? throttleKbps : settings.throttleKbps}K',
      ],
      if (settings.saveMetadataJson) '--write-info-json',
      if (settings.forceReencode) ...['--recode-video', 'mp4'],
      if (settings.nativeHlsEngine) '--hls-prefer-native',
      if (audioOnly) ...['-x', '--audio-format', settings.preferredAudioFormat],
      if (!audioOnly) ...['--merge-output-format', 'mp4'],
      if (downloadSubtitles) ...[
        '--write-subs',
        if (settings.includeAutoSubtitles) '--write-auto-subs',
        if (!settings.keepSubtitleFormat) ...['--convert-subs', 'srt'],
        if (subtitleLangs.isNotEmpty) ...[
          '--sub-langs',
          settings.subtitleMode == 1
              ? subtitleLangs.split(',').first
              : subtitleLangs,
        ],
      ],
      // --write-thumbnail 只写一张默认封面（即最高清那张），--write-all-thumbnails 才会写多张
      if (downloadCover) ...[
        '--write-thumbnail',
        '--convert-thumbnails',
        'jpg',
      ],
      ...await _youtubeArgs(url),
      if (passCookies) ..._cookieArgs(cookiePaths, url: url),
      url,
    ];

    File? logFile;
    if (logPath != null && logPath.isNotEmpty) {
      try {
        logFile = File(logPath);
        await logFile.parent.create(recursive: true);
        await logFile.writeAsString(
          '[cmd] $ytDlpPath ${args.join(' ')}\n',
          mode: FileMode.append,
        );
      } catch (_) {
        logFile = null;
      }
    }

    final process = await Process.start(
      ytDlpPath,
      args,
      environment: _processEnv,
    );
    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();

    // 监听 stdout（进度行）
    final stdoutSub = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          stdoutBuffer.writeln(line);
          final progress = parseProgressLine(line);
          if (progress != null) {
            onProgress(progress);
          }
        });

    // 监听 stderr（错误/警告）
    final stderrSub = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          stderrBuffer.writeln(line);
        });

    // 取消检查
    Timer? cancelTimer;
    if (shouldCancel != null) {
      cancelTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
        if (shouldCancel()) {
          process.kill(ProcessSignal.sigterm);
          timer.cancel();
        }
      });
    }

    final exitCode = await process.exitCode;
    await stdoutSub.cancel();
    await stderrSub.cancel();
    cancelTimer?.cancel();

    // 诊断日志：打印 yt-dlp 完整输出
    final fullStdout = stdoutBuffer.toString();
    final fullStderr = stderrBuffer.toString();
    if (logFile != null) {
      try {
        await logFile.writeAsString(
          'exitCode=$exitCode\n'
          '--- stdout ---\n$fullStdout\n'
          '--- stderr ---\n$fullStderr\n',
          mode: FileMode.append,
        );
      } catch (_) {}
    }
    debugPrint('[YtDlp] exitCode=$exitCode');
    debugPrint('[YtDlp] stdout:\n$fullStdout');
    if (fullStderr.trim().isNotEmpty) {
      debugPrint('[YtDlp] stderr:\n$fullStderr');
    }

    if (exitCode != 0) {
      // 解析时选中的格式可能在下一次 player 请求里消失（例如 140-drc
      // 这类实验性音轨）。自动退回最佳画质再试一次，避免用户只能手动
      // 重新解析；bv*+ba/b 再失败就正常报错，不会递归。
      if (fullStderr.contains('Requested format is not available') &&
          effectiveFormatId != 'bv*+ba/b') {
        debugPrint(
          '[YtDlp] 格式 $effectiveFormatId 不可用，回退 bv*+ba/b 重试',
        );
        return download(
          url: url,
          formatId: 'bv*+ba/b',
          outputPath: outputPath,
          onProgress: onProgress,
          shouldCancel: shouldCancel,
          audioOnly: audioOnly,
          downloadSubtitles: downloadSubtitles,
          downloadCover: downloadCover,
          throttleKbps: throttleKbps,
          connections: connections,
          logPath: logPath,
          referer: referer,
          userAgent: userAgent,
          cookieHeader: cookieHeader,
          passCookies: passCookies,
          forceNativeFragments: forceNativeFragments,
        );
      }
      throw YtDlpException(
        '下载失败: ${_extractErrorMessage(fullStderr)}',
        exitCode: exitCode,
        stderr: fullStderr,
      );
    }

    // 检查合并是否发生（formatId 含 + 表示需要合并音视频流）
    final needsMerge = effectiveFormatId.contains('+');
    final hasMergeLine =
        fullStdout.contains('Merging formats into') ||
        fullStderr.contains('Merging formats into');

    // 从 yt-dlp 输出中提取最终文件路径
    final outputPathFinal = _extractOutputPath(fullStdout, outputPath);
    debugPrint('[YtDlp] 最终路径: $outputPathFinal');

    // 验证文件存在且有内容
    final outFile = File(outputPathFinal);
    if (!outFile.existsSync()) {
      // 尝试从模板推导
      final derived = _deriveOutputPath(outputPath);
      if (File(derived).existsSync()) {
        debugPrint('[YtDlp] 推导路径成功: $derived');
        return derived;
      }
      // 文件不存在 + 需要合并但没合并行 = ffmpeg 合并失败
      if (needsMerge && !hasMergeLine) {
        debugPrint('[YtDlp] ❌ 需要合并但未找到合并行，ffmpeg 可能不可用');
        throw YtDlpException(
          'ffmpeg 合并失败：音视频流已下载但未合并。'
          'ffmpeg 路径: $actualFfmpegPath\n'
          'stderr: $fullStderr',
        );
      }
      debugPrint('[YtDlp] ⚠️ 输出文件不存在: $outputPathFinal');
    }
    return outputPathFinal;
  }

  /// 站点登录 cookie 参数：内置 WebView 登录保存的 Netscape 文件，
  /// 以及可选的浏览器原生 cookie（`--cookies-from-browser`）。
  ///
  /// YouTube 例外：WebView 保存的 `youtube.txt` 常是失效的游客 Cookie，
  /// 和浏览器 Cookie 一起传时会覆盖后者，反而过不了风控。配置了浏览器
  /// Cookie 时只信浏览器，跳过该文件。
  static List<String> _cookieArgs(List<String> paths, {String url = ''}) {
    final browser = SettingsStorage.instance.current.cookiesFromBrowser;
    final effectivePaths = filterCookiePathsForSite(
      paths,
      url: url,
      browser: browser,
    );
    return [
      for (final cp in effectivePaths) ...['--cookies', cp],
      if (browser.isNotEmpty) ...['--cookies-from-browser', browser],
    ];
  }

  /// YouTube 专用参数；Node 不存在时只加 extractor-args。
  static Future<List<String>> _youtubeArgs(String url) async {
    if (!_isYouTubeUrl(url)) return const [];
    final nodePath = await BinaryLocator.getNodePath();
    final hasNode = await File(nodePath).exists();
    return buildYouTubeArgs(url, nodePath: hasNode ? nodePath : null);
  }

  /// 尝试用多连接 Range 下载 YouTube 的直链格式。
  ///
  /// YouTube 有大量格式是整文件 HTTPS 直链（不是 DASH/HLS 分片），yt-dlp 只会
  /// 用一条连接顺序下载，`--concurrent-fragments` 对它无效；CDN 又会按连接
  /// 限速。这里先取到直链和请求头，再用 [ChunkedHttpDownloader] 4 连接并发下载，
  /// 视频/音频两路也同时下载。
  ///
  /// 任何条件不满足（HLS/DASH 分片、SABR、容器/编码不匹配、服务器不支持
  /// Range）都返回 null，由调用方回退到现有 yt-dlp 下载。
  static Future<String?> _tryChunkedYouTubeDownload({
    required String url,
    required String formatId,
    required String outputPath,
    required void Function(DownloadProgress) onProgress,
    required bool Function() shouldCancel,
    required String proxy,
    required int connections,
    required int chunkSizeMb,
    String? logPath,
  }) async {
    if (formatId.isEmpty || formatId == 'best' || formatId.contains('*')) {
      return null;
    }

    final cookiePaths = await SiteCookies.allCookieFilePaths();
    final probe = await _runCommand([
      '--dump-json',
      '--no-warnings',
      '--no-playlist',
      if (proxy.isNotEmpty) ...['--proxy', proxy],
      '-f', formatId,
      ...await _youtubeArgs(url),
      ..._cookieArgs(cookiePaths, url: url),
      url,
    ]);
    if (probe.exitCode != 0) return null;

    Map<String, dynamic> json;
    try {
      final text = probe.stdout.trim();
      if (text.isEmpty) return null;
      json = jsonDecode(text.split('\n').last) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }

    final streams = _resolveDirectStreams(json, formatId, outputPath);
    if (streams == null) return null;
    final video = streams.where((s) => s.isVideo).toList();
    final audio = streams.where((s) => s.isAudio).toList();

    await _appendLog(
      logPath,
      '[chunked] formats=${streams.map((s) => '${s.ext}/${s.isVideo ? 'v' : 'a'}').join('+')} '
      'conn=$connections chunk=${chunkSizeMb}MB',
    );

    final stamp = DateTime.now().microsecondsSinceEpoch;
    final videoTmp = streams.length == 2 ? '$outputPath.v.$stamp.tmp' : '';
    final audioTmp = streams.length == 2 ? '$outputPath.a.$stamp.tmp' : '';

    var videoBytes = 0;
    var audioBytes = 0;
    var videoSpeed = 0.0;
    var audioSpeed = 0.0;
    final totalBytes = streams.fold<int>(
      0,
      (sum, s) => sum + (s.fileSize ?? 0),
    );
    final knownTotal = streams.every((s) => s.fileSize != null);

    void report(double speed) {
      final done = videoBytes + audioBytes;
      onProgress(DownloadProgress(
        downloadedBytes: done,
        totalBytes: knownTotal ? totalBytes : null,
        speed: speed,
        percent: knownTotal && totalBytes > 0
            ? (done / totalBytes).clamp(0.0, 1.0)
            : null,
        stage: DownloadStage.downloading,
        detail: streams.length == 2 ? '分块下载音视频' : '分块下载',
      ));
    }

    try {
      if (streams.length == 1) {
        await ChunkedHttpDownloader.download(
          url: streams.single.url,
          outputPath: outputPath,
          headers: streams.single.headers,
          connections: connections,
          chunkSizeBytes: chunkSizeMb * 1024 * 1024,
          proxy: proxy,
          shouldCancel: shouldCancel,
          onProgress: (downloaded, total, speed) {
            videoBytes = downloaded;
            report(speed);
          },
        );
      } else {
        final videoStream = video.single;
        final audioStream = audio.single;
        await Future.wait([
          ChunkedHttpDownloader.download(
            url: videoStream.url,
            outputPath: videoTmp,
            headers: videoStream.headers,
            connections: connections,
            chunkSizeBytes: chunkSizeMb * 1024 * 1024,
            proxy: proxy,
            shouldCancel: shouldCancel,
            onProgress: (downloaded, total, speed) {
              videoBytes = downloaded;
              videoSpeed = speed;
              report(videoSpeed + audioSpeed);
            },
          ),
          ChunkedHttpDownloader.download(
            url: audioStream.url,
            outputPath: audioTmp,
            headers: audioStream.headers,
            connections: connections,
            chunkSizeBytes: chunkSizeMb * 1024 * 1024,
            proxy: proxy,
            shouldCancel: shouldCancel,
            onProgress: (downloaded, total, speed) {
              audioBytes = downloaded;
              audioSpeed = speed;
              report(videoSpeed + audioSpeed);
            },
          ),
        ]);
        onProgress(DownloadProgress(
          downloadedBytes: knownTotal ? totalBytes : videoBytes + audioBytes,
          totalBytes: knownTotal ? totalBytes : null,
          speed: 0,
          percent: 1,
          stage: DownloadStage.merging,
          detail: '合并音视频流',
        ));
        await FFmpegRunner.mergeCopy(
          videoPath: videoTmp,
          audioPath: audioTmp,
          outputPath: outputPath,
        );
      }
      await _appendLog(logPath, '[chunked] success -> $outputPath');
      return outputPath;
    } finally {
      for (final path in [videoTmp, audioTmp]) {
        if (path.isEmpty) continue;
        try {
          final f = File(path);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    }
  }

  /// 纯逻辑：判断一份 yt-dlp JSON 能否走多连接直链下载。
  @visibleForTesting
  static bool canDirectDownload(
    Map<String, dynamic> json,
    String formatId,
    String outputPath,
  ) {
    return _resolveDirectStreams(json, formatId, outputPath) != null;
  }

  static List<_DirectStream>? _resolveDirectStreams(
    Map<String, dynamic> json,
    String formatId,
    String outputPath,
  ) {
    final selected = _selectedFormats(json, formatId);
    if (selected == null || selected.isEmpty || selected.length > 2) {
      return null;
    }

    final streams = <_DirectStream>[];
    for (final f in selected) {
      final stream = _directStreamFromJson(f);
      if (stream == null) return null;
      streams.add(stream);
    }

    final video = streams.where((s) => s.isVideo).toList();
    final audio = streams.where((s) => s.isAudio).toList();
    if (streams.length == 1) {
      if (_matchingContainer(streams.single.ext, null, outputPath) == null) {
        return null;
      }
    } else if (video.length == 1 && audio.length == 1) {
      if (_matchingContainer(video.single.ext, audio.single.ext, outputPath) ==
          null) {
        return null;
      }
    } else {
      return null;
    }
    return streams;
  }

  static List<Map<String, dynamic>>? _selectedFormats(
    Map<String, dynamic> json,
    String formatId,
  ) {
    final requested = json['requested_formats'];
    final raw = (requested is List && requested.isNotEmpty)
        ? requested
        : (json['formats'] as List?) ?? const [];
    final byId = <String, Map<String, dynamic>>{};
    final byBase = <String, Map<String, dynamic>>{};
    for (final f in raw.whereType<Map>()) {
      final id = f['format_id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final copy = Map<String, dynamic>.from(f);
      byId[id] = copy;
      byBase[id.split('-').first] = copy;
    }

    final result = <Map<String, dynamic>>[];
    for (final part in formatId.split('+')) {
      final found = byId[part] ?? byBase[part.split('-').first];
      if (found == null) return null;
      result.add(found);
    }
    return result;
  }

  static _DirectStream? _directStreamFromJson(Map<String, dynamic> json) {
    final protocol = json['protocol']?.toString() ?? '';
    if (!protocol.startsWith('http')) return null;
    final fragments = json['fragments'];
    if (fragments is List && fragments.isNotEmpty) return null;
    final streamUrl = json['url']?.toString() ?? '';
    if (streamUrl.isEmpty) return null;

    final headers = <String, String>{};
    final rawHeaders = json['http_headers'];
    if (rawHeaders is Map) {
      rawHeaders.forEach((key, value) {
        if (key is String && value is String) headers[key] = value;
      });
    }
    headers.putIfAbsent(
      'User-Agent',
      () =>
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
          'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
    );
    headers.putIfAbsent('Referer', () => 'https://www.youtube.com/');

    final vcodec = json['vcodec']?.toString() ?? 'none';
    final acodec = json['acodec']?.toString() ?? 'none';
    final isVideo = vcodec != 'none' && vcodec.isNotEmpty;
    final isAudio = acodec != 'none' && acodec.isNotEmpty;
    if (!isVideo && !isAudio) return null;

    final size =
        (json['filesize'] as num?)?.toInt() ??
        (json['filesize_approx'] as num?)?.toInt();
    return _DirectStream(
      url: streamUrl,
      headers: headers,
      ext: json['ext']?.toString() ?? '',
      isVideo: isVideo,
      isAudio: isAudio,
      fileSize: size,
    );
  }

  /// 直链下载后能否直接无损封装进目标容器。
  static String? _matchingContainer(
    String videoExt,
    String? audioExt,
    String outputPath,
  ) {
    final target = outputPath.split('.').last.toLowerCase();
    final v = videoExt.toLowerCase();
    if (audioExt == null) {
      if (v == target || (v == 'm4a' && target == 'mp4')) return target;
      return null;
    }
    final a = audioExt.toLowerCase();
    final mp4Pair = (v == 'mp4' || v == 'm4v') && (a == 'm4a' || a == 'mp4');
    final webmPair = v == 'webm' && a == 'webm';
    if (mp4Pair && target == 'mp4') return 'mp4';
    if (webmPair && target == 'webm') return 'webm';
    return null;
  }

  static Future<void> _appendLog(String? path, String line) async {
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsString('$line\n', mode: FileMode.append);
    } catch (_) {}
  }

  /// 从输出模板推导实际文件路径
  ///
  /// yt-dlp 模板 `xxx.%(ext)s` 下载 mp4 后变成 `xxx.mp4`
  static String _deriveOutputPath(String template) {
    // 替换 %(ext)s 为 mp4（我们强制 merge-output-format mp4）
    return template.replaceAll('%(ext)s', 'mp4');
  }

  /// 获取可用字幕语言列表
  static Future<List<String>> listSubtitles(String url) async {
    final cookiePaths = await SiteCookies.allCookieFilePaths();
    final result = await _runCommand([
      '--list-subs',
      '--no-warnings',
      '--no-playlist',
      ...await _youtubeArgs(url),
      ..._cookieArgs(cookiePaths, url: url),
      url,
    ]);

    if (result.exitCode != 0) return [];

    // 解析输出中的语言列表（简化版）
    final lines = result.stdout.split('\n');
    final langs = <String>[];
    bool inSubsSection = false;
    for (final line in lines) {
      if (line.contains('Available subtitles')) {
        inSubsSection = true;
        continue;
      }
      if (line.contains('Available automatic captions')) {
        inSubsSection = true;
        continue;
      }
      if (inSubsSection && line.trim().isEmpty) {
        inSubsSection = false;
        continue;
      }
      if (inSubsSection) {
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.isNotEmpty && parts[0].length <= 10) {
          langs.add(parts[0]);
        }
      }
    }
    return langs.toSet().toList();
  }

  // ============== 内部方法 ==============

  /// 子进程环境变量
  ///
  /// 禁用 Python 字节码缓存（PYTHONDONTWRITEBYTECODE），
  /// 避免 brew 版 yt-dlp 运行时写 __pycache__ 到受限目录（如 sandbox）。
  static Map<String, String> get _processEnv => {
    ...Platform.environment,
    'PYTHONDONTWRITEBYTECODE': '1',
  };

  /// 执行 yt-dlp 命令并等待完成。
  ///
  /// [timeout] 到期后先 SIGTERM，2 秒后仍在则 SIGKILL；返回 exitCode=-1。
  static Future<({int exitCode, String stdout, String stderr})> _runCommand(
    List<String> args, {
    Duration? timeout,
  }) async {
    final ytDlpPath = await BinaryLocator.getYtDlpPath();
    final process = await Process.start(
      ytDlpPath,
      args,
      environment: _processEnv,
    );
    final stdoutFuture = process.stdout.transform(utf8.decoder).join();
    final stderrFuture = process.stderr.transform(utf8.decoder).join();

    var timedOut = false;
    Timer? timer;
    Timer? killTimer;
    if (timeout != null) {
      timer = Timer(timeout, () {
        timedOut = true;
        process.kill(ProcessSignal.sigterm);
        killTimer = Timer(const Duration(seconds: 2), () {
          process.kill(ProcessSignal.sigkill);
        });
      });
    }

    final exitCode = await process.exitCode;
    timer?.cancel();
    killTimer?.cancel();
    final stdout = await stdoutFuture;
    final stderr = await stderrFuture;
    return (
      exitCode: timedOut ? -1 : exitCode,
      stdout: stdout,
      stderr: timedOut
          ? '$stderr\n解析超时（${timeout!.inSeconds}s）'
          : stderr,
    );
  }

  /// 解析 yt-dlp JSON 为 VideoInfo
  static VideoInfo _parseVideoInfo(String url, Map<String, dynamic> json) {
    final formats = _parseFormats(json);
    return VideoInfo(
      url: url,
      title: json['title'] as String? ?? '未知标题',
      duration: (json['duration'] as num?)?.toInt() ?? 0,
      uploader: json['uploader'] as String? ?? '未知',
      thumbnail: json['thumbnail'] as String? ?? '',
      extractor:
          json['extractor_key'] as String? ??
          json['extractor'] as String? ??
          'Unknown',
      videoId: json['id'] as String? ?? '',
      formats: formats,
      subtitleLangs: _parseSubtitleLangs(json),
      rawJson: json,
    );
  }

  /// 从 JSON 解析格式列表
  ///
  /// 为每个视频流自动配对最佳音频流，生成组合 formatId（如 "137+140"）。
  /// 过滤掉 storyboard / m3u8 等无效格式。
  static List<FormatOption> _parseFormats(Map<String, dynamic> json) {
    final rawFormats = json['formats'] as List? ?? [];

    // 第一轮：分类收集
    final videoStreams = <Map<String, dynamic>>[];
    final audioStreams = <Map<String, dynamic>>[];
    final combinedStreams = <Map<String, dynamic>>[];

    for (final f in rawFormats) {
      if (f is! Map) continue;
      final formatId = f['format_id']?.toString();
      if (formatId == null) continue;

      final vCodec = f['vcodec']?.toString() ?? 'none';
      final aCodec = f['acodec']?.toString() ?? 'none';
      final protocol = f['protocol']?.toString() ?? '';

      // 过滤 storyboard / mhtml / m3u8
      if (vCodec == 'images' ||
          (vCodec == 'none' && aCodec == 'none') ||
          protocol == 'm3u8') {
        continue;
      }

      final hasVideo = vCodec != 'none' && vCodec.isNotEmpty;
      final hasAudio = aCodec != 'none' && aCodec.isNotEmpty;

      final mapF = Map<String, dynamic>.from(f);

      if (hasVideo && hasAudio) {
        // 组合格式（如 18 = 360p mp4 自带音视频）
        combinedStreams.add(mapF);
      } else if (hasVideo) {
        videoStreams.add(mapF);
      } else if (hasAudio) {
        audioStreams.add(mapF);
      }
    }

    // 按音频质量排序（码率越高越好）。
    // -drc 是实验性动态范围压缩音轨，不同 player client 下时有时无；
    // 配对时优先普通音轨，避免生成下载时可能消失的 formatId。
    audioStreams.sort((a, b) {
      final idA = a['format_id']?.toString() ?? '';
      final idB = b['format_id']?.toString() ?? '';
      final drcA = idA.contains('-drc');
      final drcB = idB.contains('-drc');
      if (drcA != drcB) return drcA ? 1 : -1;
      final abrA = (a['abr'] as num?)?.toInt() ?? 0;
      final abrB = (b['abr'] as num?)?.toInt() ?? 0;
      return abrB.compareTo(abrA);
    });

    final preferredTracks = SettingsStorage.instance.current.preferredAudioTrack
        .split(',')
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toList();

    // 提取最佳 m4a 和 webm 音频流（用于配对）；优先匹配用户指定音轨。
    String? bestM4aAudioId;
    String? bestWebmAudioId;
    String? preferredM4aAudioId;
    String? preferredWebmAudioId;
    for (final a in audioStreams) {
      final ext = a['ext']?.toString() ?? '';
      final matched = _audioMatches(a, preferredTracks);
      if (matched && ext == 'm4a' && preferredM4aAudioId == null) {
        preferredM4aAudioId = a['format_id']?.toString();
      }
      if (matched && ext == 'webm' && preferredWebmAudioId == null) {
        preferredWebmAudioId = a['format_id']?.toString();
      }
      if (ext == 'm4a' && bestM4aAudioId == null) {
        bestM4aAudioId = a['format_id']?.toString();
      }
      if (ext == 'webm' && bestWebmAudioId == null) {
        bestWebmAudioId = a['format_id']?.toString();
      }
    }
    bestM4aAudioId = preferredM4aAudioId ?? bestM4aAudioId;
    bestWebmAudioId = preferredWebmAudioId ?? bestWebmAudioId;
    // 兜底：取第一个音频流
    if (bestM4aAudioId == null && audioStreams.isNotEmpty) {
      bestM4aAudioId = audioStreams.first['format_id']?.toString();
    }

    final options = <FormatOption>[];
    final seenHeights = <int>{};

    // 第二轮：处理视频流（自适应，需配音频）
    for (final v in videoStreams) {
      final height = (v['height'] as num?)?.toInt() ?? 0;
      if (height <= 0) continue;

      // 同一清晰度只取最佳编码（优先 h264/mp4）
      if (seenHeights.contains(height)) continue;

      final ext = v['ext']?.toString() ?? 'mp4';
      final vCodec = v['vcodec']?.toString() ?? '';
      final formatId = v['format_id']?.toString() ?? '';

      // 配对兼容的音频流
      String? audioId;
      if (ext == 'mp4' || vCodec.contains('avc') || vCodec.contains('h264')) {
        audioId = bestM4aAudioId;
      } else if (ext == 'webm' ||
          vCodec.contains('vp9') ||
          vCodec.contains('av01')) {
        audioId = bestWebmAudioId ?? bestM4aAudioId;
      } else {
        audioId = bestM4aAudioId;
      }

      // 组合 formatId
      final combinedId = (audioId != null && audioId.isNotEmpty)
          ? '$formatId+$audioId'
          : formatId;

      final fileSize =
          (v['filesize'] as num?)?.toInt() ??
          (v['filesize_approx'] as num?)?.toInt();
      final fps = (v['fps'] as num?)?.toInt();
      final vbr = (v['vbr'] as num?)?.toInt();

      options.add(
        FormatOption(
          formatId: combinedId,
          label: '${height}p ${ext.toUpperCase()}',
          height: height,
          ext: ext,
          audioOnly: false,
          fileSize: fileSize,
          needsMerge: true,
          vbr: vbr,
          fps: fps,
        ),
      );
      seenHeights.add(height);
    }

    // 第三轮：处理组合格式（自带音视频）
    for (final c in combinedStreams) {
      final height = (c['height'] as num?)?.toInt() ?? 0;
      if (height <= 0) continue;

      final ext = c['ext']?.toString() ?? 'mp4';
      final formatId = c['format_id']?.toString() ?? '';
      final fileSize =
          (c['filesize'] as num?)?.toInt() ??
          (c['filesize_approx'] as num?)?.toInt();
      final fps = (c['fps'] as num?)?.toInt();
      final vbr = (c['vbr'] as num?)?.toInt();

      options.add(
        FormatOption(
          formatId: formatId,
          label: '${height}p ${ext.toUpperCase()}',
          height: height,
          ext: ext,
          audioOnly: false,
          fileSize: fileSize,
          needsMerge: false,
          vbr: vbr,
          fps: fps,
        ),
      );
    }

    // 第四轮：纯音频选项
    if (audioStreams.isNotEmpty) {
      // 优先使用指定音轨，否则取最佳 m4a 音频作为 MP3 选项
      final bestAudio = audioStreams.firstWhere(
        (a) => _audioMatches(a, preferredTracks),
        orElse: () => audioStreams.first,
      );
      final audioId = bestAudio['format_id']?.toString() ?? '';
      final fileSize =
          (bestAudio['filesize'] as num?)?.toInt() ??
          (bestAudio['filesize_approx'] as num?)?.toInt();
      final abr = (bestAudio['abr'] as num?)?.toInt();

      options.add(
        FormatOption(
          formatId: '$audioId/bestaudio/best',
          label: 'MP3 纯音频',
          height: 0,
          ext: 'mp3',
          audioOnly: true,
          fileSize: fileSize,
          needsMerge: false,
          abr: abr,
        ),
      );
    }

    // 按清晰度从高到低排序（0=音频排最后）
    options.sort((a, b) {
      if (a.height == 0 && b.height == 0) return 0;
      if (a.height == 0) return 1;
      if (b.height == 0) return -1;
      return b.height.compareTo(a.height);
    });

    return options;
  }

  static bool _audioMatches(
    Map<String, dynamic> audio,
    List<String> preferredTracks,
  ) {
    if (preferredTracks.isEmpty) return false;
    final haystack = [
      audio['language'],
      audio['format_note'],
      audio['format_id'],
      audio['format'],
    ].whereType<Object>().join(' ').toLowerCase();
    return preferredTracks.any(haystack.contains);
  }

  /// 解析可用字幕语言
  static List<String> _parseSubtitleLangs(Map<String, dynamic> json) {
    final subs = json['subtitles'] as Map? ?? {};
    final autoCaps = json['automatic_captions'] as Map? ?? {};
    final langs = <String>{};
    for (final key in subs.keys) {
      langs.add(key.toString());
    }
    for (final key in autoCaps.keys) {
      langs.add(key.toString());
    }
    return langs.toList()..sort();
  }

  /// 解析 yt-dlp 进度行
  /// 示例行: [download]  50.0% of 100.00MiB at 5.00MiB/s ETA 00:10
  @visibleForTesting
  static DownloadProgress? parseProgressLine(String line) {
    // 匹配下载进度行。HLS 原生下载器的行会带 "~"（估算大小）和
    // "(frag x/y)" 后缀，ETA 也可能是 Unknown；最后的汇总行则没有 at/ETA。
    final progressRegex = RegExp(
      r'\[download\]\s+([\d.]+)%\s+of\s+~?\s*([\d.]+)(B|KiB|MiB|GiB)'
      r'(?:\s+in\s+[\d:]+)?'
      r'(?:\s+at\s+([\d.]+)(B|KiB|MiB|GiB)/s)?'
      r'(?:\s+ETA\s+(\d+:\d+|Unknown))?',
    );
    final match = progressRegex.firstMatch(line);
    if (match == null) {
      // 检测合并阶段（yt-dlp 新版用 [Merger]，旧版用 [ffmpeg]）
      if ((line.contains('[Merger]') || line.contains('[ffmpeg]')) &&
          line.contains('Merging')) {
        return const DownloadProgress(
          downloadedBytes: 0,
          speed: 0,
          stage: DownloadStage.merging,
          detail: '合并音视频流',
        );
      }
      if (line.contains('[download]') && line.contains('Destination')) {
        return const DownloadProgress(
          downloadedBytes: 0,
          speed: 0,
          stage: DownloadStage.preparing,
          detail: '准备下载',
        );
      }
      return null;
    }

    final percent = double.parse(match.group(1)!) / 100;
    final sizeValue = double.parse(match.group(2)!);
    final sizeUnit = match.group(3)!;
    final speedValue = match.group(4);
    final speedUnit = match.group(5);
    final etaStr = match.group(6);

    final totalBytes = _unitToBytes(sizeValue, sizeUnit);
    final speed = (speedValue != null && speedUnit != null)
        ? _unitToBytes(double.parse(speedValue), speedUnit).toDouble()
        : 0.0;
    int? eta;
    if (etaStr != null && etaStr != 'Unknown') {
      final etaParts = etaStr.split(':');
      eta = int.parse(etaParts[0]) * 60 + int.parse(etaParts[1]);
    }

    // 分片下载器开头会先报 "100% of ~1KiB (frag 0/23)"，按分片数算进度更稳。
    final fragMatch = RegExp(r'\(frag\s+(\d+)/(\d+)\)').firstMatch(line);
    var percentValue = percent;
    if (fragMatch != null) {
      final done = int.tryParse(fragMatch.group(1)!) ?? 0;
      final total = int.tryParse(fragMatch.group(2)!) ?? 0;
      if (total > 0) percentValue = (done / total).clamp(0.0, 1.0);
    }

    final downloadedBytes = (totalBytes * percentValue).toInt();

    return DownloadProgress(
      downloadedBytes: downloadedBytes,
      totalBytes: totalBytes,
      speed: speed,
      percent: percentValue,
      eta: eta,
      stage: DownloadStage.downloading,
    );
  }

  /// 单位转字节
  static int _unitToBytes(double value, String unit) {
    switch (unit) {
      case 'KiB':
        return (value * 1024).toInt();
      case 'MiB':
        return (value * 1024 * 1024).toInt();
      case 'GiB':
        return (value * 1024 * 1024 * 1024).toInt();
      default:
        return value.toInt();
    }
  }

  /// yt-dlp 的代理：优先应用内设置，其次系统代理。
  ///
  /// 系统代理本来就是给浏览器/WebView 用的；yt-dlp 是独立进程，不会
  /// 自动读取 macOS/Windows 系统代理。留空时这里补上，避免明明浏览器
  /// 能访问 YouTube、yt-dlp 却走另一个出口被地区限制。
  static Future<String> _resolveProxy() async {
    final configured = SettingsStorage.instance.current.proxy.trim();
    if (configured.isNotEmpty) return SystemProxy.normalize(configured);
    return await SystemProxy.detect() ?? '';
  }

  /// 从错误输出提取可读错误信息
  static String _extractErrorMessage(String stderr) {
    final lines = stderr.split('\n');
    for (final line in lines.reversed) {
      final trimmed = line.trim();
      if (trimmed.startsWith('ERROR:')) {
        final message = trimmed.substring(6).trim();
        if (message.contains('not available in your country') ||
            message.contains('not made this video available in your country')) {
          return '该视频在当前代理地区不可用，请切换代理节点/国家后重试';
        }
        if (message.contains('Requested format is not available')) {
          return '所选画质在当前地区/客户端不可用，请切换代理节点或重新解析后选择其他画质';
        }
        return message;
      }
    }
    return stderr.length > 200 ? stderr.substring(stderr.length - 200) : stderr;
  }

  /// 从 yt-dlp 输出提取最终文件路径
  static String _extractOutputPath(String stdout, String template) {
    // 查找合并行（yt-dlp 新版 [Merger]，旧版 [ffmpeg]）
    // [Merger] Merging formats into "xxx.mp4"
    final mergeRegex = RegExp(
      r'\[(?:Merger|ffmpeg)\] Merging formats into "(.+)"',
    );
    final mergeMatch = mergeRegex.firstMatch(stdout);
    if (mergeMatch != null) {
      return mergeMatch.group(1)!;
    }
    // 查找 "[download] ... has already been downloaded" 行
    if (stdout.contains('has already been downloaded')) {
      // 尝试从 destination 行提取
      final destRegex = RegExp(r'\[download\] Destination:\s+(.+)');
      final destMatch = destRegex.firstMatch(stdout);
      if (destMatch != null) {
        return destMatch.group(1)!.trim();
      }
    }
    // 查找 "Deleting original file" 前的路径
    final delRegex = RegExp(r'Deleting original file (.+)');
    final delMatch = delRegex.firstMatch(stdout);
    if (delMatch != null) {
      return delMatch.group(1)!.trim();
    }
    // 降级：从模板推导（替换 %(ext)s 为 mp4）
    return template.replaceAll('%(ext)s', 'mp4');
  }
}

/// 一条可直接 HTTP Range 下载的媒体流。
class _DirectStream {
  final String url;
  final Map<String, String> headers;
  final String ext;
  final bool isVideo;
  final bool isAudio;
  final int? fileSize;

  const _DirectStream({
    required this.url,
    required this.headers,
    required this.ext,
    required this.isVideo,
    required this.isAudio,
    required this.fileSize,
  });
}
