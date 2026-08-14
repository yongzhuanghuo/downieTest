import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

/// 应用设置（不可变值对象）
///
/// 所有字段都有默认值，首次启动时使用默认值并写入 Hive。
/// 修改时通过 copyWith 生成新实例，再调用 [SettingsStorage.save] 持久化。
@immutable
class AppSettings {
  /// 下载目录（空=系统默认 Downloads）
  final String downloadDir;

  /// 并行下载数（1-10）
  final int maxConcurrent;

  /// 自动下载字幕
  final bool downloadSubtitles;

  /// 主题模式：0=跟随系统, 1=浅色, 2=深色
  final int themeMode;

  /// 开机自启动
  final bool autoStart;

  /// 下载完成后自动打开文件夹
  final bool autoOpenFolder;

  const AppSettings({
    required this.downloadDir,
    required this.maxConcurrent,
    required this.downloadSubtitles,
    required this.themeMode,
    required this.autoStart,
    required this.autoOpenFolder,
  });

  static const defaults = AppSettings(
    downloadDir: '', // 空=系统默认
    maxConcurrent: 3,
    downloadSubtitles: false,
    themeMode: 0, // 跟随系统
    autoStart: false,
    autoOpenFolder: false,
  );

  AppSettings copyWith({
    String? downloadDir,
    int? maxConcurrent,
    bool? downloadSubtitles,
    int? themeMode,
    bool? autoStart,
    bool? autoOpenFolder,
  }) {
    return AppSettings(
      downloadDir: downloadDir ?? this.downloadDir,
      maxConcurrent: maxConcurrent ?? this.maxConcurrent,
      downloadSubtitles: downloadSubtitles ?? this.downloadSubtitles,
      themeMode: themeMode ?? this.themeMode,
      autoStart: autoStart ?? this.autoStart,
      autoOpenFolder: autoOpenFolder ?? this.autoOpenFolder,
    );
  }

  /// 实际生效的下载目录（空则取系统默认）
  Future<String> resolveDownloadDir() async {
    if (downloadDir.isNotEmpty) return downloadDir;
    try {
      final dir = await getDownloadsDirectory();
      return dir?.path ?? '.';
    } catch (_) {
      return '.';
    }
  }

  /// 显示用的下载目录文本
  String get downloadDirLabel =>
      downloadDir.isEmpty ? '~/Downloads（系统默认）' : downloadDir;

  @override
  String toString() =>
      'AppSettings(dir=$downloadDir, concurrent=$maxConcurrent, subs=$downloadSubtitles, theme=$themeMode)';
}

/// Hive KV 设置存储
///
/// 桌面端把 Hive box 文件放在应用支持目录下，
/// 所有设置项存在单个 box 的 'settings' key 下（JSON-like Map）。
class SettingsStorage {
  SettingsStorage._();
  static final instance = SettingsStorage._();

  static const _boxName = 'downlo_settings';
  static const _key = 'settings';

  Box? _box;
  AppSettings _cache = AppSettings.defaults;
  bool _initialized = false;

  /// 初始化（main 中调用一次）
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final dir = await getStorageDir();
      Hive.init('${dir.path}/hive');
      _box = await Hive.openBox(_boxName);
    } catch (e) {
      debugPrint('[Settings] 存储初始化失败，退化到内存模式: $e');
    }

    final raw = _box?.get(_key);
    if (raw is Map) {
      _cache = AppSettings(
        downloadDir: (raw['downloadDir'] as String?) ?? '',
        maxConcurrent: (raw['maxConcurrent'] as num?)?.toInt() ?? 3,
        downloadSubtitles: (raw['downloadSubtitles'] as bool?) ?? false,
        themeMode: (raw['themeMode'] as num?)?.toInt() ?? 0,
        autoStart: (raw['autoStart'] as bool?) ?? false,
        autoOpenFolder: (raw['autoOpenFolder'] as bool?) ?? false,
      );
    }
    debugPrint('[Settings] loaded: $_cache');
  }

  AppSettings get current => _cache;

  /// 获取可写的存储目录
  /// 优先使用系统 Application Support，失败则回退到 ~/.downie_test
  static Future<Directory> getStorageDir() async {
    try {
      final dir = await getApplicationSupportDirectory();
      // 测试是否可写
      final testFile = File('${dir.path}/.write_test');
      await testFile.writeAsString('test');
      await testFile.delete();
      return dir;
    } catch (_) {
      // 回退到用户主目录
      final home = Platform.environment['HOME'] ?? '.';
      final fallback = Directory('$home/.downie_test');
      if (!await fallback.exists()) {
        await fallback.create(recursive: true);
      }
      return fallback;
    }
  }

  /// 保存（覆盖）
  Future<void> save(AppSettings settings) async {
    _cache = settings;
    await _box?.put(_key, {
      'downloadDir': settings.downloadDir,
      'maxConcurrent': settings.maxConcurrent,
      'downloadSubtitles': settings.downloadSubtitles,
      'themeMode': settings.themeMode,
      'autoStart': settings.autoStart,
      'autoOpenFolder': settings.autoOpenFolder,
    });
    debugPrint('[Settings] saved: $settings');
  }
}
