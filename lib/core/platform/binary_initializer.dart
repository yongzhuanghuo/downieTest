import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

import 'binary_locator.dart';

/// 二进制初始化器
///
/// 负责首次运行时把打包在 assets 里的 yt-dlp / FFmpeg 二进制
/// 复制到应用支持目录，并赋予执行权限。
class BinaryInitializer {
  BinaryInitializer._();

  /// 初始化二进制（幂等操作，已就绪则跳过）
  static Future<BinaryInitResult> initialize() async {
    try {
      final ready = await BinaryLocator.isReady();
      if (ready) {
        // 已就绪，获取版本信息
        final ytDlpVersion = await _safeGetVersion('ytdlp');
        final ffmpegVersion = await _safeGetVersion('ffmpeg');
        return BinaryInitResult(
          success: true,
          ytDlpVersion: ytDlpVersion,
          ffmpegVersion: ffmpegVersion,
        );
      }

      // 从 assets 复制二进制
      await _extractBinary(BinaryLocator.ytDlpFileName);
      await _extractBinary(BinaryLocator.ffmpegFileName);

      // 验证
      final readyAfter = await BinaryLocator.isReady();
      if (!readyAfter) {
        return const BinaryInitResult(
          success: false,
          error: '二进制提取后仍不可用',
        );
      }

      final ytDlpVersion = await _safeGetVersion('ytdlp');
      final ffmpegVersion = await _safeGetVersion('ffmpeg');
      return BinaryInitResult(
        success: true,
        ytDlpVersion: ytDlpVersion,
        ffmpegVersion: ffmpegVersion,
      );
    } catch (e) {
      return BinaryInitResult(success: false, error: e.toString());
    }
  }

  /// 从 assets 提取单个二进制
  static Future<void> _extractBinary(String fileName) async {
    final binDir = await BinaryLocator.getBinDirectory();
    final targetPath = '${binDir.path}/$fileName';
    final targetFile = File(targetPath);

    if (targetFile.existsSync()) return;

    // 注意：assets/bin/macos/ 下的文件路径
    final platformDir = _getPlatformDir();
    final assetPath = 'assets/bin/$platformDir/$fileName';

    try {
      final data = await rootBundle.load(assetPath);
      final bytes = data.buffer.asUint8List();
      await targetFile.writeAsBytes(bytes);

      // Unix 系统赋予执行权限
      if (!Platform.isWindows) {
        await _makeExecutable(targetPath);
      }
    } catch (e) {
      throw Exception('提取 $fileName 失败: $e');
    }
  }

  /// 赋予执行权限
  static Future<void> _makeExecutable(String path) async {
    final result = await Process.run('chmod', ['+x', path]);
    if (result.exitCode != 0) {
      // chmod 失败不致命，yt-dlp 仍可能可通过 shell 执行
    }
  }

  /// 安全获取版本（失败返回 null）
  static Future<String?> _safeGetVersion(String which) async {
    try {
      // 延迟导入避免循环依赖
      if (which == 'ytdlp') {
        return await _getYtDlpVersionSafe();
      } else {
        return await _getFFmpegVersionSafe();
      }
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _getYtDlpVersionSafe() async {
    final path = await BinaryLocator.getYtDlpPath();
    final result = await Process.run(path, ['--version']);
    if (result.exitCode != 0) return null;
    return (result.stdout as String).trim();
  }

  static Future<String?> _getFFmpegVersionSafe() async {
    final path = await BinaryLocator.getFFmpegPath();
    final result = await Process.run(path, ['-version']);
    if (result.exitCode != 0) return null;
    final firstLine = (result.stdout as String).split('\n').first;
    return firstLine.trim();
  }

  static String _getPlatformDir() {
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    throw UnsupportedError('不支持的平台');
  }
}
