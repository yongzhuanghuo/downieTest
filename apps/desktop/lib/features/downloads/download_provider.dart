import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/engine/ytdlp_runner.dart';
import '../../core/ffmpeg/ffmpeg_runner.dart';
import '../../core/platform/notifications.dart';
import '../../core/sites/plugin_registry.dart';
import '../../core/sites/site_plugin.dart';
import '../../core/storage/downloads_dao.dart';
import '../../core/storage/file_naming.dart';
import '../../core/storage/settings_storage.dart';
import '../../data/models/download_progress.dart';
import '../../data/models/download_task.dart';
import '../../data/models/format_option.dart';
import '../../data/models/video_info.dart';
import '../history/history_page.dart';
import 'site_login_prompt.dart';

/// 失败自动重试最大次数
const int _kMaxRetry = 3;

/// 重试基础退避毫秒（1s / 2s / 4s）
const int _kRetryBaseMs = 1000;

/// 下载列表 Notifier
///
/// 管理所有下载任务的生命周期：
/// - 并发队列（数量从设置读取，默认 3，多余等待）
/// - 失败自动重试（最多 3 次，指数退避）
/// - SQLite 持久化（所有状态字段实时写库）
/// - 断点续传（yt-dlp --continue + 应用重启恢复 pending 任务）
class DownloadListNotifier extends StateNotifier<List<DownloadTask>> {
  DownloadListNotifier(this._ref) : super(const []) {
    _init();
  }

  final Ref _ref;
  final DownloadsDao _dao = DownloadsDao.instance;
  final Set<String> _cancelled = {};
  final Set<String> _paused = {};
  final Set<String> _activeIds = {}; // 正在执行中的任务 ID（避免并发重复启动）
  bool _initialized = false;

  /// 当前并发上限（实时从设置读取）
  int get _maxConcurrent =>
      SettingsStorage.instance.current.maxConcurrent;

  // ==================== 初始化（加载DB + 恢复未完成任务） ====================

  Future<void> _init() async {
    if (_initialized) return;
    _initialized = true;

    // 1. 按设置清理过期历史（只删记录，不删文件）
    final historyDays = SettingsStorage.instance.current.historyDays;
    if (historyDays > 0) {
      final removed = await _dao.deleteHistoryBefore(
        DateTime.now().subtract(Duration(days: historyDays)),
      );
      if (removed > 0) {
        debugPrint('[DownloadList] 清理过期历史 $removed 条');
      }
    }

    // 2. 从 DB 读取所有任务（先恢复 UI）
    final all = await _dao.findAll();
    if (all.isNotEmpty) {
      state = List<DownloadTask>.unmodifiable(all);
      debugPrint('[DownloadList] 从DB恢复 ${all.length} 条任务');
    }

    // 3. 之前的 downloading / merging → 重置为 pending（已下载字节可能有 .part 供续传）
    final needResets = <DownloadTask>[];
    for (final t in all) {
      if (t.status == DownloadStatus.downloading ||
          t.status == DownloadStatus.merging) {
        final reset = t.copyWith(
          status: DownloadStatus.pending,
          error: '上次异常退出，等待重试',
          speed: 0,
        );
        needResets.add(reset);
      }
    }
    if (needResets.isNotEmpty) {
      await _dao.upsertAll(needResets);
      state = [
        for (final t in state)
          needResets.where((r) => r.id == t.id).firstOrNull ?? t,
      ];
      debugPrint('[DownloadList] 恢复 ${needResets.length} 条中断任务为 pending');
    }

    // 4. 启动调度器（先把现在的 pending 跑起来）
    unawaited(_scheduler());
  }

  // ==================== 调度器：队列 → 执行 ====================

  /// 持续维持最多 _kMaxConcurrent 个下载
  ///
  /// 每次状态变更后触发，按 pending 先进先出启动。
  Future<void> _scheduler() async {
    if (mounted) {
      final pending = state
          .where((t) => t.isPending)
          .toList()
        ..sort((a, b) {
          final byPriority = b.priority.index.compareTo(a.priority.index);
          return byPriority != 0
              ? byPriority
              : a.createdAt.compareTo(b.createdAt);
        });

      final available = _maxConcurrent - _activeIds.length;
      if (available > 0 && pending.isNotEmpty) {
        final toStart = pending.take(available);
        for (final t in toStart) {
          unawaited(_executeTask(t));
        }
      }
    }
  }

  // ==================== 添加任务 ====================

  /// 添加并（有坑位时立刻/否则等待）下载
  Future<void> startDownload({
    required VideoInfo videoInfo,
    required FormatOption format,
    bool downloadSubtitles = false,
    bool downloadCover = false,
  }) async {
    final task = DownloadTask(
      id: const Uuid().v4(),
      url: videoInfo.url,
      title: videoInfo.title,
      duration: videoInfo.duration,
      thumbnail: videoInfo.thumbnail,
      extractor: videoInfo.extractor,
      formatId: format.formatId,
      formatLabel: format.label,
      availableFormats: videoInfo.formats,
      height: format.height,
      ext: format.ext,
      fileSize: format.fileSize ?? 0,
      audioOnly: format.audioOnly,
      downloadSubtitles: downloadSubtitles,
      downloadCover: downloadCover,
      postprocessing: _defaultPostprocessing(),
      createdAt: DateTime.now(),
    );

    // 立即写入 DB + 内存
    await _dao.upsert(task);
    state = [task, ...state];

    // 触发调度器
    unawaited(_scheduler());
  }

  PostprocessingMode _defaultPostprocessing() {
    switch (SettingsStorage.instance.current.defaultPostprocessing) {
      case 1:
        return PostprocessingMode.mp4;
      case 2:
        return PostprocessingMode.audio;
      default:
        return PostprocessingMode.none;
    }
  }

  /// 等待中的任务是否下载字幕
  Future<void> setDownloadSubtitles(String id, bool value) async {
    final task = _find(id);
    if (task == null || task.status != DownloadStatus.pending) return;
    await _apply(id, (t) => t.copyWith(downloadSubtitles: value));
  }

  /// 等待中的任务是否保存缩略图
  Future<void> setDownloadCover(String id, bool value) async {
    final task = _find(id);
    if (task == null || task.status != DownloadStatus.pending) return;
    await _apply(id, (t) => t.copyWith(downloadCover: value));
  }

  /// 修改下载完成后的处理方式（下载中也可改，完成时读取最新值）
  Future<void> setPostprocessing(String id, PostprocessingMode mode) async {
    final task = _find(id);
    if (task == null || task.status == DownloadStatus.completed) return;
    await _apply(id, (t) => t.copyWith(postprocessing: mode));
  }

  /// 调整等待中任务的队列优先级
  Future<void> setPriority(String id, DownloadPriority priority) async {
    final task = _find(id);
    if (task == null || task.status != DownloadStatus.pending) return;
    await _apply(id, (t) => t.copyWith(priority: priority));
    unawaited(_scheduler());
  }

  /// 重命名任务标题
  Future<void> rename(String id, String title) async {
    final value = title.trim();
    if (value.isEmpty) return;
    await _apply(id, (t) => t.copyWith(title: value));
  }

  /// 在任务开始前切换画质/格式
  Future<void> setFormat(String id, FormatOption format) async {
    final task = _find(id);
    if (task == null || task.status != DownloadStatus.pending) return;
    await _apply(
      id,
      (t) => t.copyWith(
        formatId: format.formatId,
        formatLabel: format.label,
        height: format.height,
        ext: format.ext,
        audioOnly: format.audioOnly,
        fileSize: format.fileSize ?? t.fileSize,
      ),
    );
  }

  // ==================== 执行单个任务（含重试/续传/取消） ====================

  Future<void> _executeTask(DownloadTask task) async {
    if (_activeIds.contains(task.id) || _cancelled.contains(task.id)) return;
    _activeIds.add(task.id);

    try {
      // 确定输出目录（从设置读取，空则用系统默认 Downloads）
      final settings = SettingsStorage.instance.current;
      final outputDir = await settings.resolveDownloadDir();
      await Directory(outputDir).create(recursive: true);
      var targetDir = outputDir;
      if (settings.subfolderBySite) {
        final site = sanitizePathSegment(task.extractor);
        targetDir = '$outputDir/${site.isEmpty ? 'Other' : site}';
        await Directory(targetDir).create(recursive: true);
      }
      final baseName = renderFilenameTemplate(
        settings.filenameTemplate,
        title: task.title,
        extractor: task.extractor,
        url: task.url,
      );
      final outputTemplate = '$targetDir/$baseName.${task.ext}';

      // 重试循环（yt-dlp 已内置 --continue，.part 自动续传）
      int attempt = task.retryCount;
      while (attempt < _kMaxRetry) {
        // 用户取消？
        if (_cancelled.contains(task.id)) {
          await _markStopped(task.id);
          return;
        }

        // 更新状态：下载中 + 重试次数
        await _apply(task.id, (t) => t.copyWith(
              status: DownloadStatus.downloading,
              retryCount: attempt,
              startedAt: t.startedAt ?? DateTime.now(),
              error: null,
            ));

        try {
          final String result;
          // 播放列表条目统一用 yt-dlp 的最佳流选择器，避免误走站点插件
          final plugin = task.formatId == 'bv*+ba/b'
              ? null
              : PluginRegistry.instance.byId(task.extractor);
          if (plugin != null) {
            // 站点插件：formatId 由插件解释（抖音是直链，HLS/DASH 可以是清单）
            result = await plugin.download(PluginDownloadRequest(
              task: task,
              outputPath: outputTemplate,
              onProgress: (p) => _applyProgress(task.id, p),
              shouldCancel: () => _cancelled.contains(task.id),
            ));
          } else {
            result = await YtDlpRunner.download(
              url: task.url,
              formatId: task.formatId,
              outputPath: outputTemplate,
              onProgress: (p) => _applyProgress(task.id, p),
              shouldCancel: () => _cancelled.contains(task.id),
              audioOnly: task.audioOnly,
              downloadSubtitles: task.downloadSubtitles,
              downloadCover: task.downloadCover,
            );
          }
          if (_cancelled.contains(task.id)) {
            await _markStopped(task.id);
            return;
          }
          // 成功：按最新选择执行后处理
          final current = _find(task.id) ?? task;
          final resultPath =
              await _applyPostprocessing(task.id, current, result);
          if (_cancelled.contains(task.id)) {
            await _markStopped(task.id);
            return;
          }
          var finalSize = 0;
          try {
            finalSize = await File(resultPath).length();
          } catch (_) {}
          await _apply(task.id, (t) => t.copyWith(
                status: DownloadStatus.completed,
                outputPath: resultPath,
                fileSize: finalSize > 0 ? finalSize : t.fileSize,
                completedAt: DateTime.now(),
                speed: 0,
                progress: const DownloadProgress(
                  downloadedBytes: 0,
                  speed: 0,
                  stage: DownloadStage.downloading,
                ),
              ));
          unawaited(SystemNotifications.downloadComplete(current.title));
          // 下载完成自动打开文件夹（按设置）
          if (SettingsStorage.instance.current.autoOpenFolder) {
            unawaited(_revealFile(resultPath));
          }
          return;
        } on SitePluginException catch (e) {
          // 用户暂停/取消：插件抛出异常时按暂停或已取消处理
          if (_cancelled.contains(task.id)) {
            await _markStopped(task.id);
            return;
          }
          // 需要登录：直接弹登录浏览器；登录成功后自动重试
          if (e.requiresLogin) {
            await _apply(task.id, (t) => t.copyWith(
                  status: DownloadStatus.failed,
                  error: '需要登录才能下载：${e.message}',
                  retryCount: attempt,
                  speed: 0,
                ));
            final loggedIn = await promptSiteLogin(task.url);
            if (loggedIn) await retry(task.id);
            return;
          }
          // 不可重试（如抖音直链签名失效）
          if (!e.retryable) {
            await _apply(task.id, (t) => t.copyWith(
                  status: DownloadStatus.failed,
                  error: e.message,
                  retryCount: attempt,
                  speed: 0,
                ));
            return;
          }
          // 可重试：与 yt-dlp 相同的指数退避
          attempt++;
          if (attempt >= _kMaxRetry || _cancelled.contains(task.id)) {
            await _apply(task.id, (t) => t.copyWith(
                  status: DownloadStatus.failed,
                  error: '重试${attempt}次均失败: ${e.message}',
                  retryCount: attempt,
                  speed: 0,
                ));
            return;
          }
          final delay = Duration(milliseconds: _kRetryBaseMs * (1 << (attempt - 1)));
          debugPrint('[DownloadList] ${task.id} 第${attempt}次失败，${delay.inMilliseconds}ms后重试: ${e.message}');
          await _apply(task.id, (t) => t.copyWith(
                status: DownloadStatus.pending,
                error: '第${attempt}次失败，${delay.inSeconds}s后重试...',
                retryCount: attempt,
                speed: 0,
              ));
          await Future.delayed(delay);
          if (_cancelled.contains(task.id)) {
            await _markStopped(task.id);
            return;
          }
        } on YtDlpException catch (e) {
          if (_cancelled.contains(task.id)) {
            await _markStopped(task.id);
            return;
          }
          // 需要登录/cookie：不重试，直接提示登录对应站点
          if (isCookieError(e.message)) {
            await _apply(task.id, (t) => t.copyWith(
                  status: DownloadStatus.failed,
                  error: '需要登录才能下载：${e.message}',
                  retryCount: attempt,
                  speed: 0,
                ));
            final loggedIn = await promptSiteLogin(task.url);
            if (loggedIn) await retry(task.id);
            return;
          }
          attempt++;
          if (attempt >= _kMaxRetry || _cancelled.contains(task.id)) {
            await _apply(task.id, (t) => t.copyWith(
                  status: DownloadStatus.failed,
                  error: '重试${attempt}次均失败: ${e.message}',
                  retryCount: attempt,
                  speed: 0,
                ));
            return;
          }
          // 退避等待
          final delay = Duration(milliseconds: _kRetryBaseMs * (1 << (attempt - 1)));
          debugPrint('[DownloadList] ${task.id} 第${attempt}次失败，${delay.inMilliseconds}ms后重试: ${e.message}');
          await _apply(task.id, (t) => t.copyWith(
                status: DownloadStatus.pending,
                error: '第${attempt}次失败，${delay.inSeconds}s后重试...',
                retryCount: attempt,
                speed: 0,
              ));
          await Future.delayed(delay);
          if (_cancelled.contains(task.id)) {
            await _markStopped(task.id);
            return;
          }
        } catch (e) {
          if (_cancelled.contains(task.id)) {
            await _markStopped(task.id);
            return;
          }
          await _apply(task.id, (t) => t.copyWith(
                status: DownloadStatus.failed,
                error: e.toString(),
                speed: 0,
              ));
          return;
        }
      }
    } finally {
      _activeIds.remove(task.id);
      _cancelled.remove(task.id);
      // 调度器继续填坑
      unawaited(_scheduler());
    }
  }

  // ==================== 取消 / 重试 / 删除 ====================

  /// 暂停下载。
  ///
  /// 正在跑的任务通过取消检查器终止子进程，已下载的 .part 保留，
  /// 继续时 yt-dlp 会从断点续传。等待中的任务直接挂起。
  Future<void> pause(String id) async {
    final t = _find(id);
    if (t == null || t.isFinished || t.isPaused) return;
    _paused.add(id);
    _cancelled.add(id);
    if (t.status == DownloadStatus.pending) {
      await _apply(id, (x) => x.copyWith(
            status: DownloadStatus.paused,
            speed: 0,
          ));
      return;
    }
    await _apply(id, (x) => x.copyWith(
          status: DownloadStatus.paused,
          speed: 0,
        ));
  }

  /// 继续已暂停的任务
  Future<void> resume(String id) async {
    final t = _find(id);
    if (t == null || !t.isPaused) return;
    _paused.remove(id);
    _cancelled.remove(id);
    await _apply(id, (x) => x.copyWith(
          status: DownloadStatus.pending,
          speed: 0,
          error: null,
          completedAt: null,
        ));
    unawaited(_scheduler());
  }

  /// 取消下载
  void cancel(String id) {
    _paused.remove(id);
    _cancelled.add(id);
    final t = _find(id);
    if (t != null && !t.isFinished) {
      unawaited(_apply(id, (x) => x.copyWith(
            status: DownloadStatus.cancelled,
            speed: 0,
          )));
    }
  }

  /// 手动重试失败/取消的任务（重置为 pending）
  Future<void> retry(String id) async {
    final t = _find(id);
    if (t == null) return;
    if (!t.isFailed && t.status != DownloadStatus.cancelled) return;
    _paused.remove(id);
    _cancelled.remove(id);
    await _apply(id, (x) => x.copyWith(
          status: DownloadStatus.pending,
          retryCount: 0,
          error: null,
          speed: 0,
          downloadedBytes: 0,
          progress: null,
          startedAt: null,
          completedAt: null,
        ));
    unawaited(_scheduler());
  }

  /// 删除任务（内存 + DB）
  Future<void> remove(String id) async {
    _cancelled.add(id);
    _paused.remove(id);
    await _dao.deleteById(id);
    state = state.where((t) => t.id != id).toList();
    _ref.invalidate(historyProvider);
  }

  /// 清空已结束任务
  Future<void> clearFinished() async {
    await _dao.deleteFinished();
    state = state.where((t) => !t.isFinished).toList();
    _ref.invalidate(historyProvider);
  }

  // ==================== 内部工具方法 ====================

  /// 在文件管理器中显示文件（macOS=Finder, Windows=资源管理器）
  Future<void> _revealFile(String path) async {
    try {
      if (Platform.isMacOS) {
        await Process.run('open', ['-R', path]);
      } else if (Platform.isWindows) {
        await Process.run('explorer', ['/select,${path.replaceAll('/', '\\')}']);
      }
    } catch (e) {
      debugPrint('[DownloadList] 打开文件夹失败: $e');
    }
  }

  DownloadTask? _find(String id) {
    for (final t in state) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// 统一变更方法：内存 + DB 同步更新
  Future<void> _apply(String id, DownloadTask Function(DownloadTask) fn) async {
    final before = _find(id);
    if (before == null) return;
    final after = fn(before);
    state = [for (final t in state) if (t.id == id) after else t];
    await _dao.updateProgress(after);
  }

  Future<void> _applyProgress(String id, DownloadProgress p) async {
    if (_paused.contains(id) || _cancelled.contains(id)) return;
    final isMerging = p.stage == DownloadStage.merging;
    await _apply(id, (t) => t.copyWith(
          status: isMerging ? DownloadStatus.merging : DownloadStatus.downloading,
          progress: p,
          downloadedBytes: p.downloadedBytes,
          speed: p.speed.toInt(),
          fileSize: (p.totalBytes ?? 0) > 0 ? (p.totalBytes ?? 0) : t.fileSize,
        ));
  }

  /// 下载被取消检查器终止后，根据是否暂停决定落成暂停还是取消。
  Future<void> _markStopped(String id) async {
    if (_paused.contains(id)) {
      await _apply(id, (t) => t.copyWith(
            status: DownloadStatus.paused,
            speed: 0,
          ));
      return;
    }
    await _finishStatus(id, DownloadStatus.cancelled);
  }

  Future<void> _finishStatus(String id, DownloadStatus s) async {
    await _apply(id, (t) => t.copyWith(
          status: s,
          speed: 0,
          completedAt: s == DownloadStatus.cancelled ? DateTime.now() : null,
        ));
  }

  Future<String> _applyPostprocessing(
    String id,
    DownloadTask task,
    String inputPath,
  ) async {
    if (task.postprocessing == PostprocessingMode.none) return inputPath;
    final ext = _extensionOf(inputPath);

    if (task.postprocessing == PostprocessingMode.audio) {
      if (ext == 'mp3' || ext == 'm4a') return inputPath;
      final output = _replaceExtension(inputPath, 'mp3');
      await _apply(id, (t) => t.copyWith(
            status: DownloadStatus.merging,
            progress: const DownloadProgress(
              downloadedBytes: 0,
              speed: 0,
              stage: DownloadStage.postProcessing,
              detail: '转换为 MP3',
            ),
          ));
      final converted = await FFmpegRunner.convertToMp3(
        inputPath: inputPath,
        outputPath: output,
      );
      await _apply(id, (t) => t.copyWith(
            ext: 'mp3',
            formatLabel: 'MP3',
            audioOnly: true,
          ));
      return converted;
    }

    if (ext == 'mp4') return inputPath;
    final output = _replaceExtension(inputPath, 'mp4');
    await _apply(id, (t) => t.copyWith(
          status: DownloadStatus.merging,
          progress: const DownloadProgress(
            downloadedBytes: 0,
            speed: 0,
            stage: DownloadStage.postProcessing,
            detail: '转换为 MP4',
          ),
        ));
    final converted = await FFmpegRunner.convertToMp4(
      inputPath: inputPath,
      outputPath: output,
    );
    await _apply(id, (t) => t.copyWith(
          ext: 'mp4',
          formatLabel: 'MP4',
          audioOnly: false,
        ));
    return converted;
  }

  String _extensionOf(String path) {
    final slash = path.lastIndexOf(RegExp(r'[\\/]'));
    final dot = path.lastIndexOf('.');
    if (dot <= slash) return '';
    return path.substring(dot + 1).toLowerCase();
  }

  String _replaceExtension(String path, String ext) {
    final slash = path.lastIndexOf(RegExp(r'[\\/]'));
    final dot = path.lastIndexOf('.');
    if (dot <= slash) return '$path.$ext';
    return '${path.substring(0, dot)}.$ext';
  }
}

final downloadListProvider =
    StateNotifierProvider<DownloadListNotifier, List<DownloadTask>>(
        (ref) => DownloadListNotifier(ref));

/// 只返回正在进行中的任务（用于展示角标数字）
final pendingCountProvider = Provider<int>((ref) {
  return ref.watch(downloadListProvider).where((t) => t.isRunning).length;
});

/// 主队列搜索关键词（空 = 显示全部）
final downloadSearchProvider = StateProvider<String>((ref) => '');
