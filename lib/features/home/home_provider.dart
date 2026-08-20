import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/engine/douyin_http_extractor.dart';
import '../../core/engine/ytdlp_runner.dart';
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
    final target = _extractUrl(trimmed) ?? trimmed;
    state = const ParseState(status: ParseStatus.loading);

    // 抖音：yt-dlp 提取器被反爬打穿，改走 HTTP 抓分享页 SSR 数据（移动端 UA）
    if (target.contains('douyin.com')) {
      try {
        final id = await DouyinHttpExtractor.resolveId(target);
        if (id == null) {
          state = const ParseState(status: ParseStatus.error, error: '抖音解析失败：无法获取视频 ID');
          return;
        }
        final info = await DouyinHttpExtractor.fetch(id, target);
        state = ParseState(status: ParseStatus.success, videoInfo: info);
      } catch (e) {
        debugPrint('[解析] 抖音失败: $e');
        state = const ParseState(status: ParseStatus.error, error: '抖音解析失败，请重试');
      }
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
      if (needLogin && autoLogin) {
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

  /// 重置状态
  void reset() => state = const ParseState();
}

final parseProvider =
    StateNotifierProvider<ParseNotifier, ParseState>((ref) => ParseNotifier());

/// 从分享文本里提取第一个 URL（如「标题 https://v.douyin.com/xxx 复制此链接」）。
/// 匹配到空格或中文字符为止；找不到 URL 则返回 null。
String? _extractUrl(String text) {
  final m = RegExp(r'https?://[^\s一-鿿]+').firstMatch(text);
  return m?.group(0);
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
  if (m.contains('private') || m.contains('members only') || m.contains('premium')) {
    return '该视频需要会员或登录才能访问';
  }
  return '解析失败，请检查链接是否正确';
}
