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
      // 抖音无数据/风控通常是因为没登录或需要过验证码；
      // 与 Downie 一样直接弹登录浏览器，登录后用 cookie 重试。
      // 即便错误不是典型的登录文案，也先让用户走一遍登录/验证，
      // 这是抖音目前唯一稳定的用户可见恢复路径。
      throw SitePluginException(
        e.message,
        retryable: false,
        requiresLogin: true,
      );
    } catch (e) {
      // 网络/JSON/node 签名等非预期错误也进入登录/验证码流程，
      // 避免用户只看到一句「解析失败」而没有恢复入口。
      throw SitePluginException(
        e.toString(),
        retryable: false,
        requiresLogin: true,
      );
    }
  }

  @override
  Future<String> download(PluginDownloadRequest request) async {
    try {
      final formatId = request.task.formatId;
      // 媒体分轨兜底格式：videoUrl\naudioUrl
      if (formatId.contains('\n')) {
        final parts = formatId.split('\n');
        if (parts.length >= 2 && parts[1].isNotEmpty) {
          return await DouyinDownloader.downloadMultipart(
            videoUrl: parts[0],
            audioUrl: parts[1],
            outputPath: request.outputPath,
            onProgress: request.onProgress,
            shouldCancel: request.shouldCancel,
          );
        }
      }
      return await DouyinDownloader.download(
        url: formatId,
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
