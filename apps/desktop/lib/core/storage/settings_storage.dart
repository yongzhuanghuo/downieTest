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

  /// 按播放列表/番剧分文件夹
  final bool subfolderByPlaylist;

  /// 每次添加下载时询问保存目录
  final bool askForDestination;

  /// 不支持的链接始终用「用户自定义视频提取」打开
  final bool autoUgeUnsupported;

  /// 多画质选择：0=自动最佳, 1=每次询问, 2=360p, 3=480p, 4=720p, 5=1080p, 6=4K
  final int qualityPreference;

  /// 同分辨率时优先 MP4
  final bool preferMp4;

  /// 强制只用 MP4（忽略更高分辨率但非 MP4 的格式）
  final bool forceMp4;

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

  /// HTTP 分块大小（MB，0=不分块）
  final int chunkSizeMb;

  /// yt-dlp 全局限速（kB/s，0=不限）
  final int throttleKbps;

  /// 下载完成后保存元数据 JSON
  final bool saveMetadataJson;

  /// 下载完成/失败播放系统提示音
  final bool playSounds;

  /// 添加链接后自动开始下载（关闭后任务停在等待中）
  final bool autoStartDownloads;

  /// 下载行显示缩略图
  final bool showThumbnails;

  /// 启动时清理文件已不存在的历史记录
  final bool clearMissingHistory;

  /// 转换完成后删除原始下载文件
  final bool deleteOriginalAfterConversion;

  /// 自定义后处理脚本路径（PostprocessingMode.custom）
  final String postprocessingScript;

  /// 下载自动生成的字幕
  final bool includeAutoSubtitles;

  /// 字幕模式：0=全部匹配，1=只取第一个匹配
  final int subtitleMode;

  /// 保留字幕原始格式（关闭时统一转成 SRT，与 Downie 默认一致）
  final bool keepSubtitleFormat;

  /// 首选音轨（语言/名称，逗号分隔；空=自动选最佳）
  final String preferredAudioTrack;

  /// HLS/DASH 强制重新编码
  final bool forceReencode;

  /// 使用 yt-dlp 原生 HLS 下载器
  final bool nativeHlsEngine;

  /// 在菜单栏 / 系统托盘显示图标
  final bool showInMenuBar;

  /// 启动时自动检查应用更新
  final bool autoCheckUpdates;

  /// 禁用站点登录对话框（解析失败时直接报错）
  final bool disableLoginDialogs;

  /// 自动化模式：抑制登录/画质/重复确认等阻塞对话框
  final bool automatedMode;

  /// 纯音频下载格式（yt-dlp 任务）：mp3/m4a/opus
  final String preferredAudioFormat;

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
    this.subfolderByPlaylist = false,
    this.askForDestination = false,
    this.autoUgeUnsupported = false,
    this.qualityPreference = 0,
    this.preferMp4 = true,
    this.forceMp4 = false,
    this.duplicatePrompt = true,
    this.queueSort = 0,
    this.queueSortDesc = false,
    this.quitWhenDone = false,
    this.connectionsPerDownload = 4,
    this.chunkSizeMb = 0,
    this.throttleKbps = 0,
    this.saveMetadataJson = false,
    this.playSounds = false,
    this.autoStartDownloads = true,
    this.showThumbnails = true,
    this.clearMissingHistory = false,
    this.deleteOriginalAfterConversion = false,
    this.postprocessingScript = '',
    this.includeAutoSubtitles = true,
    this.subtitleMode = 0,
    this.keepSubtitleFormat = false,
    this.preferredAudioTrack = '',
    this.forceReencode = false,
    this.nativeHlsEngine = false,
    this.showInMenuBar = true,
    this.autoCheckUpdates = true,
    this.disableLoginDialogs = false,
    this.automatedMode = false,
    this.preferredAudioFormat = 'mp3',
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
    subfolderByPlaylist: false,
    askForDestination: false,
    autoUgeUnsupported: false,
    qualityPreference: 0,
    preferMp4: true,
    forceMp4: false,
    duplicatePrompt: true,
    queueSort: 0,
    queueSortDesc: false,
    quitWhenDone: false,
    connectionsPerDownload: 4,
    chunkSizeMb: 0,
    throttleKbps: 0,
    saveMetadataJson: false,
    playSounds: false,
    autoStartDownloads: true,
    showThumbnails: true,
    clearMissingHistory: false,
    deleteOriginalAfterConversion: false,
    postprocessingScript: '',
    includeAutoSubtitles: true,
    subtitleMode: 0,
    keepSubtitleFormat: false,
    preferredAudioTrack: '',
    forceReencode: false,
    nativeHlsEngine: false,
    showInMenuBar: true,
    autoCheckUpdates: true,
    disableLoginDialogs: false,
    automatedMode: false,
    preferredAudioFormat: 'mp3',
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
    bool? subfolderByPlaylist,
    bool? askForDestination,
    bool? autoUgeUnsupported,
    int? qualityPreference,
    bool? preferMp4,
    bool? forceMp4,
    bool? duplicatePrompt,
    int? queueSort,
    bool? queueSortDesc,
    bool? quitWhenDone,
    int? connectionsPerDownload,
    int? chunkSizeMb,
    int? throttleKbps,
    bool? saveMetadataJson,
    bool? playSounds,
    bool? autoStartDownloads,
    bool? showThumbnails,
    bool? clearMissingHistory,
    bool? deleteOriginalAfterConversion,
    String? postprocessingScript,
    bool? includeAutoSubtitles,
    int? subtitleMode,
    bool? keepSubtitleFormat,
    String? preferredAudioTrack,
    bool? forceReencode,
    bool? nativeHlsEngine,
    bool? showInMenuBar,
    bool? autoCheckUpdates,
    bool? disableLoginDialogs,
    bool? automatedMode,
    String? preferredAudioFormat,
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
      subfolderByPlaylist:
          subfolderByPlaylist ?? this.subfolderByPlaylist,
      askForDestination:
          askForDestination ?? this.askForDestination,
      autoUgeUnsupported:
          autoUgeUnsupported ?? this.autoUgeUnsupported,
      qualityPreference:
          qualityPreference ?? this.qualityPreference,
      preferMp4: preferMp4 ?? this.preferMp4,
      forceMp4: forceMp4 ?? this.forceMp4,
      duplicatePrompt: duplicatePrompt ?? this.duplicatePrompt,
      queueSort: queueSort ?? this.queueSort,
      queueSortDesc: queueSortDesc ?? this.queueSortDesc,
      quitWhenDone: quitWhenDone ?? this.quitWhenDone,
      connectionsPerDownload:
          connectionsPerDownload ?? this.connectionsPerDownload,
      chunkSizeMb: chunkSizeMb ?? this.chunkSizeMb,
      throttleKbps: throttleKbps ?? this.throttleKbps,
      saveMetadataJson: saveMetadataJson ?? this.saveMetadataJson,
      playSounds: playSounds ?? this.playSounds,
      autoStartDownloads:
          autoStartDownloads ?? this.autoStartDownloads,
      showThumbnails: showThumbnails ?? this.showThumbnails,
      clearMissingHistory:
          clearMissingHistory ?? this.clearMissingHistory,
      deleteOriginalAfterConversion:
          deleteOriginalAfterConversion ?? this.deleteOriginalAfterConversion,
      postprocessingScript:
          postprocessingScript ?? this.postprocessingScript,
      includeAutoSubtitles:
          includeAutoSubtitles ?? this.includeAutoSubtitles,
      subtitleMode: subtitleMode ?? this.subtitleMode,
      keepSubtitleFormat:
          keepSubtitleFormat ?? this.keepSubtitleFormat,
      preferredAudioTrack:
          preferredAudioTrack ?? this.preferredAudioTrack,
      forceReencode: forceReencode ?? this.forceReencode,
      nativeHlsEngine: nativeHlsEngine ?? this.nativeHlsEngine,
      showInMenuBar: showInMenuBar ?? this.showInMenuBar,
      autoCheckUpdates: autoCheckUpdates ?? this.autoCheckUpdates,
      disableLoginDialogs:
          disableLoginDialogs ?? this.disableLoginDialogs,
      automatedMode: automatedMode ?? this.automatedMode,
      preferredAudioFormat:
          preferredAudioFormat ?? this.preferredAudioFormat,
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
        subfolderByPlaylist:
            (raw['subfolderByPlaylist'] as bool?) ?? false,
        askForDestination:
            (raw['askForDestination'] as bool?) ?? false,
        autoUgeUnsupported:
            (raw['autoUgeUnsupported'] as bool?) ?? false,
        qualityPreference:
            (raw['qualityPreference'] as num?)?.toInt() ?? 0,
        preferMp4: (raw['preferMp4'] as bool?) ?? true,
        forceMp4: (raw['forceMp4'] as bool?) ?? false,
        duplicatePrompt: (raw['duplicatePrompt'] as bool?) ?? true,
        queueSort: (raw['queueSort'] as num?)?.toInt() ?? 0,
        queueSortDesc: (raw['queueSortDesc'] as bool?) ?? false,
        quitWhenDone: (raw['quitWhenDone'] as bool?) ?? false,
        connectionsPerDownload:
            (raw['connectionsPerDownload'] as num?)?.toInt() ?? 4,
        chunkSizeMb: (raw['chunkSizeMb'] as num?)?.toInt() ?? 0,
        throttleKbps: (raw['throttleKbps'] as num?)?.toInt() ?? 0,
        saveMetadataJson: (raw['saveMetadataJson'] as bool?) ?? false,
        playSounds: (raw['playSounds'] as bool?) ?? false,
        autoStartDownloads:
            (raw['autoStartDownloads'] as bool?) ?? true,
        showThumbnails: (raw['showThumbnails'] as bool?) ?? true,
        clearMissingHistory:
            (raw['clearMissingHistory'] as bool?) ?? false,
        deleteOriginalAfterConversion:
            (raw['deleteOriginalAfterConversion'] as bool?) ?? false,
        postprocessingScript:
            (raw['postprocessingScript'] as String?) ?? '',
        includeAutoSubtitles:
            (raw['includeAutoSubtitles'] as bool?) ?? true,
        subtitleMode: (raw['subtitleMode'] as num?)?.toInt() ?? 0,
        keepSubtitleFormat:
            (raw['keepSubtitleFormat'] as bool?) ?? false,
        preferredAudioTrack:
            (raw['preferredAudioTrack'] as String?) ?? '',
        forceReencode: (raw['forceReencode'] as bool?) ?? false,
        nativeHlsEngine: (raw['nativeHlsEngine'] as bool?) ?? false,
        showInMenuBar: (raw['showInMenuBar'] as bool?) ?? true,
        autoCheckUpdates: (raw['autoCheckUpdates'] as bool?) ?? true,
        disableLoginDialogs:
            (raw['disableLoginDialogs'] as bool?) ?? false,
        automatedMode: (raw['automatedMode'] as bool?) ?? false,
        preferredAudioFormat:
            (raw['preferredAudioFormat'] as String?) ?? 'mp3',
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
      'subfolderByPlaylist': settings.subfolderByPlaylist,
      'askForDestination': settings.askForDestination,
      'autoUgeUnsupported': settings.autoUgeUnsupported,
      'qualityPreference': settings.qualityPreference,
      'preferMp4': settings.preferMp4,
      'forceMp4': settings.forceMp4,
      'duplicatePrompt': settings.duplicatePrompt,
      'queueSort': settings.queueSort,
      'queueSortDesc': settings.queueSortDesc,
      'quitWhenDone': settings.quitWhenDone,
      'connectionsPerDownload': settings.connectionsPerDownload,
      'chunkSizeMb': settings.chunkSizeMb,
      'throttleKbps': settings.throttleKbps,
      'saveMetadataJson': settings.saveMetadataJson,
      'playSounds': settings.playSounds,
      'autoStartDownloads': settings.autoStartDownloads,
      'showThumbnails': settings.showThumbnails,
      'clearMissingHistory': settings.clearMissingHistory,
      'deleteOriginalAfterConversion':
          settings.deleteOriginalAfterConversion,
      'postprocessingScript': settings.postprocessingScript,
      'includeAutoSubtitles': settings.includeAutoSubtitles,
      'subtitleMode': settings.subtitleMode,
      'keepSubtitleFormat': settings.keepSubtitleFormat,
      'preferredAudioTrack': settings.preferredAudioTrack,
      'forceReencode': settings.forceReencode,
      'nativeHlsEngine': settings.nativeHlsEngine,
      'showInMenuBar': settings.showInMenuBar,
      'autoCheckUpdates': settings.autoCheckUpdates,
      'disableLoginDialogs': settings.disableLoginDialogs,
      'automatedMode': settings.automatedMode,
      'preferredAudioFormat': settings.preferredAudioFormat,
    });
    debugPrint('[Settings] saved: $settings');
  }
}
