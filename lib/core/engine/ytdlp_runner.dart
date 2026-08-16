import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../data/models/download_progress.dart';
import '../../data/models/format_option.dart';
import '../../data/models/video_info.dart';
import '../platform/binary_locator.dart';

/// yt-dlp 解析异常
class YtDlpException implements Exception {
  final String message;
  final int? exitCode;
  final String? stderr;

  const YtDlpException(this.message, {this.exitCode, this.stderr});

  @override
  String toString() => 'YtDlpException: $message';
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
      throw YtDlpException('获取版本失败', exitCode: result.exitCode, stderr: result.stderr);
    }
    return result.stdout.trim();
  }

  /// 解析视频信息（不下载）
  ///
  /// [url] 视频 URL
  /// 返回包含标题、时长、格式列表等信息的 [VideoInfo]
  static Future<VideoInfo> parse(String url) async {
    // 使用 --dump-json 输出单行 JSON
    final result = await _runCommand([
      '--dump-json',
      '--no-warnings',
      '--no-playlist',
      url,
    ]);

    if (result.exitCode != 0) {
      throw YtDlpException(
        '解析失败: ${_extractErrorMessage(result.stderr)}',
        exitCode: result.exitCode,
        stderr: result.stderr,
      );
    }

    final jsonStr = result.stdout.trim();
    if (jsonStr.isEmpty) {
      throw const YtDlpException('解析返回空结果');
    }

    final Map<String, dynamic> json;
    try {
      json = jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (e) {
      throw YtDlpException('JSON 解析失败: $e');
    }

    return _parseVideoInfo(url, json);
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
  }) async {
    final ytDlpPath = await BinaryLocator.getYtDlpPath();
    final ffmpegPath = await BinaryLocator.getFFmpegPath();

    debugPrint('[YtDlp] ytDlpPath: $ytDlpPath');
    debugPrint('[YtDlp] ffmpegPath: $ffmpegPath');
    debugPrint('[YtDlp] formatId: $formatId');

    // 验证 ffmpeg 可执行（合并音视频流必需）
    String actualFfmpegPath = ffmpegPath;
    if (formatId.contains('+')) {
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
          final which =
              await Process.run('which', ['ffmpeg']);
          if (which.exitCode == 0) {
            actualFfmpegPath = (which.stdout as String).trim();
            debugPrint('[YtDlp] 从 PATH 找到 ffmpeg: $actualFfmpegPath');
          }
        } catch (_) {}
        // 再次验证
        try {
          final recheck = Process.runSync(actualFfmpegPath, ['-version']);
          if (recheck.exitCode != 0) {
            throw YtDlpException(
              'ffmpeg 不可用，无法合并音视频流。路径: $actualFfmpegPath',
            );
          }
        } catch (e) {
          throw YtDlpException(
            'ffmpeg 不可用，无法合并音视频流。请确认 ffmpeg 已安装。',
          );
        }
      }
    }

    final args = <String>[
      '--newline', // 每行一个进度，便于解析
      '--no-warnings',
      '--no-playlist',
      '-f', formatId,
      '-o', outputPath,
      '--ffmpeg-location', actualFfmpegPath,
      if (audioOnly) ...['-x', '--audio-format', 'mp3'],
      if (!audioOnly) ...['--merge-output-format', 'mp4'],
      url,
    ];

    final process =
        await Process.start(ytDlpPath, args, environment: _processEnv);
    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();

    // 监听 stdout（进度行）
    final stdoutSub = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      stdoutBuffer.writeln(line);
      final progress = _parseProgressLine(line);
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
    debugPrint('[YtDlp] exitCode=$exitCode');
    debugPrint('[YtDlp] stdout:\n$fullStdout');
    if (fullStderr.trim().isNotEmpty) {
      debugPrint('[YtDlp] stderr:\n$fullStderr');
    }

    if (exitCode != 0) {
      throw YtDlpException(
        '下载失败: ${_extractErrorMessage(fullStderr)}',
        exitCode: exitCode,
        stderr: fullStderr,
      );
    }

    // 检查合并是否发生（formatId 含 + 表示需要合并音视频流）
    final needsMerge = formatId.contains('+');
    final hasMergeLine = fullStdout.contains('Merging formats into') ||
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

  /// 从输出模板推导实际文件路径
  ///
  /// yt-dlp 模板 `xxx.%(ext)s` 下载 mp4 后变成 `xxx.mp4`
  static String _deriveOutputPath(String template) {
    // 替换 %(ext)s 为 mp4（我们强制 merge-output-format mp4）
    return template.replaceAll('%(ext)s', 'mp4');
  }

  /// 获取可用字幕语言列表
  static Future<List<String>> listSubtitles(String url) async {
    final result = await _runCommand([
      '--list-subs',
      '--no-warnings',
      '--no-playlist',
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
  static Map<String, String> get _processEnv =>
      {...Platform.environment, 'PYTHONDONTWRITEBYTECODE': '1'};

  /// 执行 yt-dlp 命令并等待完成
  static Future<({int exitCode, String stdout, String stderr})> _runCommand(
    List<String> args,
  ) async {
    final ytDlpPath = await BinaryLocator.getYtDlpPath();
    final result =
        await Process.run(ytDlpPath, args, environment: _processEnv);
    return (
      exitCode: result.exitCode,
      stdout: result.stdout.toString(),
      stderr: result.stderr.toString(),
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
      extractor: json['extractor_key'] as String? ??
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

    // 按音频质量排序（码率越高越好）
    audioStreams.sort((a, b) {
      final abrA = (a['abr'] as num?)?.toInt() ?? 0;
      final abrB = (b['abr'] as num?)?.toInt() ?? 0;
      return abrB.compareTo(abrA);
    });

    // 提取最佳 m4a 和 webm 音频流（用于配对）
    String? bestM4aAudioId;
    String? bestWebmAudioId;
    for (final a in audioStreams) {
      final ext = a['ext']?.toString() ?? '';
      if (ext == 'm4a' && bestM4aAudioId == null) {
        bestM4aAudioId = a['format_id']?.toString();
      }
      if (ext == 'webm' && bestWebmAudioId == null) {
        bestWebmAudioId = a['format_id']?.toString();
      }
    }
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
      } else if (ext == 'webm' || vCodec.contains('vp9') || vCodec.contains('av01')) {
        audioId = bestWebmAudioId ?? bestM4aAudioId;
      } else {
        audioId = bestM4aAudioId;
      }

      // 组合 formatId
      final combinedId = (audioId != null && audioId.isNotEmpty)
          ? '$formatId+$audioId'
          : formatId;

      final fileSize = (v['filesize'] as num?)?.toInt() ??
          (v['filesize_approx'] as num?)?.toInt();
      final fps = (v['fps'] as num?)?.toInt();
      final vbr = (v['vbr'] as num?)?.toInt();

      options.add(FormatOption(
        formatId: combinedId,
        label: '${height}p ${ext.toUpperCase()}',
        height: height,
        ext: ext,
        audioOnly: false,
        fileSize: fileSize,
        needsMerge: true,
        vbr: vbr,
        fps: fps,
      ));
      seenHeights.add(height);
    }

    // 第三轮：处理组合格式（自带音视频）
    for (final c in combinedStreams) {
      final height = (c['height'] as num?)?.toInt() ?? 0;
      if (height <= 0) continue;

      final ext = c['ext']?.toString() ?? 'mp4';
      final formatId = c['format_id']?.toString() ?? '';
      final fileSize = (c['filesize'] as num?)?.toInt() ??
          (c['filesize_approx'] as num?)?.toInt();
      final fps = (c['fps'] as num?)?.toInt();
      final vbr = (c['vbr'] as num?)?.toInt();

      options.add(FormatOption(
        formatId: formatId,
        label: '${height}p ${ext.toUpperCase()}',
        height: height,
        ext: ext,
        audioOnly: false,
        fileSize: fileSize,
        needsMerge: false,
        vbr: vbr,
        fps: fps,
      ));
    }

    // 第四轮：纯音频选项
    if (audioStreams.isNotEmpty) {
      // 取最佳 m4a 音频作为 MP3 选项
      final bestAudio = audioStreams.first;
      final audioId = bestAudio['format_id']?.toString() ?? '';
      final fileSize = (bestAudio['filesize'] as num?)?.toInt() ??
          (bestAudio['filesize_approx'] as num?)?.toInt();
      final abr = (bestAudio['abr'] as num?)?.toInt();

      options.add(FormatOption(
        formatId: '$audioId/bestaudio/best',
        label: 'MP3 纯音频',
        height: 0,
        ext: 'mp3',
        audioOnly: true,
        fileSize: fileSize,
        needsMerge: false,
        abr: abr,
      ));
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
  static DownloadProgress? _parseProgressLine(String line) {
    // 匹配下载进度行
    final progressRegex = RegExp(
      r'\[download\]\s+([\d.]+)%\s+of\s+([\d.]+)(KiB|MiB|GiB)\s+at\s+([\d.]+)(KiB|MiB|GiB)/s\s+ETA\s+(\d+:\d+)',
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
    final speedValue = double.parse(match.group(4)!);
    final speedUnit = match.group(5)!;
    final etaStr = match.group(6)!;

    final totalBytes = _unitToBytes(sizeValue, sizeUnit);
    final speed = _unitToBytes(speedValue, speedUnit).toDouble();
    final etaParts = etaStr.split(':');
    final eta = int.parse(etaParts[0]) * 60 + int.parse(etaParts[1]);

    final downloadedBytes = (totalBytes * percent).toInt();

    return DownloadProgress(
      downloadedBytes: downloadedBytes,
      totalBytes: totalBytes,
      speed: speed,
      percent: percent,
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

  /// 从错误输出提取可读错误信息
  static String _extractErrorMessage(String stderr) {
    final lines = stderr.split('\n');
    for (final line in lines.reversed) {
      final trimmed = line.trim();
      if (trimmed.startsWith('ERROR:')) {
        return trimmed.substring(6).trim();
      }
    }
    return stderr.length > 200 ? stderr.substring(stderr.length - 200) : stderr;
  }

  /// 从 yt-dlp 输出提取最终文件路径
  static String _extractOutputPath(String stdout, String template) {
    // 查找合并行（yt-dlp 新版 [Merger]，旧版 [ffmpeg]）
    // [Merger] Merging formats into "xxx.mp4"
    final mergeRegex =
        RegExp(r'\[(?:Merger|ffmpeg)\] Merging formats into "(.+)"');
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
