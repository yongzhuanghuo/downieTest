import 'dart:io';

import 'package:flutter/foundation.dart';

import '../storage/settings_storage.dart';

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

  /// node 可执行文件名（抖音 a_bogus 签名用）
  static String get nodeFileName => 'node$_exeSuffix';

  /// 应用数据目录中存放二进制的子目录
  static const String _binSubDir = 'bin';

  /// 获取二进制工作目录（存储目录下的 bin/）
  static Future<Directory> getBinDirectory() async {
    final supportDir = await SettingsStorage.getStorageDir();
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
    if (await _canExecute(localPath)) return localPath;
    final found = await _findBinary(ytDlpFileName);
    if (found != null) return found;
    return localPath;
  }

  /// 获取 FFmpeg 可执行文件路径
  ///
  /// 查找顺序：工作目录 → 系统 PATH → 常见绝对路径 → 默认路径
  static Future<String> getFFmpegPath() async {
    final localPath = await _localPath(ffmpegFileName);
    if (await _canExecute(localPath)) return localPath;
    final found = await _findBinary(ffmpegFileName);
    if (found != null) return found;
    return localPath;
  }

  /// 获取 node 可执行文件路径
  static Future<String> getNodePath() async {
    final localPath = await _localPath(nodeFileName);
    if (await _canExecute(localPath)) return localPath;
    final found = await _findBinary(nodeFileName);
    if (found != null) return found;
    return localPath;
  }

  /// 工作目录下的完整路径
  static Future<String> _localPath(String fileName) async {
    final binDir = await getBinDirectory();
    return '${binDir.path}/$fileName';
  }

  /// 探测结果缓存：同一路径一次进程生命周期只探测一次。
  /// yt-dlp --version 在部分 macOS 上单次要 20~30s（系统验证阻塞），
  /// 一次启动重复探测六七次曾是启动卡死 2~3 分钟的主因。
  static final Map<String, bool> _probeCache = {};

  /// 判断路径是否可执行（通过启动进程验证，而非 File.existsSync；
  /// macOS sandbox 下 File.existsSync 可能被拦截）。
  ///
  /// - 必须异步：探测可能很慢（见 _probeCache 注释），同步会冻住 UI 线程
  /// - ffmpeg 只认单杠 `-version`（`--version` 退出码 8，会被误判不可用）
  /// - 成功才写缓存；超时/失败不缓存，下次探测还有机会
  static Future<bool> _canExecute(String path) async {
    final flag = path.endsWith(ffmpegFileName) ? '-version' : '--version';
    final key = '$path $flag';
    final cached = _probeCache[key];
    if (cached != null) return cached;
    try {
      final result = await Process.run(path, [flag])
          .timeout(const Duration(seconds: 30));
      if (result.exitCode == 0) {
        _probeCache[key] = true;
        return true;
      }
      return false;
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
    // 1. 通过 which/where 查找（并手动补 PATH 避免 macOS GUI 应用 PATH 不全）
    try {
      final cmd = Platform.isWindows ? 'where' : 'which';
      // macOS 下 GUI 应用的 PATH 通常不包含 brew，手动拼接
      final env = Map<String, String>.from(Platform.environment);
      if (Platform.isMacOS) {
        final origPath = env['PATH'] ?? '';
        const extras = '/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin';
        env['PATH'] = origPath.isEmpty ? extras : '$origPath:$extras';
      }
      final result = await Process.run(cmd, [name], environment: env);
      if (result.exitCode == 0) {
        final out = (result.stdout as String).trim();
        if (out.isNotEmpty) {
          final path = out.split('\n').first.trim();
          if (path.isNotEmpty && await _canExecute(path)) {
            debugPrint('[BinaryLocator] 通过 which 找到 $name: $path');
            return path;
          }
        }
      }
    } catch (e) {
      debugPrint('[BinaryLocator] which $name 异常: $e');
    }

    // 2. 常见绝对路径
    final candidates = <String>[
      '/opt/homebrew/bin/$name',    // Apple Silicon brew (优先)
      '/usr/local/bin/$name',       // Intel Mac brew
      '/usr/bin/$name',             // 系统自带
      'C:\\ProgramData\\chocolatey\\bin\\$name.exe',  // Windows chocolatey
      'C:\\FFmpeg\\bin\\$name.exe', // Windows FFmpeg 官方
    ];
    for (final p in candidates) {
      if (await _canExecute(p)) {
        debugPrint('[BinaryLocator] 在常见路径找到 $name: $p');
        return p;
      }
    }

    return null;
  }

  /// 检查二进制是否已就绪
  static Future<bool> isReady() async {
    final ytPath = await getYtDlpPath();
    final ffPath = await getFFmpegPath();
    return await _canExecute(ytPath) && await _canExecute(ffPath);
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
    final ytOk = await _canExecute(ytDlpPath);
    final ffOk = await _canExecute(ffmpegPath);
    return [
      platformInfo,
      'BinDir: ${binDir.path}',
      'yt-dlp: $ytDlpPath (${ytOk ? "可执行" : "不可用"})',
      'ffmpeg: $ffmpegPath (${ffOk ? "可执行" : "不可用"})',
      'Ready: ${ytOk && ffOk}',
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
