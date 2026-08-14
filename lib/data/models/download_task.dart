import 'package:flutter/foundation.dart';

import 'download_progress.dart';

/// 下载任务状态
enum DownloadStatus {
  pending,    // 等待中（队列里）
  downloading,
  merging,
  completed,
  failed,
  cancelled,
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

  /// 缩略图 URL
  final String thumbnail;

  /// 来源网站 (extractor_key，如 "BiliBili" "Youtube")
  final String extractor;

  /// yt-dlp 格式 ID
  final String formatId;

  /// 格式显示标签（如 "1080P MP4"）
  final String formatLabel;

  /// 高度（纯音频=0）
  final int height;

  /// 扩展名（mp4/mp3/webm...）
  final String ext;

  /// 是否纯音频
  final bool audioOnly;

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
    required this.thumbnail,
    required this.extractor,
    required this.formatId,
    required this.formatLabel,
    required this.height,
    required this.ext,
    required this.audioOnly,
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

  DownloadTask copyWith({
    DownloadStatus? status,
    DownloadProgress? progress,
    int? fileSize,
    int? downloadedBytes,
    int? speed,
    String? outputPath,
    String? error,
    int? retryCount,
    DateTime? startedAt,
    DateTime? completedAt,
  }) {
    return DownloadTask(
      id: id,
      url: url,
      title: title,
      thumbnail: thumbnail,
      extractor: extractor,
      formatId: formatId,
      formatLabel: formatLabel,
      height: height,
      ext: ext,
      audioOnly: audioOnly,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      fileSize: fileSize ?? this.fileSize,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      speed: speed ?? this.speed,
      outputPath: outputPath ?? this.outputPath,
      error: error ?? this.error,
      retryCount: retryCount ?? this.retryCount,
      createdAt: createdAt,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  // ==================== 是否状态 ====================

  bool get isPending => status == DownloadStatus.pending;
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
    }
  }

  // ==================== SQLite 序列化 ====================

  factory DownloadTask.fromMap(Map<String, dynamic> map) {
    return DownloadTask(
      id: map['id'] as String,
      url: map['url'] as String,
      title: (map['title'] as String?) ?? '',
      thumbnail: (map['thumb_url'] as String?) ?? '',
      extractor: (map['source'] as String?) ?? 'Unknown',
      formatId: map['format_id'] as String,
      formatLabel: (map['format_label'] as String?) ?? '',
      height: (map['height'] as num?)?.toInt() ?? 0,
      ext: (map['ext'] as String?) ?? 'mp4',
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
      'thumb_url': thumbnail,
      'format_id': formatId,
      'format_label': formatLabel,
      'height': height,
      'ext': ext,
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
