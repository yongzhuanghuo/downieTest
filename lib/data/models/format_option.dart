import 'package:flutter/foundation.dart';

/// 视频格式选项（一个可下载的清晰度/格式）
@immutable
class FormatOption {
  /// yt-dlp format_id，如 "137" 或 "137+140"
  final String formatId;

  /// 显示标签，如 "1080p MP4"
  final String label;

  /// 分辨率高度（0 表示纯音频）
  final int height;

  /// 扩展名，如 "mp4"、"mp3"、"webm"
  final String ext;

  /// 是否为纯音频
  final bool audioOnly;

  /// 文件大小估算（字节），可为 null
  final int? fileSize;

  /// 是否需要合并音视频流
  final bool needsMerge;

  /// 视频码率（kbps）
  final int? vbr;

  /// 音频码率（kbps）
  final int? abr;

  /// 原始 FPS
  final int? fps;

  const FormatOption({
    required this.formatId,
    required this.label,
    required this.height,
    required this.ext,
    this.audioOnly = false,
    this.fileSize,
    this.needsMerge = false,
    this.vbr,
    this.abr,
    this.fps,
  });

  /// 画质等级标签（用于 UI）
  String get qualityTag {
    if (audioOnly) return 'MP3';
    if (height >= 2160) return '4K';
    if (height >= 1440) return '2K';
    if (height >= 1080) return 'HD';
    if (height >= 720) return 'HD';
    return 'SD';
  }

  /// 是否为 VIP 画质（4K/2K）
  bool get isVipQuality => height >= 1440;

  /// 文件大小可读字符串
  String get fileSizeText {
    if (fileSize == null || fileSize == 0) return '未知';
    const units = ['B', 'KB', 'MB', 'GB'];
    double size = fileSize!.toDouble();
    int unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(1)} ${units[unit]}';
  }

  @override
  String toString() => 'FormatOption($label, $formatId, $fileSizeText)';

  Map<String, dynamic> toJson() => {
        'formatId': formatId,
        'label': label,
        'height': height,
        'ext': ext,
        'audioOnly': audioOnly,
        'fileSize': fileSize,
        'needsMerge': needsMerge,
        'vbr': vbr,
        'abr': abr,
        'fps': fps,
      };
}
