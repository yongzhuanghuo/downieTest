import 'plugins/bilibili_plugin.dart';
import 'plugins/douyin_plugin.dart';
import 'plugins/generic_web_plugin.dart';
import 'plugins/kuaishou_plugin.dart';
import 'plugins/tiktok_plugin.dart';
import 'site_plugin.dart';

/// 站点插件注册表。
///
/// 新增站点：在 `plugins/` 下实现 [SitePlugin]，然后加到这里。
/// 没有命中的 URL 走 yt-dlp 兜底。
class PluginRegistry {
  PluginRegistry._(List<SitePlugin> plugins)
      : _plugins = List<SitePlugin>.unmodifiable(plugins);

  static final PluginRegistry instance = PluginRegistry._(<SitePlugin>[
    DouyinPlugin(),
    BilibiliPlugin(),
    TikTokPlugin(),
    KuaishouPlugin(),
    GenericWebPlugin(),
    // 后续：YouTubePlugin / InstagramPlugin / XPlugin
  ]);

  final List<SitePlugin> _plugins;

  List<SitePlugin> get all => _plugins;

  /// 按优先级找能处理 [url] 的插件；没有则返回 null（交给 yt-dlp）。
  SitePlugin? find(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;

    final sorted = List<SitePlugin>.of(_plugins)
      ..sort((a, b) => b.priority.compareTo(a.priority));
    for (final plugin in sorted) {
      if (plugin.matches(uri, url)) return plugin;
    }
    return null;
  }

  /// 下载阶段按 [SitePlugin.id] 找回插件。
  SitePlugin? byId(String id) {
    for (final plugin in _plugins) {
      if (plugin.id == id) return plugin;
    }
    return null;
  }
}
