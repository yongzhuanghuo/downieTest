import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 二进制文件路径查找器
///
/// 负责在开发和打包环境下定位 yt-dlp / FFmpeg 可执行文件。
/// - 开发态：从系统 PATH（brew 安装）或绝对路径查找
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
  /// 查找顺序：工作目录 → 系统 PATH → 常见绝对路径 → 默认路径
  static Future<String> getYtDlpPath() async {
    final localPath = await _localPath(ytDlpFileName);
    if (_canExecute(localPath)) return localPath;
    final found = await _findBinary(ytDlpFileName);
    if (found != null) return found;
    return localPath;
  }

  /// 获取 FFmpeg 可执行文件路径
  ///
  /// 查找顺序：工作目录 → 系统 PATH → 常见绝对路径 → 默认路径
  static Future<String> getFFmpegPath() async {
    final localPath = await _localPath(ffmpegFileName);
    if (_canExecute(localPath)) return localPath;
    final found = await _findBinary(ffmpegFileName);
    if (found != null) return found;
    return localPath;
  }

  /// 工作目录下的完整路径
  static Future<String> _localPath(String fileName) async {
    final binDir = await getBinDirectory();
    return '${binDir.path}/$fileName';
  }

  /// 判断路径是否可执行（通过启动进程验证，而非 File.existsSync）
  ///
  /// macOS sandbox 下 File.existsSync 可能被拦截，
  /// 用 Process.run 直接尝试执行更可靠。
  static bool _canExecute(String path) {
    try {
      final result = Process.runSync(path, ['--version']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// 在系统中查找可执行文件
  ///
  /// 查找顺序：
  /// 1. `which` / `where` 命令
  /// 2. 常见 brew 安装路径（Intel / Apple Silicon / Linux）
  /// 3. 系统路径
  static Future<String?> _findBinary(String name) async {
    // 1. 通过 which/where 查找
    try {
      final cmd = Platform.isWindows ? 'where' : 'which';
      final result = await Process.run(cmd, [name]);
      if (result.exitCode == 0) {
        final out = (result.stdout as String).trim();
        if (out.isNotEmpty) {
          final path = out.split('\n').first.trim();
          if (path.isNotEmpty && _canExecute(path)) return path;
        }
      }
    } catch (_) {}

    // 2. 常见绝对路径
    final candidates = <String>[
      '/usr/local/bin/$name',       // Intel Mac brew
      '/opt/homebrew/bin/$name',    // Apple Silicon brew
      '/usr/bin/$name',             // 系统自带
      '/usr/local/bin/$name',       // Linux 自编译
      'C:\\ProgramData\\chocolatey\\bin\\$name.exe',  // Windows chocolatey
      'C:\\FFmpeg\\bin\\$name.exe', // Windows FFmpeg 官方
    ];
    for (final p in candidates) {
      if (_canExecute(p)) return p;
    }

    return null;
  }

  /// 检查二进制是否已就绪
  static Future<bool> isReady() async {
    final ytPath = await getYtDlpPath();
    final ffPath = await getFFmpegPath();
    return _canExecute(ytPath) && _canExecute(ffPath);
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
      'yt-dlp: $ytDlpPath (${_canExecute(ytDlpPath) ? "可执行" : "不可用"})',
      'ffmpeg: $ffmpegPath (${_canExecute(ffmpegPath) ? "可执行" : "不可用"})',
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
