import '../../data/models/format_option.dart';
import '../../data/models/video_info.dart';

/// 根据偏好选择下载格式。
///
/// [qualityPreference]：
/// - 0 自动最佳
/// - 1 每次询问（调用方负责弹窗；这里返回最佳）
/// - 2/3/4/5/6 限制到 360/480/720/1080/2160
///
/// 限制画质时，如果没有低于上限的格式，按 Downie 的行为选择**最小**的可用格式。
FormatOption? selectFormatForDownload(
  VideoInfo info, {
  int qualityPreference = 0,
  bool preferMp4 = true,
  bool forceMp4 = false,
}) {
  if (info.formats.isEmpty) return null;
  final videos = info.formats.where((f) => !f.audioOnly).toList();
  var pool = videos.isEmpty ? List<FormatOption>.of(info.formats) : videos;

  // Downie 的「强制 MP4」：宁可降低分辨率，也不选 WebM/其他容器。
  if (forceMp4) {
    final mp4 = pool.where(_isMp4).toList();
    if (mp4.isNotEmpty) pool = mp4;
  }

  final maxHeight = switch (qualityPreference) {
    2 => 360,
    3 => 480,
    4 => 720,
    5 => 1080,
    6 => 2160,
    _ => 0,
  };

  var overLimit = false;
  if (maxHeight > 0) {
    final within = pool
        .where((f) => f.height > 0 && f.height <= maxHeight)
        .toList();
    if (within.isNotEmpty) {
      pool = within;
    } else {
      final known = pool.where((f) => f.height > 0).toList();
      if (known.isNotEmpty) {
        pool = known;
        overLimit = true;
      }
    }
  }

  pool.sort((a, b) {
    if (overLimit) {
      // 全都不符合上限时选最小的
      final byHeight = a.height.compareTo(b.height);
      if (byHeight != 0) return byHeight;
    } else {
      final byHeight = b.height.compareTo(a.height);
      if (byHeight != 0) return byHeight;
    }
    if (preferMp4) {
      final aMp4 = _isMp4(a);
      final bMp4 = _isMp4(b);
      if (aMp4 != bMp4) return aMp4 ? -1 : 1;
    }
    final aSize = a.fileSize ?? 0;
    final bSize = b.fileSize ?? 0;
    if (aSize != bSize) return bSize.compareTo(aSize);
    final aFps = a.fps ?? 0;
    final bFps = b.fps ?? 0;
    return bFps.compareTo(aFps);
  });
  return pool.first;
}

bool _isMp4(FormatOption format) =>
    format.ext.toLowerCase() == 'mp4' ||
    format.label.toLowerCase().contains('mp4');
