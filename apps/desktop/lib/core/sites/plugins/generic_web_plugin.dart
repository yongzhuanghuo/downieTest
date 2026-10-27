import 'dart:convert';

import '../../../data/models/video_info.dart';
import '../../ffmpeg/ffmpeg_runner.dart';
import '../site_plugin.dart';

/// 判断嗅探到的 URL 属于哪种媒体类型。
/// 返回 `hls` / `dash` / `direct`；不是媒体返回 null。
String? detectMediaKind(String url) {
  final lower = url.toLowerCase();
  final path = lower.split('?').first.split('#').first;
  // HLS/DASH 分片不单独作为下载目标，优先让用户选 manifest
  if (path.endsWith('.m4s') || path.endsWith('.ts')) return null;
  if (lower.contains('/media-audio-') ||
      lower.contains('mime_type=audio') ||
      lower.contains('mimetype=audio')) {
    return null;
  }
  if (path.endsWith('.m3u8') || lower.contains('.m3u8')) return 'hls';
  if (path.endsWith('.mpd') || lower.contains('.mpd')) return 'dash';
  if (path.endsWith('.mp4') ||
      path.endsWith('.m4v') ||
      path.endsWith('.flv') ||
      lower.contains('mime_type=video') ||
      lower.contains('mimetype=video') ||
      lower.contains('/media-video-') ||
      lower.contains('/video/mp4') ||
      lower.contains('format=mp4')) {
    return 'direct';
  }
  return null;
}

/// 通用用户自定义视频提取下载插件。
///
/// 它不参与 URL 匹配（[matches] 永远 false），只由「用户自定义视频提取」对话框手动选中后
/// 通过 `extractor == 'GenericWeb'` 找回，使用 FFmpeg 下载 HLS/DASH/直链。
class GenericWebPlugin extends SitePlugin {
  @override
  String get id => 'GenericWeb';

  @override
  String get displayName => '用户自定义视频提取';

  @override
  int get priority => 0;

  @override
  bool matches(Uri uri, String rawInput) => false;

  @override
  Future<VideoInfo> parse(String url) async {
    throw const SitePluginException(
      '请使用「用户自定义视频提取」按钮打开页面后再选择媒体',
      retryable: false,
    );
  }

  @override
  Future<String> download(PluginDownloadRequest request) async {
    Map<String, dynamic> spec;
    try {
      spec = jsonDecode(request.task.formatId) as Map<String, dynamic>;
    } catch (_) {
      throw const SitePluginException('用户自定义视频提取下载参数无效', retryable: false);
    }

    final url = spec['url']?.toString() ?? '';
    if (url.isEmpty) {
      throw const SitePluginException('用户自定义视频提取地址为空', retryable: false);
    }

    try {
      return await FFmpegRunner.downloadUrl(
        url: url,
        outputPath: request.outputPath,
        referer: spec['referer']?.toString(),
        cookie: spec['cookie']?.toString(),
        userAgent: _ua,
        onProgress: request.onProgress,
        shouldCancel: request.shouldCancel,
      );
    } on FFmpegException catch (e) {
      throw SitePluginException(e.message, retryable: false);
    }
  }

  static const String _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
}
