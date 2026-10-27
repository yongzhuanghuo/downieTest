import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:convert';

import '../../core/engine/douyin_parser.dart';
import '../../core/engine/ytdlp_runner.dart';
import '../../core/sites/generic_html_extractor.dart';
import '../../core/sites/plugin_registry.dart';
import '../../core/sites/plugins/generic_web_plugin.dart';
import '../../core/sites/site_plugin.dart';
import '../../core/storage/settings_storage.dart';
import '../../data/models/format_option.dart';
import '../../data/models/video_info.dart';
import '../downloads/site_login_prompt.dart';

/// 解析状态
enum ParseStatus { idle, loading, success, error }

/// 解析状态数据
@immutable
class ParseState {
  final ParseStatus status;
  final VideoInfo? videoInfo;
  final String? error;

  const ParseState({
    this.status = ParseStatus.idle,
    this.videoInfo,
    this.error,
  });

  bool get isLoading => status == ParseStatus.loading;
  bool get isSuccess => status == ParseStatus.success;
  bool get isError => status == ParseStatus.error;
}

/// 解析 Notifier
class ParseNotifier extends StateNotifier<ParseState> {
  ParseNotifier() : super(const ParseState());

  /// 解析视频 URL（公开入口）
  Future<void> parse(String url) => _doParse(url, autoLogin: true);

  /// 解析实现。autoLogin 为 true 时，遇到需要登录的站点会弹登录并自动重试一次。
  Future<void> _doParse(String url, {required bool autoLogin}) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      state = const ParseState(status: ParseStatus.error, error: '请输入视频链接');
      return;
    }
    // 从分享文本里提取真正的 URL（抖音/B站等复制的链接常带标题等文字）
    final target = wholeHttpUrl(trimmed) ??
        firstVideoUrl(trimmed) ??
        trimmed;
    state = const ParseState(status: ParseStatus.loading);

    // 直接媒体地址：不抓页面，直接生成可下载格式
    final directKind = detectMediaKind(target);
    if (directKind != null) {
      final uri = Uri.tryParse(target);
      final info = VideoInfo(
        url: target,
        title: uri?.host ?? target,
        duration: 0,
        uploader: uri?.host ?? '',
        thumbnail: '',
        extractor: 'GenericWeb',
        videoId: target.hashCode.abs().toString(),
        formats: [
          FormatOption(
            formatId: jsonEncode({
              'url': target,
              'kind': directKind,
              'referer': target,
              'cookie': '',
            }),
            label: '直链 ${directKind.toUpperCase()}',
            height: 0,
            ext: 'mp4',
          ),
        ],
      );
      state = ParseState(status: ParseStatus.success, videoInfo: info);
      return;
    }

    // 登录浏览器已经拦截到 aweme/detail 时，直接用缓存，避免再次走签名/风控
    final cachedDouyin = DouyinParser.cachedVideo(target);
    if (cachedDouyin != null) {
      debugPrint('[解析] 使用登录浏览器缓存的抖音数据: ${cachedDouyin.videoId}');
      state = ParseState(
        status: ParseStatus.success,
        videoInfo: cachedDouyin,
      );
      return;
    }

    // 站点插件优先（抖音等自研解析）；没有命中再走 yt-dlp 兜底
    final plugin = PluginRegistry.instance.find(target);
    debugPrint('[解析] plugin=${plugin?.id ?? 'none'} target=$target');
    if (plugin != null) {
      try {
        final info = await plugin.parse(target);
        state = ParseState(status: ParseStatus.success, videoInfo: info);
      } on SitePluginException catch (e) {
        if (!e.fallbackToYtDlp) {
          debugPrint('[解析] ${plugin.displayName}失败: ${e.message}');
          state = ParseState(
            status: ParseStatus.error,
            error: e.requiresLogin
                ? '该网站需要登录后才能解析'
                : '${plugin.displayName}解析失败，请重试',
          );
          if (e.requiresLogin &&
              autoLogin &&
              !SettingsStorage.instance.current.disableLoginDialogs) {
            final loggedIn = await promptSiteLogin(target);
            if (loggedIn) {
              await _doParse(url, autoLogin: false);
            }
          }
          return;
        }
        debugPrint('[解析] ${plugin.displayName}不支持该链接，回退 yt-dlp: ${e.message}');
      } catch (e) {
        debugPrint('[解析] ${plugin.displayName}异常: $e');
        state = ParseState(
          status: ParseStatus.error,
          error: '${plugin.displayName}解析失败，请重试',
        );
        return;
      }
    }

    // 通用 HTML 提取：在 yt-dlp 之前找 og:video / video / JSON-LD / m3u8
    final htmlInfo = await GenericHtmlExtractor.tryParse(target);
    if (htmlInfo != null) {
      state = ParseState(status: ParseStatus.success, videoInfo: htmlInfo);
      return;
    }

    try {
      final info = await YtDlpRunner.parse(target);
      state = ParseState(status: ParseStatus.success, videoInfo: info);
    } on YtDlpException catch (e) {
      // 技术日志只输出到终端，不显示在界面上
      debugPrint('[解析] $target 失败: ${e.message}');
      final needLogin = isCookieError(e.message);
      state = ParseState(
        status: ParseStatus.error,
        error: needLogin ? '该网站需要登录后才能解析' : _friendlyError(e.message),
      );
      if (needLogin &&
          autoLogin &&
          !SettingsStorage.instance.current.disableLoginDialogs) {
        final loggedIn = await promptSiteLogin(target);
        if (loggedIn) {
          // 登录成功，自动重新解析一次（不再自动弹登录，避免死循环）
          await _doParse(url, autoLogin: false);
        }
      }
    } catch (e) {
      debugPrint('[解析] $target 异常: $e');
      state = const ParseState(
        status: ParseStatus.error,
        error: '解析失败，请检查链接是否正确',
      );
    }
  }

  /// 外部注入解析结果（用户自定义视频提取等）
  void setResult(VideoInfo info) {
    state = ParseState(status: ParseStatus.success, videoInfo: info);
  }

  /// 重置状态
  void reset() => state = const ParseState();
}

final parseProvider =
    StateNotifierProvider<ParseNotifier, ParseState>((ref) => ParseNotifier());

// 遇到空白、中文或全角标点就结束，避免把分享文案里的下一段文字吞进 URL。
final _urlPattern =
    RegExp('https?://[^\\s\\u3000-\\u303f\\u4e00-\\u9fff\\uff00-\\uffef]+');

/// 中文/全角标点常被复制进分享文本，不能当成 URL 的一部分。
const _trailingPunctuation = '.,;:!?)]}>"\'、。，；：'
    '！？）】》”’';

/// 整段输入本身就是一个 http(s) URL 时原样返回。
///
/// 这样 URL 路径/参数里的中文不会被分享文案的提取规则截断。
String? wholeHttpUrl(String text) {
  var value = text.trim();
  while (value.isNotEmpty &&
      _trailingPunctuation.contains(value[value.length - 1])) {
    value = value.substring(0, value.length - 1);
  }
  if (value.isEmpty || RegExp(r'\s').hasMatch(value)) return null;
  final uri = Uri.tryParse(value);
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty) {
    return null;
  }
  return value;
}

/// 从分享文本里提取全部 URL，按出现顺序去重。
///
/// 抖音/B站等 App 的分享文本形如「标题 https://v.douyin.com/xxx 复制此链接」，
/// 一次粘贴多条链接时也会走这里。
List<String> extractUrls(String text) {
  final result = <String>[];
  final seen = <String>{};
  // `https://a,https://b` 这种半角分隔也拆开
  final normalized = text.replaceAllMapped(
    RegExp(r'[,;](?=https?://)'),
    (_) => '\n',
  );
  for (final match in _urlPattern.allMatches(normalized)) {
    var url = match.group(0)!;
    while (url.isNotEmpty && _trailingPunctuation.contains(url[url.length - 1])) {
      url = url.substring(0, url.length - 1);
    }
    if (url.isEmpty || !seen.add(url)) continue;
    result.add(url);
  }
  return result;
}

/// 提取第一个 URL；找不到返回 null。
String? extractFirstUrl(String text) {
  final urls = extractUrls(text);
  return urls.isEmpty ? null : urls.first;
}

/// 分享文案里常见的无协议短链（`v.douyin.com/xxx`、`b23.tv/xxx` 等）。
final _bareVideoPattern = RegExp(
  '(?<![\\w.])((?:v\\.douyin\\.com|www\\.douyin\\.com/video|'
  'www\\.iesdouyin\\.com/share/video|b23\\.tv|v\\.kuaishou\\.com|'
  'xhslink\\.com|www\\.xiaohongshu\\.com/explore|weibo\\.com/tv|'
  'm\\.weibo\\.cn/detail)/'
  '[^\\s\\u3000-\\u303f\\u4e00-\\u9fff\\uff00-\\uffef]*)',
  caseSensitive: false,
);

/// 从分享文案里提取普通 URL + 无协议短链，按出现顺序去重。
List<String> extractVideoUrls(String text) {
  final result = <String>[...extractUrls(text)];
  final seen = result.toSet();
  for (final match in _bareVideoPattern.allMatches(text)) {
    var url = match.group(1)!;
    while (url.isNotEmpty &&
        _trailingPunctuation.contains(url[url.length - 1])) {
      url = url.substring(0, url.length - 1);
    }
    if (url.isEmpty) continue;
    final full = 'https://$url';
    if (seen.add(full)) result.add(full);
  }
  return result;
}

bool _looksLikeVideoHost(String url) {
  final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
  return host.endsWith('douyin.com') ||
      host.endsWith('iesdouyin.com') ||
      host == 'b23.tv' ||
      host.endsWith('kuaishou.com') ||
      host.endsWith('xiaohongshu.com') ||
      host == 'xhslink.com' ||
      host.endsWith('weibo.com') ||
      host.endsWith('weibo.cn');
}

/// 分享文案里优先取视频站点链接，其次取第一个 URL。
String? firstVideoUrl(String text) {
  final urls = extractVideoUrls(text);
  if (urls.isEmpty) return null;
  for (final url in urls) {
    if (_looksLikeVideoHost(url)) return url;
  }
  return urls.first;
}

/// 把 yt-dlp 的技术错误转成用户能看懂的提示
String _friendlyError(String message) {
  final m = message.toLowerCase();
  if (m.contains('unsupported url') || m.contains('unsupported')) {
    return '不支持该链接，请确认链接是否正确';
  }
  if (m.contains('not found') || m.contains('404')) {
    return '视频不存在或已被删除';
  }
  if (m.contains('drm') ||
      m.contains('widevine') ||
      m.contains('fairplay') ||
      m.contains('playready')) {
    return '该内容受 DRM 保护，无法下载';
  }
  if (m.contains('private') || m.contains('members only') || m.contains('premium')) {
    return '该视频需要会员或登录才能访问';
  }
  return '解析失败，请检查链接是否正确';
}
