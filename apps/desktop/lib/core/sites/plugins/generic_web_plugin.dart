import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../data/models/download_progress.dart';
import '../../../data/models/video_info.dart';
import '../../engine/chunked_http_downloader.dart';
import '../../engine/hls_downloader.dart';
import '../../engine/ytdlp_runner.dart';
import '../../ffmpeg/ffmpeg_runner.dart';
import '../../platform/system_proxy.dart';
import '../../storage/settings_storage.dart';
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

    final configuredProxy = SettingsStorage.instance.current.proxy;
    final proxy = configuredProxy.trim().isNotEmpty
        ? SystemProxy.normalize(configuredProxy)
        : await SystemProxy.detect();
    final capturedUa = spec['userAgent']?.toString().trim() ?? '';
    final referer = spec['referer']?.toString();
    final cookie = spec['cookie']?.toString();
    final kind = spec['kind']?.toString() ?? '';
    final userAgent = capturedUa.isEmpty ? _ua : capturedUa;

    final lowerUrl = url.toLowerCase();
    final isHls = kind == 'hls' || lowerUrl.contains('.m3u8');
    final isDash = kind == 'dash' || lowerUrl.contains('.mpd');
    final headers = <String, String>{
      if (referer != null && referer.isNotEmpty) 'Referer': referer,
      'User-Agent': userAgent,
      if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie,
    };
    final settings = SettingsStorage.instance.current;
    // HLS 分片小，CDN 通常按连接限速；16 连接起步（用户设更高则跟随）。
    final configuredConnections = request.task.connections > 0
        ? request.task.connections
        : settings.connectionsPerDownload;
    final hlsConnections = configuredConnections < 16
        ? 16
        : configuredConnections;

    // HLS：Dart 多连接拉分片 + 本地 ffmpeg 解密。
    //
    // 绝对不能再回退到「ffmpeg 直接拉网络」：ffmpeg 遇到失败分片会
    // 跳过并返回成功，产出残缺文件（实测跑到第 2048 片后 DNS 失败）。
    // AES 也不能交给 yt-dlp：它的纯 Python AES 实测只有 ~130 KB/s，
    // 16 个 2 秒分片要 22 秒，且 -N 加到 16 也没有提升。
    if (isHls) {
      try {
        final result = await HlsDownloader.download(
          url: url,
          headers: headers,
          connections: hlsConnections,
          proxy: proxy,
          shouldCancel: request.shouldCancel,
          onProgress: (done, total, bytes, speed) {
            request.onProgress(DownloadProgress(
              downloadedBytes: bytes,
              speed: speed,
              percent: total > 0 ? done / total : null,
              stage: DownloadStage.downloading,
              detail: 'HLS 分片 $done/$total',
            ));
          },
        );
        request.onProgress(const DownloadProgress(
          downloadedBytes: 0,
          speed: 0,
          percent: 1,
          stage: DownloadStage.merging,
          detail: '解密并合并 HLS',
        ));
        try {
          return await FFmpegRunner.remuxHls(
            playlistPath: result.playlistPath,
            outputPath: request.outputPath,
          );
        } on FFmpegException catch (e) {
          throw SitePluginException(
            'HLS 合并失败: ${e.message}',
            retryable: false,
          );
        } finally {
          await result.cleanup();
        }
      } on HlsCancelledException {
        throw const SitePluginException('已取消', retryable: false);
      } on HlsUnsupportedException catch (e) {
        debugPrint('[GenericWeb] HLS 不支持，回退 yt-dlp: ${e.message}');
      } on HlsDownloadException catch (e) {
        throw SitePluginException('HLS 下载失败: ${e.message}', retryable: true);
      }

      // 直播 / BYTERANGE / 独立音轨等少数情况交给 yt-dlp。
      try {
        return await YtDlpRunner.download(
          url: url,
          formatId: 'best',
          outputPath: request.outputPath,
          onProgress: request.onProgress,
          shouldCancel: request.shouldCancel,
          referer: referer,
          userAgent: userAgent,
          cookieHeader: cookie,
          passCookies: false,
          forceNativeFragments: true,
          connections: request.task.connections,
          throttleKbps: request.task.throttleKbps,
          logPath: await _taskLogPath(request.task.id),
        );
      } on YtDlpException catch (e) {
        throw SitePluginException(e.message, retryable: false);
      }
    }

    if (isDash) {
      try {
        return await YtDlpRunner.download(
          url: url,
          formatId: 'best',
          outputPath: request.outputPath,
          onProgress: request.onProgress,
          shouldCancel: request.shouldCancel,
          referer: referer,
          userAgent: userAgent,
          cookieHeader: cookie,
          passCookies: false,
          forceNativeFragments: true,
          connections: request.task.connections,
          throttleKbps: request.task.throttleKbps,
          logPath: await _taskLogPath(request.task.id),
        );
      } on YtDlpException catch (e) {
        throw SitePluginException(e.message, retryable: false);
      }
    }

    // 直链 MP4/FLV：用多连接 Range 下载。CDN 常按单连接限速，4 连接能
    // 把速度拉回正常水平；服务器不支持 Range 时抛异常并回退 ffmpeg。
    if (!isHls && !isDash) {
      final connectionCount = request.task.connections > 0
          ? request.task.connections
          : settings.connectionsPerDownload;
      final chunkMb = settings.chunkSizeMb > 0 ? settings.chunkSizeMb : 2;
      try {
        await ChunkedHttpDownloader.download(
          url: url,
          outputPath: request.outputPath,
          headers: headers,
          connections: connectionCount,
          chunkSizeBytes: chunkMb * 1024 * 1024,
          proxy: proxy,
          shouldCancel: request.shouldCancel,
          onProgress: (downloaded, total, speed) {
            request.onProgress(DownloadProgress(
              downloadedBytes: downloaded,
              totalBytes: total,
              speed: speed,
              percent: total != null && total > 0
                  ? (downloaded / total).clamp(0.0, 1.0)
                  : null,
              stage: DownloadStage.downloading,
              detail: '分块下载',
            ));
          },
        );
        return request.outputPath;
      } on DownloadCancelledException {
        throw const SitePluginException('已取消', retryable: false);
      } on ChunkedDownloadException catch (e) {
        debugPrint('[GenericWeb] 分块下载失败，回退 ffmpeg: ${e.message}');
      }
    }

    try {
      return await FFmpegRunner.downloadUrl(
        url: url,
        outputPath: request.outputPath,
        referer: referer,
        cookie: cookie,
        userAgent: userAgent,
        proxy: proxy,
        onProgress: request.onProgress,
        shouldCancel: request.shouldCancel,
      );
    } on FFmpegException catch (e) {
      throw SitePluginException(e.message, retryable: false);
    }
  }

  Future<String?> _taskLogPath(String taskId) async {
    try {
      final dir = await SettingsStorage.getStorageDir();
      return '${dir.path}/logs/task_$taskId.log';
    } catch (_) {
      return null;
    }
  }

  static const String _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
}
