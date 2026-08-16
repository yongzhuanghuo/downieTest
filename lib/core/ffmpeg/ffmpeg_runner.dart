import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../platform/binary_locator.dart';
import '../../data/models/watermark_segment.dart';

/// FFmpeg 异常
class FFmpegException implements Exception {
  final String message;
  final int? exitCode;

  const FFmpegException(this.message, {this.exitCode});

  @override
  String toString() => 'FFmpegException: $message';
}

/// FFmpeg 引擎封装
///
/// 用于音视频流合并、转码、字幕嵌入等后处理操作。
/// 通常由 YtDlpRunner 自动调用，也可单独使用。
class FFmpegRunner {
  FFmpegRunner._();

  /// 获取 FFmpeg 版本
  static Future<String> getVersion() async {
    final ffmpegPath = await BinaryLocator.getFFmpegPath();
    final result = await Process.run(ffmpegPath, ['-version']);
    if (result.exitCode != 0) {
      throw const FFmpegException('获取版本失败');
    }
    final firstLine = result.stdout.toString().split('\n').first;
    return firstLine.trim();
  }

  /// 合并音视频流为 MP4
  ///
  /// [videoPath] 视频流文件
  /// [audioPath] 音频流文件
  /// [outputPath] 输出文件（应为 .mp4）
  /// [onProgress] 进度回调（0.0 - 1.0）
  static Future<String> mergeVideoAudio({
    required String videoPath,
    required String audioPath,
    required String outputPath,
    void Function(double)? onProgress,
  }) async {
    final ffmpegPath = await BinaryLocator.getFFmpegPath();

    // 获取视频时长用于进度计算
    final duration = await getMediaDuration(videoPath);

    final args = <String>[
      '-y', // 覆盖输出
      '-i', videoPath,
      '-i', audioPath,
      '-c:v', 'copy', // 视频直接复制，不重编码
      '-c:a', 'aac', // 音频转 aac
      '-map', '0:v:0',
      '-map', '1:a:0',
      '-movflags', '+faststart', // 适合流媒体播放
      outputPath,
    ];

    final process = await Process.start(ffmpegPath, args);
    final stderrBuffer = StringBuffer();

    final stderrSub = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      stderrBuffer.writeln(line);
      if (onProgress != null && duration > 0) {
        final progress = _parseFFmpegProgress(line, duration);
        if (progress != null) onProgress(progress);
      }
    });

    final exitCode = await process.exitCode;
    await stderrSub.cancel();

    if (exitCode != 0) {
      throw FFmpegException(
        '合并失败: ${stderrBuffer.toString()}',
        exitCode: exitCode,
      );
    }

    return outputPath;
  }

  /// 转换音频为 MP3
  ///
  /// [inputPath] 输入文件（任何音视频格式）
  /// [outputPath] 输出 .mp3 文件
  /// [bitrate] 比特率，如 "192"、"320"
  static Future<String> convertToMp3({
    required String inputPath,
    required String outputPath,
    String bitrate = '192',
  }) async {
    final ffmpegPath = await BinaryLocator.getFFmpegPath();

    final args = <String>[
      '-y',
      '-i', inputPath,
      '-vn', // 去掉视频
      '-ar', '44100', // 采样率
      '-ac', '2', // 双声道
      '-b:a', '${bitrate}k',
      outputPath,
    ];

    final result = await Process.run(ffmpegPath, args);
    if (result.exitCode != 0) {
      throw FFmpegException(
        'MP3 转换失败: ${result.stderr}',
        exitCode: result.exitCode,
      );
    }
    return outputPath;
  }

  /// 嵌入字幕到视频
  ///
  /// [videoPath] 视频文件
  /// [subtitlePath] 字幕文件（.srt 或 .vtt）
  /// [outputPath] 输出文件
  /// [lang] 字幕语言代码，如 "zh"、"en"
  static Future<String> embedSubtitle({
    required String videoPath,
    required String subtitlePath,
    required String outputPath,
    String lang = 'chi',
  }) async {
    final ffmpegPath = await BinaryLocator.getFFmpegPath();

    final args = <String>[
      '-y',
      '-i', videoPath,
      '-i', subtitlePath,
      '-c', 'copy',
      '-c:s', 'mov_text',
      '-metadata:s:s:0', 'language=$lang',
      '-map', '0',
      '-map', '1',
      outputPath,
    ];

    final result = await Process.run(ffmpegPath, args);
    if (result.exitCode != 0) {
      throw FFmpegException(
        '嵌入字幕失败: ${result.stderr}',
        exitCode: result.exitCode,
      );
    }
    return outputPath;
  }

  /// 提取视频某一秒的画面帧（用于去水印预览）
  static Future<String> extractFrame({
    required String inputPath,
    required double timestamp,
    required String outputPath,
  }) async {
    final ffmpegPath = await BinaryLocator.getFFmpegPath();
    final args = [
      '-ss', timestamp.toStringAsFixed(2),
      '-i', inputPath,
      '-frames:v', '1',
      '-y',
      outputPath,
    ];
    final result = await Process.run(ffmpegPath, args);
    if (result.exitCode != 0) {
      throw FFmpegException('抽帧失败: ${result.stderr}', exitCode: result.exitCode);
    }
    return outputPath;
  }

  /// 获取视频分辨率（宽, 高）
  static Future<(int, int)> getVideoDimensions(String inputPath) async {
    final ffmpegPath = await BinaryLocator.getFFmpegPath();
    final result = await Process.run(ffmpegPath, ['-i', inputPath]);
    final stderr = result.stderr.toString();
    for (final line in stderr.split('\n')) {
      if (line.contains('Video:')) {
        final match = RegExp(r'(\d{2,5})x(\d{2,5})').firstMatch(line);
        if (match != null) {
          return (int.parse(match.group(1)!), int.parse(match.group(2)!));
        }
      }
    }
    return (1920, 1080); // 兜底
  }

  /// 多段去水印：按时间轴对多段位置做 delogo 抹除
  static Future<String> removeWatermark({
    required String inputPath,
    required String outputPath,
    required List<WatermarkSegment> segments,
    required double duration,
    required int videoWidth,
    required int videoHeight,
  }) async {
    if (segments.isEmpty) throw const FFmpegException('没有水印段');
    final sorted = [...segments]..sort((a, b) => a.time.compareTo(b.time));
    final filters = <String>[];
    for (int i = 0; i < sorted.length; i++) {
      final seg = sorted[i];
      final start = seg.time;
      final end = (i + 1 < sorted.length) ? sorted[i + 1].time : duration;
      final px = (seg.x * videoWidth).round().clamp(0, videoWidth - 1);
      final py = (seg.y * videoHeight).round().clamp(0, videoHeight - 1);
      final pw = (seg.w * videoWidth).round().clamp(1, videoWidth - px);
      final ph = (seg.h * videoHeight).round().clamp(1, videoHeight - py);
      filters.add(
        "delogo=x=$px:y=$py:w=$pw:h=$ph:enable='between(t,$start,$end)'",
      );
    }
    final ffmpegPath = await BinaryLocator.getFFmpegPath();
    final args = [
      '-i', inputPath,
      '-vf', filters.join(','),
      '-c:a', 'copy',
      '-y', outputPath,
    ];
    final result = await Process.run(ffmpegPath, args);
    if (result.exitCode != 0) {
      throw FFmpegException('去水印失败: ${result.stderr}', exitCode: result.exitCode);
    }
    return outputPath;
  }

  // ============== 内部方法 ==============

  /// 获取媒体时长（秒）
  static Future<double> getMediaDuration(String filePath) async {
    final ffmpegPath = await BinaryLocator.getFFmpegPath();
    final result = await Process.run(
      ffmpegPath,
      ['-i', filePath, '-hide_banner'],
    );
    // FFmpeg 在 stderr 输出媒体信息
    final stderr = result.stderr.toString();
    final durationRegex = RegExp(r'Duration:\s+(\d+):(\d+):(\d+\.\d+)');
    final match = durationRegex.firstMatch(stderr);
    if (match == null) return 0;
    final h = int.parse(match.group(1)!);
    final m = int.parse(match.group(2)!);
    final s = double.parse(match.group(3)!);
    return h * 3600 + m * 60 + s;
  }

  /// 解析 FFmpeg 进度行
  /// 示例: frame=  120 fps=60 q=-1.0 size=    1024kB time=00:00:05.00
  static double? _parseFFmpegProgress(String line, double totalDuration) {
    final timeRegex = RegExp(r'time=(\d+):(\d+):(\d+\.\d+)');
    final match = timeRegex.firstMatch(line);
    if (match == null) return null;

    final h = int.parse(match.group(1)!);
    final m = int.parse(match.group(2)!);
    final s = double.parse(match.group(3)!);
    final currentTime = h * 3600 + m * 60 + s;

    if (totalDuration <= 0) return null;
    return (currentTime / totalDuration).clamp(0.0, 1.0);
  }
}
