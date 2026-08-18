import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  /// 解析视频 URL
  Future<void> parse(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      state = const ParseState(status: ParseStatus.error, error: '请输入视频链接');
      return;
    }
    // 从分享文本里提取真正的 URL（抖音/B站等复制的链接常带标题等文字）
    final target = _extractUrl(trimmed) ?? trimmed;
    state = const ParseState(status: ParseStatus.loading);
    try {
      final info = await YtDlpRunner.parse(target);
      state = ParseState(status: ParseStatus.success, videoInfo: info);
    } on YtDlpException catch (e) {
      state = ParseState(status: ParseStatus.error, error: e.message);
      // 解析也需要登录/cookie 的站点（如抖音）：弹登录提示
      if (isCookieError(e.message)) {
        unawaited(promptSiteLogin(target));
      }
    } catch (e) {
      state = ParseState(status: ParseStatus.error, error: '解析失败: $e');
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
