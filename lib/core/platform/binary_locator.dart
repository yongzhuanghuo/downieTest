import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 二进制文件路径查找器
///
/// 负责在开发和打包环境下定位 yt-dlp / FFmpeg 可执行文件。
/// - 开发态：从 `assets/bin/<platform>/` 读取（通过 Flutter assets 机制）
/// - 打包态：从应用支持目录读取（首次启动时从 assets 复制过去）
class BinaryLocator {
  BinaryLocator._();

  /// 平台子目录名
  static String get _platformDir {
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    throw UnsupportedError('不支持的平台: ${Platform.operatingSystem}');
  }

  /// 可执行文件扩展名（Windows 需要 .exe）
  static String get _exeSuffix => Platform.isWindows ? '.exe' : '';

  /// yt-dlp 可执行文件名
  static String get ytDlpFileName => 'yt-dlp$_exeSuffix';

  /// FFmpeg 可执行文件名
  static String get ffmpegFileName => 'ffmpeg$_exeSuffix';

  /// 应用数据目录中存放二进制的子目录
  static const String _binSubDir = 'bin';

  /// 获取二进制工作目录（应用支持目录下的 bin/）
  /// 首次运行时会把 assets 里的二进制复制到这里，并赋予执行权限。
  static Future<Directory> getBinDirectory() async {
    final supportDir = await getApplicationSupportDirectory();
    final binDir = Directory('${supportDir.path}/$_binSubDir');
    if (!await binDir.exists()) {
      await binDir.create(recursive: true);
    }
    return binDir;
  }

  /// 获取 yt-dlp 可执行文件路径
  ///
  /// 查找顺序：工作目录 → 系统 PATH（开发态 brew/系统安装）→ 默认路径
  static Future<String> getYtDlpPath() async {
    final localPath = await _localPath(ytDlpFileName);
    if (File(localPath).existsSync()) return localPath;
    final inPath = await _findInPath(ytDlpFileName);
    if (inPath != null) return inPath;
    return localPath;
  }

  /// 获取 FFmpeg 可执行文件路径
  ///
  /// 查找顺序：工作目录 → 系统 PATH（开发态 brew/系统安装）→ 默认路径
  static Future<String> getFFmpegPath() async {
    final localPath = await _localPath(ffmpegFileName);
    if (File(localPath).existsSync()) return localPath;
    final inPath = await _findInPath(ffmpegFileName);
    if (inPath != null) return inPath;
    return localPath;
  }

  /// 工作目录下的完整路径
  static Future<String> _localPath(String fileName) async {
    final binDir = await getBinDirectory();
    return '${binDir.path}/$fileName';
  }

  /// 在系统 PATH 中查找可执行文件（开发态 fallback）
  ///
  /// 开发期 assets 里通常没有预编译独立二进制，
  /// 此时直接复用 brew / 系统安装的 yt-dlp / ffmpeg。
  static Future<String?> _findInPath(String name) async {
    try {
      final cmd = Platform.isWindows ? 'where' : 'which';
      final result = await Process.run(cmd, [name]);
      if (result.exitCode != 0) return null;
      final out = (result.stdout as String).trim();
      if (out.isEmpty) return null;
      final path = out.split('\n').first.trim();
      if (path.isNotEmpty && File(path).existsSync()) return path;
    } catch (_) {}
    return null;
  }

  /// 检查二进制是否已就绪
  ///
  /// 工作目录有，或系统 PATH 有，即视为就绪。
  static Future<bool> isReady() async {
    final ytDlpLocal = await _localPath(ytDlpFileName);
    final ffmpegLocal = await _localPath(ffmpegFileName);
    if (File(ytDlpLocal).existsSync() && File(ffmpegLocal).existsSync()) {
      return true;
    }
    final ytInPath = await _findInPath(ytDlpFileName);
    final ffInPath = await _findInPath(ffmpegFileName);
    return ytInPath != null && ffInPath != null;
  }

  /// 平台信息（用于日志/调试）
  static String get platformInfo {
    return 'Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion} '
        '($_platformDir)';
  }

  /// 调试输出当前路径配置
  static Future<String> getDebugInfo() async {
    final binDir = await getBinDirectory();
    final ytDlpPath = await getYtDlpPath();
    final ffmpegPath = await getFFmpegPath();
    final ready = await isReady();
    return [
      platformInfo,
      'BinDir: ${binDir.path}',
      'yt-dlp: $ytDlpPath (${File(ytDlpPath).existsSync() ? "存在" : "缺失"})',
      'ffmpeg: $ffmpegPath (${File(ffmpegPath).existsSync() ? "存在" : "缺失"})',
      'Ready: $ready',
    ].join('\n');
  }
}

/// 二进制初始化结果
@immutable
class BinaryInitResult {
  final bool success;
  final String? ytDlpVersion;
  final String? ffmpegVersion;
  final String? error;

  const BinaryInitResult({
    required this.success,
    this.ytDlpVersion,
    this.ffmpegVersion,
    this.error,
  });

  @override
  String toString() {
    if (!success) return 'BinaryInitResult(failed: $error)';
    return 'BinaryInitResult(yt-dlp: $ytDlpVersion, ffmpeg: $ffmpegVersion)';
  }
}
