import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/engine/ytdlp_runner.dart';
import '../../data/models/download_progress.dart';
import '../../data/models/download_task.dart';
import '../../data/models/format_option.dart';
import '../../data/models/video_info.dart';

/// 下载列表 Notifier
///
/// 管理所有下载任务的生命周期：添加、下载、进度更新、取消、清理。
class DownloadListNotifier extends StateNotifier<List<DownloadTask>> {
  DownloadListNotifier() : super(const []);

  /// 已取消任务 ID 集合（用于通知 yt-dlp 子进程终止）
  final Set<String> _cancelled = {};

  /// 添加并开始下载任务
  Future<void> startDownload({
    required VideoInfo videoInfo,
    required FormatOption format,
  }) async {
    final task = DownloadTask(
      id: const Uuid().v4(),
      url: videoInfo.url,
      title: videoInfo.title,
      thumbnail: videoInfo.thumbnail,
      extractor: videoInfo.extractor,
      formatId: format.formatId,
      formatLabel: format.label,
      audioOnly: format.audioOnly,
      createdAt: DateTime.now(),
    );

    state = [task, ...state];

    // 确定输出目录（桌面端使用系统下载目录）
    String outputDir;
    try {
      final dir = await getDownloadsDirectory();
      outputDir = dir?.path ?? '.';
    } catch (_) {
      outputDir = '.';
    }

    // yt-dlp 输出模板：标题 + 视频 ID，由 yt-dlp 自动补扩展名
    final safeTitle =
        videoInfo.title.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_').trim();
    final titlePart = safeTitle.isEmpty ? videoInfo.videoId : safeTitle;
    final outputTemplate =
        '$outputDir/$titlePart [${videoInfo.videoId}].%(ext)s';

    try {
      _update(task.id, status: DownloadStatus.downloading);
      final result = await YtDlpRunner.download(
        url: task.url,
        formatId: format.formatId,
        outputPath: outputTemplate,
        onProgress: (p) => _updateProgress(task.id, p),
        shouldCancel: () => _cancelled.contains(task.id),
      );
      if (_cancelled.contains(task.id)) {
        _update(task.id, status: DownloadStatus.cancelled);
      } else {
        _update(task.id,
            status: DownloadStatus.completed, outputPath: result);
      }
    } on YtDlpException catch (e) {
      _update(task.id, status: DownloadStatus.failed, error: e.message);
    } catch (e) {
      _update(task.id, status: DownloadStatus.failed, error: e.toString());
    } finally {
      _cancelled.remove(task.id);
    }
  }

  /// 取消下载
  void cancel(String id) {
    _cancelled.add(id);
    final task = state.where((t) => t.id == id).firstOrNull;
    if (task != null && !task.isFinished) {
      _update(id, status: DownloadStatus.cancelled);
    }
  }

  /// 移除任务
  void remove(String id) {
    state = state.where((t) => t.id != id).toList();
  }

  /// 清空已结束的任务
  void clearFinished() {
    state = state.where((t) => !t.isFinished).toList();
  }

  void _update(
    String id, {
    DownloadStatus? status,
    String? outputPath,
    String? error,
  }) {
    state = [
      for (final t in state)
        if (t.id == id)
          t.copyWith(status: status, outputPath: outputPath, error: error)
        else
          t,
    ];
  }

  void _updateProgress(String id, DownloadProgress p) {
    final isMerging = p.stage == DownloadStage.merging;
    state = [
      for (final t in state)
        if (t.id == id)
          t.copyWith(
            status: isMerging ? DownloadStatus.merging : t.status,
            progress: p,
          )
        else
          t,
    ];
  }
}

final downloadListProvider =
    StateNotifierProvider<DownloadListNotifier, List<DownloadTask>>(
        (ref) => DownloadListNotifier());
