import 'package:flutter/foundation.dart';

import 'download_progress.dart';
import 'format_option.dart';

/// 下载完成后的处理方式
enum PostprocessingMode { none, mp4, audio, custom }

extension PostprocessingModeX on PostprocessingMode {
  String get label {
    switch (this) {
      case PostprocessingMode.none:
        return '无后处理';
      case PostprocessingMode.mp4:
        return 'MP4';
      case PostprocessingMode.audio:
        return '仅音频';
      case PostprocessingMode.custom:
        return '自定义脚本';
    }
  }
}

/// 队列优先级（高的先下载）
enum DownloadPriority { low, normal, high }

extension DownloadPriorityX on DownloadPriority {
  String get label {
    switch (this) {
      case DownloadPriority.low:
        return '低优先级';
      case DownloadPriority.normal:
        return '普通优先级';
      case DownloadPriority.high:
        return '高优先级';
    }
  }
}

/// 下载任务状态
enum DownloadStatus {
  pending,    // 等待中（队列里）
  downloading,
  merging,
  completed,
  failed,
  cancelled,
  paused,
  loading,    // 已加入队列，正在获取页面信息（Downie: 加载中）
  preparing,  // 正在解析/准备格式（Downie: 准备中...）
}

/// 下载任务
@immutable
class DownloadTask {
  /// 任务唯一 ID
  final String id;

  /// 视频 URL
  final String url;

  /// 视频标题
  final String title;

  /// 视频时长（秒，0=未知）
  final int duration;

  /// 缩略图 URL
  final String thumbnail;

  /// 来源网站 (extractor_key，如 "BiliBili" "Youtube")
  final String extractor;

  /// yt-dlp 格式 ID
  final String formatId;

  /// 格式显示标签（如 "1080P MP4"）
  final String formatLabel;

  /// 解析时拿到的可切换格式（任务重启/DB 恢复后可能为空）
  final List<FormatOption> availableFormats;

  /// 下载完成后的处理方式
  final PostprocessingMode postprocessing;

  /// 队列优先级
  final DownloadPriority priority;

  /// 高度（纯音频=0）
  final int height;

  /// 扩展名（mp4/mp3/webm...）
  final String ext;

  /// 是否纯音频
  final bool audioOnly;

  /// 是否在下载时同时导出字幕
  final bool downloadSubtitles;

  /// 是否在下载时同时下载封面
  final bool downloadCover;

  /// 本任务限速（kB/s，0=使用全局设置）
  final int throttleKbps;

  /// 本任务连接数（0=使用全局设置）
  final int connections;

  /// 本任务单独指定的保存目录（空=使用全局下载目录）
  final String destinationDir;

  /// 所属播放列表/番剧名称（空=单视频）
  final String playlistTitle;

  /// 当前状态
  final DownloadStatus status;

  /// 下载进度
  final DownloadProgress? progress;

  /// 文件总大小（字节）
  final int fileSize;

  /// 已下载字节
  final int downloadedBytes;

  /// 当前速度（字节/秒）
  final int speed;

  /// 输出文件路径（完成后）
  final String? outputPath;

  /// 错误信息
  final String? error;

  /// 重试次数
  final int retryCount;

  /// 创建时间
  final DateTime createdAt;

  /// 开始时间
  final DateTime? startedAt;

  /// 完成时间
  final DateTime? completedAt;

  const DownloadTask({
    required this.id,
    required this.url,
    required this.title,
    this.duration = 0,
    required this.thumbnail,
    required this.extractor,
    required this.formatId,
    required this.formatLabel,
    this.availableFormats = const [],
    this.postprocessing = PostprocessingMode.none,
    this.priority = DownloadPriority.normal,
    required this.height,
    required this.ext,
    required this.audioOnly,
    this.downloadSubtitles = false,
    this.downloadCover = false,
    this.throttleKbps = 0,
    this.connections = 0,
    this.destinationDir = '',
    this.playlistTitle = '',
    this.status = DownloadStatus.pending,
    this.progress,
    this.fileSize = 0,
    this.downloadedBytes = 0,
    this.speed = 0,
    this.outputPath,
    this.error,
    this.retryCount = 0,
    required this.createdAt,
    this.startedAt,
    this.completedAt,
  });

  /// 可空字段用哨兵区分「不修改」和「清空」。
  static const Object _unset = Object();

  DownloadTask copyWith({
    DownloadStatus? status,
    Object? progress = _unset,
    String? title,
    int? duration,
    String? thumbnail,
    String? extractor,
    String? formatId,
    String? formatLabel,
    int? height,
    String? ext,
    bool? audioOnly,
    List<FormatOption>? availableFormats,
    PostprocessingMode? postprocessing,
    DownloadPriority? priority,
    bool? downloadSubtitles,
    bool? downloadCover,
    int? throttleKbps,
    int? connections,
    String? destinationDir,
    String? playlistTitle,
    int? fileSize,
    int? downloadedBytes,
    int? speed,
    Object? outputPath = _unset,
    Object? error = _unset,
    int? retryCount,
    Object? startedAt = _unset,
    Object? completedAt = _unset,
  }) {
    return DownloadTask(
      id: id,
      url: url,
      title: title ?? this.title,
      duration: duration ?? this.duration,
      thumbnail: thumbnail ?? this.thumbnail,
      extractor: extractor ?? this.extractor,
      formatId: formatId ?? this.formatId,
      formatLabel: formatLabel ?? this.formatLabel,
      availableFormats: availableFormats ?? this.availableFormats,
      postprocessing: postprocessing ?? this.postprocessing,
      priority: priority ?? this.priority,
      height: height ?? this.height,
      ext: ext ?? this.ext,
      audioOnly: audioOnly ?? this.audioOnly,
      downloadSubtitles: downloadSubtitles ?? this.downloadSubtitles,
      downloadCover: downloadCover ?? this.downloadCover,
      throttleKbps: throttleKbps ?? this.throttleKbps,
      connections: connections ?? this.connections,
      destinationDir: destinationDir ?? this.destinationDir,
      playlistTitle: playlistTitle ?? this.playlistTitle,
      status: status ?? this.status,
      progress: identical(progress, _unset)
          ? this.progress
          : progress as DownloadProgress?,
      fileSize: fileSize ?? this.fileSize,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      speed: speed ?? this.speed,
      outputPath: identical(outputPath, _unset)
          ? this.outputPath
          : outputPath as String?,
      error: identical(error, _unset) ? this.error : error as String?,
      retryCount: retryCount ?? this.retryCount,
      createdAt: createdAt,
      startedAt: identical(startedAt, _unset)
          ? this.startedAt
          : startedAt as DateTime?,
      completedAt: identical(completedAt, _unset)
          ? this.completedAt
          : completedAt as DateTime?,
    );
  }

  // ==================== 是否状态 ====================

  bool get isPending => status == DownloadStatus.pending;
  bool get isLoading => status == DownloadStatus.loading;
  bool get isPreparing => status == DownloadStatus.preparing;
  bool get isDownloading => status == DownloadStatus.downloading;
  bool get isRunning =>
      status == DownloadStatus.pending ||
      status == DownloadStatus.downloading ||
      status == DownloadStatus.merging;
  bool get isFinished =>
      status == DownloadStatus.completed ||
      status == DownloadStatus.failed ||
      status == DownloadStatus.cancelled;
  bool get isFailed => status == DownloadStatus.failed;
  bool get isCompleted => status == DownloadStatus.completed;
  bool get isPaused => status == DownloadStatus.paused;

  // ==================== 进度百分比（0-100） ====================

  int get percentValue {
    final p = progress?.percent;
    if (p == null) {
      if (status == DownloadStatus.completed) return 100;
      if (status == DownloadStatus.merging) return 99;
      return 0;
    }
    return (p * 100).round().clamp(0, 100);
  }

  // ==================== 状态中文描述 ====================

  String get statusText {
    switch (status) {
      case DownloadStatus.loading:
        return '加载中';
      case DownloadStatus.preparing:
        return '准备中';
      case DownloadStatus.pending:
        return '等待中';
      case DownloadStatus.downloading:
        return progress?.stage.label ?? '下载中';
      case DownloadStatus.merging:
        return '合并中';
      case DownloadStatus.completed:
        return '已完成';
      case DownloadStatus.failed:
        return '失败';
      case DownloadStatus.cancelled:
        return '已取消';
      case DownloadStatus.paused:
        return '已暂停';
    }
  }

  // ==================== SQLite 序列化 ====================

  factory DownloadTask.fromMap(Map<String, dynamic> map) {
    return DownloadTask(
      id: map['id'] as String,
      url: map['url'] as String,
      title: (map['title'] as String?) ?? '',
      duration: (map['duration'] as num?)?.toInt() ?? 0,
      thumbnail: (map['thumb_url'] as String?) ?? '',
      extractor: (map['source'] as String?) ?? 'Unknown',
      formatId: map['format_id'] as String,
      formatLabel: (map['format_label'] as String?) ?? '',
      postprocessing: PostprocessingMode.values.firstWhere(
        (mode) => mode.name == map['postprocessing'],
        orElse: () => PostprocessingMode.none,
      ),
      priority: DownloadPriority.values.firstWhere(
        (value) => value.index == ((map['priority'] as num?)?.toInt() ?? 1),
        orElse: () => DownloadPriority.normal,
      ),
      height: (map['height'] as num?)?.toInt() ?? 0,
      ext: (map['ext'] as String?) ?? 'mp4',
      downloadSubtitles: ((map['download_subtitles'] as num?)?.toInt() ?? 0) == 1,
      downloadCover: ((map['download_cover'] as num?)?.toInt() ?? 0) == 1,
      throttleKbps: (map['throttle_kbps'] as num?)?.toInt() ?? 0,
      connections: (map['connections'] as num?)?.toInt() ?? 0,
      destinationDir: (map['destination_dir'] as String?) ?? '',
      playlistTitle: (map['playlist_title'] as String?) ?? '',
      audioOnly: (map['height'] as num?)?.toInt() == 0 &&
          (map['format_label'] as String?)?.toLowerCase().contains('音频') == true,
      status: DownloadStatus.values[(map['status'] as int?) ?? 0],
      fileSize: (map['file_size'] as num?)?.toInt() ?? 0,
      downloadedBytes: (map['downloaded_bytes'] as num?)?.toInt() ?? 0,
      speed: (map['speed'] as num?)?.toInt() ?? 0,
      outputPath: map['output_path'] as String?,
      error: map['error_message'] as String?,
      retryCount: (map['retry_count'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      startedAt: map['started_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(map['started_at'] as int),
      completedAt: map['completed_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(map['completed_at'] as int),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'url': url,
      'title': title,
      'duration': duration,
      'thumb_url': thumbnail,
      'format_id': formatId,
      'format_label': formatLabel,
      'postprocessing': postprocessing.name,
      'priority': priority.index,
      'height': height,
      'ext': ext,
      'download_subtitles': downloadSubtitles ? 1 : 0,
      'download_cover': downloadCover ? 1 : 0,
      'throttle_kbps': throttleKbps,
      'connections': connections,
      'destination_dir': destinationDir,
      'playlist_title': playlistTitle,
      'file_size': fileSize,
      'downloaded_bytes': downloadedBytes,
      'speed': speed,
      'output_path': outputPath,
      'status': status.index,
      'error_message': error,
      'retry_count': retryCount,
      'source': extractor,
      'created_at': createdAt.millisecondsSinceEpoch,
      'started_at': startedAt?.millisecondsSinceEpoch,
      'completed_at': completedAt?.millisecondsSinceEpoch,
    };
  }

  @override
  String toString() => 'DownloadTask($title, $statusText, $percentValue%)';
}
