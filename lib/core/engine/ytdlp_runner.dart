import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
  }) async {
    final ytDlpPath = await BinaryLocator.getYtDlpPath();
    final ffmpegPath = await BinaryLocator.getFFmpegPath();

    final args = <String>[
      '--newline', // 每行一个进度，便于解析
      '--no-warnings',
      '--no-playlist',
      '-f', formatId,
      '-o', outputPath,
      '--ffmpeg-location', ffmpegPath,
      '--merge-output-format', 'mp4',
      url,
    ];

    final process = await Process.start(ytDlpPath, args);
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

    if (exitCode != 0) {
      final stderr = stderrBuffer.toString();
      throw YtDlpException(
        '下载失败: ${_extractErrorMessage(stderr)}',
        exitCode: exitCode,
        stderr: stderr,
      );
    }

    // 从 yt-dlp 输出中提取最终文件路径
    // yt-dlp 最后一行通常是: [download] ... has already been downloaded
    // 或: [download] Destination: xxx
    // 或: [ffmpeg] Merging formats into "xxx"
    final outputPathFinal = _extractOutputPath(stdoutBuffer.toString(), outputPath);
    return outputPathFinal;
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

  /// 执行 yt-dlp 命令并等待完成
  static Future<({int exitCode, String stdout, String stderr})> _runCommand(
    List<String> args,
  ) async {
    final ytDlpPath = await BinaryLocator.getYtDlpPath();
    final result = await Process.run(ytDlpPath, args);
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
  static List<FormatOption> _parseFormats(Map<String, dynamic> json) {
    final rawFormats = json['formats'] as List? ?? [];
    final options = <FormatOption>[];

    for (final f in rawFormats) {
      if (f is! Map) continue;
      final formatId = f['format_id']?.toString();
      if (formatId == null) continue;

      final vCodec = f['vcodec']?.toString() ?? 'none';
      final aCodec = f['acodec']?.toString() ?? 'none';
      final hasVideo = vCodec != 'none' && vCodec.isNotEmpty;
      final hasAudio = aCodec != 'none' && aCodec.isNotEmpty;

      // 只处理同时有音视频，或纯音频的格式
      if (!hasVideo && !hasAudio) continue;

      final height = (f['height'] as num?)?.toInt() ?? 0;
      final ext = f['ext']?.toString() ?? 'mp4';
      final fileSize = (f['filesize'] as num?)?.toInt() ??
          (f['filesize_approx'] as num?)?.toInt();
      final fps = (f['fps'] as num?)?.toInt();
      final vbr = (f['vbr'] as num?)?.toInt();
      final abr = (f['abr'] as num?)?.toInt();

      // 生成显示标签
      String label;
      if (!hasVideo && hasAudio) {
        label = '纯音频 $ext'.toUpperCase();
      } else {
        label = '${height}p $ext'.toUpperCase();
      }

      options.add(FormatOption(
        formatId: formatId,
        label: label,
        height: height,
        ext: ext,
        audioOnly: !hasVideo && hasAudio,
        fileSize: fileSize,
        needsMerge: hasVideo && !hasAudio,
        vbr: vbr,
        abr: abr,
        fps: fps,
      ));
    }

    // 按清晰度从高到低排序
    options.sort((a, b) => b.height.compareTo(a.height));

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
      // 检测合并阶段
      if (line.contains('[ffmpeg]') && line.contains('Merging')) {
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
    // 查找 "[ffmpeg] Merging formats into "xxx"" 行
    final mergeRegex = RegExp(r'\[ffmpeg\] Merging formats into "(.+)"');
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
    // 降级：返回模板路径（不带 .part）
    return template.replaceAll('.part', '');
  }
}
