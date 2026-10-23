import '../../data/models/download_progress.dart';
import '../../data/models/download_task.dart';
import '../../data/models/video_info.dart';

/// 站点插件异常。
///
/// - [retryable]：失败后是否值得重试（网络抖动=true，签名/直链失效=false）
/// - [requiresLogin]：是否应弹站点登录并重试
/// - [fallbackToYtDlp]：插件明确不支持时，交回 yt-dlp 兜底
class SitePluginException implements Exception {
  final String message;
  final bool retryable;
  final bool requiresLogin;
  final bool fallbackToYtDlp;

  const SitePluginException(
    this.message, {
    this.retryable = true,
    this.requiresLogin = false,
    this.fallbackToYtDlp = false,
  });

  @override
  String toString() => 'SitePluginException: $message';
}

/// 插件下载请求。
///
/// 队列只负责调度、持久化和进度，具体怎么下载由插件决定：
/// 抖音是 HTTP 直链，B 站/YouTube 可以是 DASH/HLS 分片。
class PluginDownloadRequest {
  final DownloadTask task;
  final String outputPath;
  final void Function(DownloadProgress progress) onProgress;
  final bool Function() shouldCancel;

  const PluginDownloadRequest({
    required this.task,
    required this.outputPath,
    required this.onProgress,
    required this.shouldCancel,
  });
}

/// 站点插件接口。
///
/// 约定：
/// - [id] 会写入 `VideoInfo.extractor` / `DownloadTask.extractor`，下载时据此找回插件
/// - [parse] 返回的 [VideoInfo.extractor] 必须是 [id]
/// - 匹配不到的站点交给 yt-dlp 兜底
abstract class SitePlugin {
  /// 稳定标识，如 `Douyin`、`Bilibili`
  String get id;

  /// 界面展示名，如 `抖音`
  String get displayName;

  /// 数值越大越优先；同一 URL 命中多个插件时用
  int get priority => 0;

  /// 是否能处理这个 URL
  bool matches(Uri uri, String rawInput);

  /// 解析视频信息
  Future<VideoInfo> parse(String url);

  /// 下载到 [PluginDownloadRequest.outputPath]，返回最终文件路径
  Future<String> download(PluginDownloadRequest request);
}
