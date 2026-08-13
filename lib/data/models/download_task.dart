import 'package:flutter/foundation.dart';

import 'download_progress.dart';

/// 下载任务状态
enum DownloadStatus {
  pending,
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

  /// 来源网站
  final String extractor;

  /// yt-dlp 格式 ID
  final String formatId;

  /// 格式显示标签
  final String formatLabel;

  /// 是否纯音频
  final bool audioOnly;

  /// 当前状态
  final DownloadStatus status;

  /// 下载进度
  final DownloadProgress? progress;

  /// 输出文件路径（完成后）
  final String? outputPath;

  /// 错误信息
  final String? error;

  /// 创建时间
  final DateTime createdAt;

  const DownloadTask({
    required this.id,
    required this.url,
    required this.title,
    required this.thumbnail,
    required this.extractor,
    required this.formatId,
    required this.formatLabel,
    required this.audioOnly,
    this.status = DownloadStatus.pending,
    this.progress,
    this.outputPath,
    this.error,
    required this.createdAt,
  });

  DownloadTask copyWith({
    DownloadStatus? status,
    DownloadProgress? progress,
    String? outputPath,
    String? error,
  }) {
    return DownloadTask(
      id: id,
      url: url,
      title: title,
      thumbnail: thumbnail,
      extractor: extractor,
      formatId: formatId,
      formatLabel: formatLabel,
      audioOnly: audioOnly,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      outputPath: outputPath ?? this.outputPath,
      error: error ?? this.error,
      createdAt: createdAt,
    );
  }

  /// 是否正在运行
  bool get isRunning =>
      status == DownloadStatus.pending ||
      status == DownloadStatus.downloading ||
      status == DownloadStatus.merging;

  /// 是否已结束
  bool get isFinished =>
      status == DownloadStatus.completed ||
      status == DownloadStatus.failed ||
      status == DownloadStatus.cancelled;

  /// 进度百分比（0-100）
  int get percentValue {
    final p = progress?.percent;
    if (p == null) {
      if (status == DownloadStatus.completed) return 100;
      if (status == DownloadStatus.merging) return 99;
      return 0;
    }
    return (p * 100).round().clamp(0, 100);
  }

  /// 状态中文描述
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

  @override
  String toString() => 'DownloadTask($title, $statusText, $percentValue%)';
}
