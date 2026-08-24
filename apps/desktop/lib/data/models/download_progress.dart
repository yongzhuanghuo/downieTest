import 'package:flutter/foundation.dart';

/// 下载进度状态
@immutable
class DownloadProgress {
  /// 已下载字节
  final int downloadedBytes;

  /// 总字节（未知为 null）
  final int? totalBytes;

  /// 下载速度（字节/秒）
  final double speed;

  /// 进度百分比（0.0 - 1.0），未知为 null
  final double? percent;

  /// 预计剩余秒数
  final int? eta;

  /// 当前阶段
  final DownloadStage stage;

  /// 阶段附加信息（如 "下载视频流" / "下载音频流" / "合并中"）
  final String? detail;

  const DownloadProgress({
    required this.downloadedBytes,
    required this.speed,
    this.totalBytes,
    this.percent,
    this.eta,
    this.stage = DownloadStage.downloading,
    this.detail,
  });

  /// 已下载大小可读字符串
  String get downloadedText => _formatBytes(downloadedBytes);

  /// 总大小可读字符串
  String get totalText =>
      totalBytes == null ? '未知' : _formatBytes(totalBytes!);

  /// 速度可读字符串
  String get speedText => '${_formatBytes(speed.toInt())}/s';

  /// 剩余时间可读字符串
  String get etaText {
    if (eta == null || eta == 0) return '计算中';
    if (eta! < 60) return '${eta}s';
    final m = eta! ~/ 60;
    final s = eta! % 60;
    return '${m}m ${s}s';
  }

  /// 进度百分比文本
  String get percentText =>
      percent == null ? '--' : '${(percent! * 100).toStringAsFixed(1)}%';

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    double size = bytes.toDouble();
    int unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(1)} ${units[unit]}';
  }

  @override
  String toString() =>
      'DownloadProgress($percentText, $speedText, ETA $etaText)';
}

/// 下载阶段
enum DownloadStage {
  /// 准备中
  preparing,

  /// 下载视频流
  downloadingVideo,

  /// 下载音频流
  downloadingAudio,

  /// 下载中（通用）
  downloading,

  /// FFmpeg 合并中
  merging,

  /// 后处理（嵌入字幕等）
  postProcessing,

  /// 已完成
  completed,

  /// 失败
  failed,
}

/// 下载阶段中文描述
extension DownloadStageX on DownloadStage {
  String get label {
    switch (this) {
      case DownloadStage.preparing:
        return '准备中';
      case DownloadStage.downloadingVideo:
        return '下载视频流';
      case DownloadStage.downloadingAudio:
        return '下载音频流';
      case DownloadStage.downloading:
        return '下载中';
      case DownloadStage.merging:
        return '合并中';
      case DownloadStage.postProcessing:
        return '后处理';
      case DownloadStage.completed:
        return '已完成';
      case DownloadStage.failed:
        return '失败';
    }
  }
}
