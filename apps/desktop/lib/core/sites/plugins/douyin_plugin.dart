import '../../../data/models/video_info.dart';
import '../../engine/douyin_downloader.dart';
import '../../engine/douyin_parser.dart';
import '../site_plugin.dart';

/// 抖音插件：纯 HTTP + a_bogus 签名解析，播放地址走 HTTP 直链下载。
class DouyinPlugin extends SitePlugin {
  @override
  String get id => 'Douyin';

  @override
  String get displayName => '抖音';

  @override
  int get priority => 100;

  @override
  bool matches(Uri uri, String rawInput) {
    final host = uri.host.toLowerCase();
    return host == 'douyin.com' ||
        host.endsWith('.douyin.com') ||
        host == 'iesdouyin.com' ||
        host.endsWith('.iesdouyin.com');
  }

  @override
  Future<VideoInfo> parse(String url) async {
    try {
      return await DouyinParser.parse(url);
    } on DouyinParseException catch (e) {
      throw SitePluginException(e.message, retryable: false);
    }
  }

  @override
  Future<String> download(PluginDownloadRequest request) async {
    try {
      return await DouyinDownloader.download(
        url: request.task.formatId,
        outputPath: request.outputPath,
        onProgress: request.onProgress,
        shouldCancel: request.shouldCancel,
      );
    } on DouyinDownloadException catch (e) {
      // 直链带签名，过期/失效重试也没用
      throw SitePluginException(e.message, retryable: false);
    }
  }
}
