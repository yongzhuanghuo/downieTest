import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../data/models/download_progress.dart';
import '../platform/binary_locator.dart';

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

  /// 转码为兼容性更好的 MP4（H.264 + AAC）。
  static Future<String> convertToMp4({
    required String inputPath,
    required String outputPath,
  }) async {
    final ffmpegPath = await BinaryLocator.getFFmpegPath();
    final args = <String>[
      '-y',
      '-i', inputPath,
      '-c:v', 'libx264',
      '-preset', 'veryfast',
      '-crf', '20',
      '-c:a', 'aac',
      '-b:a', '192k',
      '-movflags', '+faststart',
      outputPath,
    ];
    final result = await Process.run(ffmpegPath, args);
    if (result.exitCode != 0) {
      throw FFmpegException(
        'MP4 转换失败: ${result.stderr}',
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

  /// 用 FFmpeg 直接下载并转封装网络流。
  ///
  /// 支持 HLS（.m3u8）、DASH（.mpd）和直链 MP4/FLV。适用于用户自定义视频提取抓到的
  /// 媒体地址：不需要自己实现分片调度，ffmpeg 会处理 manifest、分片和 AES-128
  /// （非 DRM）解密。
  static Future<String> downloadUrl({
    required String url,
    required String outputPath,
    String? referer,
    String? cookie,
    String? userAgent,
    void Function(DownloadProgress progress)? onProgress,
    bool Function()? shouldCancel,
  }) async {
    final ffmpegPath = await BinaryLocator.getFFmpegPath();

    final headers = <String>[
      if (referer != null && referer.isNotEmpty) 'Referer: $referer',
      if (userAgent != null && userAgent.isNotEmpty) 'User-Agent: $userAgent',
      if (cookie != null && cookie.isNotEmpty) 'Cookie: $cookie',
    ];
    final args = <String>[
      '-y',
      '-nostdin',
      if (headers.isNotEmpty) ...['-headers', '${headers.join('\r\n')}\r\n'],
      '-protocol_whitelist', 'file,http,https,tcp,tls,crypto',
      '-i', url,
      '-c', 'copy',
      '-movflags', '+faststart',
      outputPath,
    ];

    final process = await Process.start(ffmpegPath, args);
    var stderrText = '';
    double? duration;
    var cancelled = false;

    Timer? cancelTimer;
    if (shouldCancel != null) {
      cancelTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (shouldCancel()) {
          cancelled = true;
          process.kill();
        }
      });
    }

    final sub = process.stderr.transform(utf8.decoder).listen((chunk) {
      stderrText += chunk;
      if (stderrText.length > 40000) {
        stderrText = stderrText.substring(stderrText.length - 40000);
      }

      final d = RegExp(r'Duration:\s*(\d+):(\d+):(\d+\.\d+)')
          .firstMatch(chunk);
      if (d != null) duration = _hms(d);

      for (final m
          in RegExp(r'time=(\d+):(\d+):(\d+\.\d+)').allMatches(chunk)) {
        final current = _hms(m);
        final percent = duration != null && duration! > 0
            ? (current / duration!).clamp(0.0, 1.0)
            : null;
        onProgress?.call(DownloadProgress(
          downloadedBytes: 0,
          totalBytes: null,
          speed: 0,
          percent: percent,
          stage: DownloadStage.downloading,
          detail: '下载媒体流',
        ));
      }
    });

    final exitCode = await process.exitCode;
    await sub.cancel();
    cancelTimer?.cancel();

    if (cancelled) throw const FFmpegException('已取消');
    if (exitCode != 0) {
      throw FFmpegException(
        '下载失败: ${stderrText.trim()}',
        exitCode: exitCode,
      );
    }
    return outputPath;
  }

  // ============== 内部方法 ==============

  static double _hms(RegExpMatch m) =>
      int.parse(m.group(1)!) * 3600 +
      int.parse(m.group(2)!) * 60 +
      double.parse(m.group(3)!);

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
