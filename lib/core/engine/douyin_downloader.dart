import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../data/models/download_progress.dart';

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

  /// 移动端 UA（与分享页抓取一致，脚本证明移动端 UA 无 Referer 即可下载）
  static const String ua =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 '
      'Safari/604.1';

  /// 下载播放地址 [url] 到 [outputPath]（完整文件路径，含扩展名）
  static Future<String> download({
    required String url,
    required String outputPath,
    required void Function(DownloadProgress) onProgress,
    bool Function()? shouldCancel,
  }) async {
    debugPrint('[抖音下载] 开始: $url');
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(url));
      req.headers['User-Agent'] = ua;
      final resp = await client.send(req);
      if (resp.statusCode != 200) {
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
      client.close();
    }
  }
}
