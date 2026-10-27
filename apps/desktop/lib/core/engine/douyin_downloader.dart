import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../data/models/download_progress.dart';
import '../ffmpeg/ffmpeg_runner.dart';
import '../storage/site_cookies.dart';

/// 抖音直链下载异常
class DouyinDownloadException implements Exception {
  final String message;
  const DouyinDownloadException(this.message);

  @override
  String toString() => 'DouyinDownloadException: $message';
}

/// 抖音 HTTP 直链下载器
///
/// 抖音的播放地址是带签名的 mp4 直链，绕过 yt-dlp 直接用 HTTP 下载。
/// 需带 Referer + 桌面 Chrome UA 绕过防盗链。
class DouyinDownloader {
  DouyinDownloader._();

  /// 桌面 Chrome UA（下载地址是 PC 网页版 aweme/detail 返回的，需桌面 UA + Referer）
  static const String ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

  /// 下载播放地址 [url] 到 [outputPath]（完整文件路径，含扩展名）
  ///
  /// [client] 仅供测试注入；为空时使用默认 http.Client 并在结束时关闭。
  static Future<String> download({
    required String url,
    required String outputPath,
    required void Function(DownloadProgress) onProgress,
    bool Function()? shouldCancel,
    http.Client? client,
    String referer = 'https://www.douyin.com/',
    String cookieSiteId = 'douyin',
  }) async {
    debugPrint('[抖音下载] 开始: $url');
    final cookie = await SiteCookies.loadCookieHeader(cookieSiteId);
    final ownsClient = client == null;
    final effectiveClient = client ?? http.Client();
    try {
      final req = http.Request('GET', Uri.parse(url));
      req.headers['User-Agent'] = ua;
      req.headers['Referer'] = referer;
      if (cookie.isNotEmpty) req.headers['Cookie'] = cookie;
      final resp = await effectiveClient.send(req);
      if (resp.statusCode != 200 && resp.statusCode != 206) {
        throw DouyinDownloadException('下载失败 HTTP ${resp.statusCode}');
      }
      final total = resp.contentLength;
      final file = File(outputPath);
      final sink = file.openWrite();
      int downloaded = 0;
      final sw = Stopwatch()..start();
      try {
        await for (final chunk in resp.stream) {
          if (shouldCancel?.call() == true) {
            throw const DouyinDownloadException('已取消');
          }
          sink.add(chunk);
          downloaded += chunk.length;
          final elapsed = sw.elapsedMilliseconds / 1000.0;
          final speed = elapsed > 0 ? downloaded / elapsed : 0.0;
          onProgress(DownloadProgress(
            downloadedBytes: downloaded,
            totalBytes: total,
            speed: speed,
            percent: total != null && total > 0 ? downloaded / total : null,
            stage: DownloadStage.downloading,
          ));
        }
        await sink.flush();
        await sink.close();
      } catch (e) {
        await sink.close();
        rethrow;
      }
      debugPrint('[抖音下载] 完成: $outputPath ($downloaded 字节)');
      return outputPath;
    } finally {
      if (ownsClient) effectiveClient.close();
    }
  }

  /// 兜底下载：登录浏览器只拿到了 DASH 的 video/audio 分轨时，
  /// 分别下载后用 ffmpeg 合并成完整 MP4。
  static Future<String> downloadMultipart({
    required String videoUrl,
    required String audioUrl,
    required String outputPath,
    required void Function(DownloadProgress) onProgress,
    bool Function()? shouldCancel,
  }) async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final videoTmp = '$outputPath.$stamp.video.mp4';
    final audioTmp = '$outputPath.$stamp.audio.mp4';
    try {
      await download(
        url: videoUrl,
        outputPath: videoTmp,
        shouldCancel: shouldCancel,
        onProgress: (p) => onProgress(DownloadProgress(
          downloadedBytes: p.downloadedBytes,
          totalBytes: p.totalBytes,
          speed: p.speed,
          percent: p.percent == null ? null : p.percent! * 0.6,
          stage: DownloadStage.downloadingVideo,
        )),
      );
      if (shouldCancel?.call() == true) {
        throw const DouyinDownloadException('已取消');
      }
      await download(
        url: audioUrl,
        outputPath: audioTmp,
        shouldCancel: shouldCancel,
        onProgress: (p) => onProgress(DownloadProgress(
          downloadedBytes: p.downloadedBytes,
          totalBytes: p.totalBytes,
          speed: p.speed,
          percent: p.percent == null ? null : 0.6 + p.percent! * 0.2,
          stage: DownloadStage.downloadingAudio,
        )),
      );
      if (shouldCancel?.call() == true) {
        throw const DouyinDownloadException('已取消');
      }
      onProgress(const DownloadProgress(
        downloadedBytes: 0,
        speed: 0,
        percent: 0.8,
        stage: DownloadStage.merging,
        detail: '合并音视频',
      ));
      return await FFmpegRunner.mergeVideoAudio(
        videoPath: videoTmp,
        audioPath: audioTmp,
        outputPath: outputPath,
        onProgress: (value) => onProgress(DownloadProgress(
          downloadedBytes: 0,
          speed: 0,
          percent: 0.8 + value * 0.2,
          stage: DownloadStage.merging,
          detail: '合并音视频',
        )),
      );
    } finally {
      for (final path in [videoTmp, audioTmp]) {
        try {
          final file = File(path);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
    }
  }
}
