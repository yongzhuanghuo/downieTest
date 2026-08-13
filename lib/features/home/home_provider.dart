import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/engine/ytdlp_runner.dart';
import '../../data/models/video_info.dart';

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
    state = const ParseState(status: ParseStatus.loading);
    try {
      final info = await YtDlpRunner.parse(trimmed);
      state = ParseState(status: ParseStatus.success, videoInfo: info);
    } on YtDlpException catch (e) {
      state = ParseState(status: ParseStatus.error, error: e.message);
    } catch (e) {
      state = ParseState(status: ParseStatus.error, error: '解析失败: $e');
    }
  }

  /// 重置状态
  void reset() => state = const ParseState();
}

final parseProvider =
    StateNotifierProvider<ParseNotifier, ParseState>((ref) => ParseNotifier());
