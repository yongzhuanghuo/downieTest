import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'binary_locator.dart';

/// 二进制初始化器
///
/// 负责首次运行时把打包在 assets 里的 yt-dlp / FFmpeg 二进制
/// 复制到应用支持目录，并赋予执行权限。
///
/// 开发态：assets 不打包二进制文件，直接走系统 PATH 查找（brew 安装等）
/// 打包态：assets 含二进制，首次复制到 APPDATA 执行
class BinaryInitializer {
  BinaryInitializer._();

  /// 初始化二进制（幂等操作，已就绪则跳过）
  static Future<BinaryInitResult> initialize() async {
    try {
      final ready = await BinaryLocator.isReady();
      if (ready) {
        final ytDlpVersion = await _safeGetVersion('ytdlp');
        final ffmpegVersion = await _safeGetVersion('ffmpeg');
        return BinaryInitResult(
          success: true,
          ytDlpVersion: ytDlpVersion,
          ffmpegVersion: ffmpegVersion,
        );
      }

      // 尝试从 assets 复制二进制（打包态）；
      // 开发态 assets 为空 → 忽略异常，走下面系统 PATH 判断
      await _extractBinaryOrSkip(BinaryLocator.ytDlpFileName);
      await _extractBinaryOrSkip(BinaryLocator.ffmpegFileName);

      // 再次验证（可能系统 PATH 已有，开发态常见）
      final readyAfter = await BinaryLocator.isReady();
      final ytDlpVersion = await _safeGetVersion('ytdlp');
      final ffmpegVersion = await _safeGetVersion('ffmpeg');

      if (!readyAfter) {
        String? hint;
        if (ytDlpVersion == null) {
          hint = '未找到 yt-dlp：macOS 可执行 `brew install yt-dlp`';
          if (ffmpegVersion == null) {
            hint = '$hint，且未找到 ffmpeg：执行 `brew install ffmpeg`';
          }
        } else if (ffmpegVersion == null) {
          hint = '未找到 ffmpeg：macOS 可执行 `brew install ffmpeg`';
        }
        return BinaryInitResult(
          success: false,
          ytDlpVersion: ytDlpVersion,
          ffmpegVersion: ffmpegVersion,
          error: hint ?? '二进制未就绪',
        );
      }

      return BinaryInitResult(
        success: true,
        ytDlpVersion: ytDlpVersion,
        ffmpegVersion: ffmpegVersion,
      );
    } catch (e) {
      return BinaryInitResult(success: false, error: e.toString());
    }
  }

  /// 从 assets 提取单个二进制；失败（如开发态 assets 为空）仅记录日志不抛异常
  static Future<void> _extractBinaryOrSkip(String fileName) async {
    try {
      await _extractBinary(fileName);
    } catch (e) {
      debugPrint('[BinaryInit] assets 中未找到 $fileName（开发态正常，将走系统 PATH）: $e');
    }
  }

  /// 从 assets 提取单个二进制（失败抛异常，由上层捕获）
  static Future<void> _extractBinary(String fileName) async {
    final binDir = await BinaryLocator.getBinDirectory();
    final targetPath = '${binDir.path}/$fileName';
    final targetFile = File(targetPath);

    if (targetFile.existsSync()) {
      // 对空文件/占位文件重新提取（之前启动可能只写了 0 字节）
      if (targetFile.statSync().size > 1024) return;
      await targetFile.delete();
    }

    final platformDir = _getPlatformDir();
    final assetPath = 'assets/bin/$platformDir/$fileName';

    final data = await rootBundle.load(assetPath);
    final bytes = data.buffer.asUint8List();
    if (bytes.isEmpty) {
      throw Exception('asset $assetPath 为空');
    }
    await targetFile.writeAsBytes(bytes);

    // Unix 系统赋予执行权限
    if (!Platform.isWindows) {
      await _makeExecutable(targetPath);
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
