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

  /// 主题模式：0=跟随系统, 1=浅色, 2=深色
  final int themeMode;

  /// 开机自启动
  final bool autoStart;

  /// 下载完成后自动打开文件夹
  final bool autoOpenFolder;

  /// 代理服务器地址（空=不使用）；支持 http://、https://、socks5://
  final String proxy;

  /// 新任务默认后处理：0=无, 1=MP4, 2=仅音频
  final int defaultPostprocessing;

  /// 新任务默认下载字幕
  final bool defaultDownloadSubtitles;

  /// 新任务默认下载封面
  final bool defaultDownloadCover;

  /// 历史记录保留天数（0=永久）
  final int historyDays;

  /// 用户自定义视频提取地址栏的搜索引擎（0=Google, 1=Bing, 2=百度, 3=DuckDuckGo）
  final int searchEngine;

  /// 从哪个本机浏览器读取登录 cookie（空=不读取）
  final String cookiesFromBrowser;

  /// 是否开启本机浏览器接收端口（书签/扩展把当前页面发到应用）
  final bool browserBridgeEnabled;

  /// 浏览器接收端口的鉴权 token
  final String browserBridgeToken;

  /// 下载完成后发送系统通知
  final bool notifyOnComplete;

  /// 字幕语言（逗号分隔，如 zh,en；空=全部）
  final String subtitleLangs;

  /// 文件名模板，支持 {title}/{extractor}/{id}/{date}
  final String filenameTemplate;

  /// 是否按来源站点建子文件夹
  final bool subfolderBySite;

  /// 不支持的链接始终用「用户自定义视频提取」打开
  final bool autoUgeUnsupported;

  /// 多画质选择：0=自动最佳, 1=每次询问, 2=360p, 3=480p, 4=720p, 5=1080p, 6=4K
  final int qualityPreference;

  /// 同分辨率时优先 MP4
  final bool preferMp4;

  /// 重复链接是否询问
  final bool duplicatePrompt;

  /// 队列排序：0=添加时间, 1=名称, 2=站点, 3=优先级
  final int queueSort;

  /// 队列排序降序
  final bool queueSortDesc;

  /// 全部下载结束后退出应用
  final bool quitWhenDone;

  /// yt-dlp 每个下载的分片并发数（1-16）
  final int connectionsPerDownload;

  /// yt-dlp 全局限速（kB/s，0=不限）
  final int throttleKbps;

  /// 下载完成后保存元数据 JSON
  final bool saveMetadataJson;

  /// 下载完成/失败播放系统提示音
  final bool playSounds;

  const AppSettings({
    required this.downloadDir,
    required this.maxConcurrent,
    required this.themeMode,
    required this.autoStart,
    required this.autoOpenFolder,
    this.proxy = '',
    this.defaultPostprocessing = 0,
    this.defaultDownloadSubtitles = false,
    this.defaultDownloadCover = false,
    this.historyDays = 0,
    this.searchEngine = 1,
    this.cookiesFromBrowser = '',
    this.browserBridgeEnabled = false,
    this.browserBridgeToken = '',
    this.notifyOnComplete = true,
    this.subtitleLangs = '',
    this.filenameTemplate = '{title}',
    this.subfolderBySite = false,
    this.autoUgeUnsupported = false,
    this.qualityPreference = 0,
    this.preferMp4 = true,
    this.duplicatePrompt = true,
    this.queueSort = 0,
    this.queueSortDesc = false,
    this.quitWhenDone = false,
    this.connectionsPerDownload = 4,
    this.throttleKbps = 0,
    this.saveMetadataJson = false,
    this.playSounds = false,
  });

  static const defaults = AppSettings(
    downloadDir: '', // 空=系统默认
    maxConcurrent: 3,
    themeMode: 0, // 跟随系统（Downie 默认行为）
    autoStart: false,
    autoOpenFolder: false,
    proxy: '',
    defaultPostprocessing: 0,
    defaultDownloadSubtitles: false,
    defaultDownloadCover: false,
    historyDays: 0,
    searchEngine: 1,
    cookiesFromBrowser: '',
    browserBridgeEnabled: false,
    browserBridgeToken: '',
    notifyOnComplete: true,
    subtitleLangs: '',
    filenameTemplate: '{title}',
    subfolderBySite: false,
    autoUgeUnsupported: false,
    qualityPreference: 0,
    preferMp4: true,
    duplicatePrompt: true,
    queueSort: 0,
    queueSortDesc: false,
    quitWhenDone: false,
    connectionsPerDownload: 4,
    throttleKbps: 0,
    saveMetadataJson: false,
    playSounds: false,
  );

  AppSettings copyWith({
    String? downloadDir,
    int? maxConcurrent,
    int? themeMode,
    bool? autoStart,
    bool? autoOpenFolder,
    String? proxy,
    int? defaultPostprocessing,
    bool? defaultDownloadSubtitles,
    bool? defaultDownloadCover,
    int? historyDays,
    int? searchEngine,
    String? cookiesFromBrowser,
    bool? browserBridgeEnabled,
    String? browserBridgeToken,
    bool? notifyOnComplete,
    String? subtitleLangs,
    String? filenameTemplate,
    bool? subfolderBySite,
    bool? autoUgeUnsupported,
    int? qualityPreference,
    bool? preferMp4,
    bool? duplicatePrompt,
    int? queueSort,
    bool? queueSortDesc,
    bool? quitWhenDone,
    int? connectionsPerDownload,
    int? throttleKbps,
    bool? saveMetadataJson,
    bool? playSounds,
  }) {
    return AppSettings(
      downloadDir: downloadDir ?? this.downloadDir,
      maxConcurrent: maxConcurrent ?? this.maxConcurrent,
      themeMode: themeMode ?? this.themeMode,
      autoStart: autoStart ?? this.autoStart,
      autoOpenFolder: autoOpenFolder ?? this.autoOpenFolder,
      proxy: proxy ?? this.proxy,
      defaultPostprocessing:
          defaultPostprocessing ?? this.defaultPostprocessing,
      defaultDownloadSubtitles:
          defaultDownloadSubtitles ?? this.defaultDownloadSubtitles,
      defaultDownloadCover: defaultDownloadCover ?? this.defaultDownloadCover,
      historyDays: historyDays ?? this.historyDays,
      searchEngine: searchEngine ?? this.searchEngine,
      cookiesFromBrowser:
          cookiesFromBrowser ?? this.cookiesFromBrowser,
      browserBridgeEnabled:
          browserBridgeEnabled ?? this.browserBridgeEnabled,
      browserBridgeToken: browserBridgeToken ?? this.browserBridgeToken,
      notifyOnComplete: notifyOnComplete ?? this.notifyOnComplete,
      subtitleLangs: subtitleLangs ?? this.subtitleLangs,
      filenameTemplate: filenameTemplate ?? this.filenameTemplate,
      subfolderBySite: subfolderBySite ?? this.subfolderBySite,
      autoUgeUnsupported:
          autoUgeUnsupported ?? this.autoUgeUnsupported,
      qualityPreference:
          qualityPreference ?? this.qualityPreference,
      preferMp4: preferMp4 ?? this.preferMp4,
      duplicatePrompt: duplicatePrompt ?? this.duplicatePrompt,
      queueSort: queueSort ?? this.queueSort,
      queueSortDesc: queueSortDesc ?? this.queueSortDesc,
      quitWhenDone: quitWhenDone ?? this.quitWhenDone,
      connectionsPerDownload:
          connectionsPerDownload ?? this.connectionsPerDownload,
      throttleKbps: throttleKbps ?? this.throttleKbps,
      saveMetadataJson: saveMetadataJson ?? this.saveMetadataJson,
      playSounds: playSounds ?? this.playSounds,
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
      'AppSettings(dir=$downloadDir, concurrent=$maxConcurrent, theme=$themeMode)';
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
        themeMode: (raw['themeMode'] as num?)?.toInt() ?? 0,
        autoStart: (raw['autoStart'] as bool?) ?? false,
        autoOpenFolder: (raw['autoOpenFolder'] as bool?) ?? false,
        proxy: (raw['proxy'] as String?) ?? '',
        defaultPostprocessing:
            (raw['defaultPostprocessing'] as num?)?.toInt() ?? 0,
        defaultDownloadSubtitles:
            (raw['defaultDownloadSubtitles'] as bool?) ?? false,
        defaultDownloadCover:
            (raw['defaultDownloadCover'] as bool?) ?? false,
        historyDays: (raw['historyDays'] as num?)?.toInt() ?? 0,
        searchEngine: (raw['searchEngine'] as num?)?.toInt() ?? 1,
        cookiesFromBrowser: (raw['cookiesFromBrowser'] as String?) ?? '',
        browserBridgeEnabled:
            (raw['browserBridgeEnabled'] as bool?) ?? false,
        browserBridgeToken:
            (raw['browserBridgeToken'] as String?) ?? '',
        notifyOnComplete: (raw['notifyOnComplete'] as bool?) ?? true,
        subtitleLangs: (raw['subtitleLangs'] as String?) ?? '',
        filenameTemplate:
            (raw['filenameTemplate'] as String?) ?? '{title}',
        subfolderBySite: (raw['subfolderBySite'] as bool?) ?? false,
        autoUgeUnsupported:
            (raw['autoUgeUnsupported'] as bool?) ?? false,
        qualityPreference:
            (raw['qualityPreference'] as num?)?.toInt() ?? 0,
        preferMp4: (raw['preferMp4'] as bool?) ?? true,
        duplicatePrompt: (raw['duplicatePrompt'] as bool?) ?? true,
        queueSort: (raw['queueSort'] as num?)?.toInt() ?? 0,
        queueSortDesc: (raw['queueSortDesc'] as bool?) ?? false,
        quitWhenDone: (raw['quitWhenDone'] as bool?) ?? false,
        connectionsPerDownload:
            (raw['connectionsPerDownload'] as num?)?.toInt() ?? 4,
        throttleKbps: (raw['throttleKbps'] as num?)?.toInt() ?? 0,
        saveMetadataJson: (raw['saveMetadataJson'] as bool?) ?? false,
        playSounds: (raw['playSounds'] as bool?) ?? false,
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
      // 回退到用户主目录（Windows 没有 HOME 环境变量，用 USERPROFILE）
      final home = Platform.environment['HOME'] ??
          (Platform.isWindows ? Platform.environment['USERPROFILE'] : null) ??
          '.';
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
      'themeMode': settings.themeMode,
      'autoStart': settings.autoStart,
      'autoOpenFolder': settings.autoOpenFolder,
      'proxy': settings.proxy,
      'defaultPostprocessing': settings.defaultPostprocessing,
      'defaultDownloadSubtitles': settings.defaultDownloadSubtitles,
      'defaultDownloadCover': settings.defaultDownloadCover,
      'historyDays': settings.historyDays,
      'searchEngine': settings.searchEngine,
      'cookiesFromBrowser': settings.cookiesFromBrowser,
      'browserBridgeEnabled': settings.browserBridgeEnabled,
      'browserBridgeToken': settings.browserBridgeToken,
      'notifyOnComplete': settings.notifyOnComplete,
      'subtitleLangs': settings.subtitleLangs,
      'filenameTemplate': settings.filenameTemplate,
      'subfolderBySite': settings.subfolderBySite,
      'autoUgeUnsupported': settings.autoUgeUnsupported,
      'qualityPreference': settings.qualityPreference,
      'preferMp4': settings.preferMp4,
      'duplicatePrompt': settings.duplicatePrompt,
      'queueSort': settings.queueSort,
      'queueSortDesc': settings.queueSortDesc,
      'quitWhenDone': settings.quitWhenDone,
      'connectionsPerDownload': settings.connectionsPerDownload,
      'throttleKbps': settings.throttleKbps,
      'saveMetadataJson': settings.saveMetadataJson,
      'playSounds': settings.playSounds,
    });
    debugPrint('[Settings] saved: $settings');
  }
}
