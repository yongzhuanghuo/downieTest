import 'package:flutter/foundation.dart';

import 'format_option.dart';

/// 解析后的视频信息
@immutable
class VideoInfo {
  /// 原始 URL
  final String url;

  /// 视频标题
  final String title;

  /// 视频时长（秒）
  final int duration;

  /// 上传者
  final String uploader;

  /// 缩略图 URL
  final String thumbnail;

  /// 网站名（YouTube / Bilibili 等）
  final String extractor;

  /// 视频 ID
  final String videoId;

  /// 可用格式列表（已按清晰度从高到低排序）
  final List<FormatOption> formats;

  /// 可用字幕语言列表
  final List<String> subtitleLangs;

  /// 原始 JSON（调试用）
  final Map<String, dynamic>? rawJson;

  const VideoInfo({
    required this.url,
    required this.title,
    required this.duration,
    required this.uploader,
    required this.thumbnail,
    required this.extractor,
    required this.videoId,
    required this.formats,
    this.subtitleLangs = const [],
    this.rawJson,
  });

  /// 时长可读格式 "MM:SS" 或 "H:MM:SS"
  String get durationText {
    if (duration <= 0) return '未知';
    final h = duration ~/ 3600;
    final m = (duration % 3600) ~/ 60;
    final s = duration % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// 是否有字幕
  bool get hasSubtitles => subtitleLangs.isNotEmpty;

  /// 推荐格式（默认 1080p，降级到最高可用）
  FormatOption? get recommendedFormat {
    if (formats.isEmpty) return null;
    // 优先 1080p
    for (final f in formats) {
      if (f.height == 1080 && !f.audioOnly) return f;
    }
    // 降级到第一个非音频格式
    for (final f in formats) {
      if (!f.audioOnly) return f;
    }
    return formats.first;
  }

  @override
  String toString() =>
      'VideoInfo($title, $durationText, ${formats.length} formats)';

  Map<String, dynamic> toJson() => {
        'url': url,
        'title': title,
        'duration': duration,
        'uploader': uploader,
        'thumbnail': thumbnail,
        'extractor': extractor,
        'videoId': videoId,
        'formats': formats.map((f) => f.toJson()).toList(),
        'subtitleLangs': subtitleLangs,
      };
}
