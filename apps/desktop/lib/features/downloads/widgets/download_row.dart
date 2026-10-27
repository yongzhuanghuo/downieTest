import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/models/download_task.dart';
import '../../../data/models/format_option.dart';
import '../../../shared/branding/app_brand.dart';
import '../../../shared/theme/design_tokens.dart';
import '../../settings/settings_provider.dart';
import '../download_provider.dart';
import '../task_debug_dialog.dart';

/// 全宽下载行：缩略图 banner + 标题/状态/操作覆盖层。
///
/// 对应 Downie 主窗口的单条下载；没有独立详情面板。
class DownloadRow extends ConsumerWidget {
  final DownloadTask task;

  const DownloadRow({super.key, required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(downloadListProvider.notifier);
    final showThumbnails =
        ref.watch(settingsProvider.select((s) => s.showThumbnails));
    final running = task.status == DownloadStatus.downloading ||
        task.status == DownloadStatus.merging;

    return SizedBox(
      height: 132,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _background(context, showThumbnails),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xCC000000),
                  Color(0x22000000),
                  Color(0xE6000000),
                ],
                stops: [0, 0.42, 1],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            task.title.isEmpty ? '未命名视频' : task.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.rowTitle(Colors.white),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _metaText(task),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.rowMeta(Colors.white70),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: (task.isRunning || task.isPaused)
                          ? () => notifier.cancel(task.id)
                          : () => notifier.remove(task.id),
                      tooltip:
                          (task.isRunning || task.isPaused) ? '取消下载' : '移除',
                      icon: const Icon(Icons.close, size: 14),
                      color: Colors.white70,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints.tightFor(width: 24, height: 24),
                    ),
                  ],
                ),
                const Spacer(),
                Row(
                  children: [
                    Icon(
                      _statusIcon(task),
                      size: 14,
                      color: _statusColor(task),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        _statusLine(task),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: task.isFailed
                              ? const Color(0xFFFF8A80)
                              : Colors.white70,
                        ),
                      ),
                    ),
                    if (task.isPaused)
                      IconButton(
                        onPressed: () => notifier.resume(task.id),
                        tooltip: '继续下载',
                        icon: const Icon(Icons.play_arrow, size: 16),
                        color: Colors.white70,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 24,
                          height: 24,
                        ),
                      )
                    else if (task.isRunning)
                      IconButton(
                        onPressed: () => notifier.pause(task.id),
                        tooltip: '暂停下载',
                        icon: const Icon(Icons.pause, size: 14),
                        color: Colors.white70,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 24,
                          height: 24,
                        ),
                      ),
                    if (task.status == DownloadStatus.completed &&
                        task.outputPath != null)
                      TextButton(
                        onPressed: () => _openContainingFolder(task.outputPath!),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          minimumSize: const Size(0, 24),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('打开', style: TextStyle(fontSize: 11)),
                      ),
                    if (task.isFailed ||
                        task.status == DownloadStatus.cancelled)
                      IconButton(
                        onPressed: () => notifier.retry(task.id),
                        tooltip: '重试',
                        icon: const Icon(Icons.refresh, size: 14),
                        color: Colors.white70,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 24,
                          height: 24,
                        ),
                      ),
                    const SizedBox(width: 4),
                    _postprocessingMenu(notifier, task),
                    const SizedBox(width: 4),
                    _formatMenu(notifier, task),
                    const SizedBox(width: 4),
                    _taskMenu(context, notifier, task),
                  ],
                ),
              ],
            ),
          ),
          if (running)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: LinearProgressIndicator(
                value: task.status == DownloadStatus.merging
                    ? null
                    : task.percentValue / 100,
                minHeight: 2,
                backgroundColor: Colors.white12,
                color: AppTokens.accent,
              ),
            ),
        ],
      ),
    );
  }

  Widget _background(BuildContext context, bool showThumbnails) {
    if (showThumbnails && task.thumbnail.isNotEmpty) {
      return Image.network(
        task.thumbnail,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return _placeholder();
        },
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTokens.panelRaised, AppTokens.window],
        ),
      ),
      alignment: Alignment.center,
      child: Opacity(
        opacity: 0.16,
        child: Image.asset(AppBrand.logoAsset, width: 62, height: 62),
      ),
    );
  }

  Widget _postprocessingMenu(
    DownloadListNotifier notifier,
    DownloadTask task,
  ) {
    final enabled = task.status != DownloadStatus.completed;
    return PopupMenuButton<PostprocessingMode>(
      enabled: enabled,
      tooltip: '后处理',
      onSelected: (mode) => notifier.setPostprocessing(task.id, mode),
      itemBuilder: (context) => [
        for (final mode in PostprocessingMode.values)
          PopupMenuItem(value: mode, child: Text(mode.label)),
      ],
      child: _pill(task.postprocessing.label, chevron: enabled),
    );
  }

  Widget _formatMenu(
    DownloadListNotifier notifier,
    DownloadTask task,
  ) {
    final formats = task.availableFormats;
    final canChange = task.status == DownloadStatus.pending && formats.isNotEmpty;
    final label = task.formatLabel.isEmpty
        ? (task.audioOnly ? 'AUDIO' : task.ext.toUpperCase())
        : task.formatLabel;
    if (!canChange) return _pill(label);

    return PopupMenuButton<FormatOption>(
      tooltip: '画质',
      onSelected: (format) => notifier.setFormat(task.id, format),
      itemBuilder: (context) => [
        for (final format in formats)
          PopupMenuItem(
            value: format,
            child: Text(
              '${format.label}'
              '${format.fileSize == null ? '' : ' · ${format.fileSizeText}'}',
            ),
          ),
      ],
      child: _pill(label, chevron: true),
    );
  }

  Widget _pill(String label, {bool chevron = false}) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: Colors.white70),
            ),
          ),
          if (chevron) ...[
            const SizedBox(width: 2),
            const Icon(Icons.expand_more, size: 11, color: Colors.white54),
          ],
        ],
      ),
    );
  }

  Widget _taskMenu(
    BuildContext context,
    DownloadListNotifier notifier,
    DownloadTask task,
  ) {
    return SizedBox(
      width: 24,
      height: 24,
      child: PopupMenuButton<String>(
        tooltip: '操作',
        padding: EdgeInsets.zero,
        iconSize: 14,
        icon: const Icon(Icons.more_horiz, color: Colors.white70),
        onSelected: (value) async {
          switch (value) {
            case 'copy':
              await Clipboard.setData(ClipboardData(text: task.url));
              break;
            case 'copy-download':
              await Clipboard.setData(
                ClipboardData(text: _downloadUrl(task)),
              );
              break;
            case 'open-browser':
              try {
                await launchUrl(
                  Uri.parse(task.url),
                  mode: LaunchMode.externalApplication,
                );
              } catch (e) {
                debugPrint('[下载行] 打开浏览器失败: $e');
              }
              break;
            case 'preview':
              if (task.outputPath != null) {
                await _quickLook(task.outputPath!);
              }
              break;
            case 'report':
              await _reportLink(task);
              break;
            case 'debug':
              await TaskDebugDialog.show(context, task);
              break;
            case 'open':
              if (task.outputPath != null) {
                await _openContainingFolder(task.outputPath!);
              }
              break;
            case 'rename':
              await _rename(context, notifier, task);
              break;
            case 'priority:low':
              await notifier.setPriority(task.id, DownloadPriority.low);
              break;
            case 'priority:normal':
              await notifier.setPriority(task.id, DownloadPriority.normal);
              break;
            case 'priority:high':
              await notifier.setPriority(task.id, DownloadPriority.high);
              break;
            case 'throttle':
              await _pickThrottle(context, notifier, task);
              break;
            case 'subtitles':
              await notifier.setDownloadSubtitles(
                task.id,
                !task.downloadSubtitles,
              );
              break;
            case 'cover':
              await notifier.setDownloadCover(task.id, !task.downloadCover);
              break;
            case 'pause':
              await notifier.pause(task.id);
              break;
            case 'resume':
              await notifier.resume(task.id);
              break;
            case 'retry':
              await notifier.retry(task.id);
              break;
            case 'cancel':
              notifier.cancel(task.id);
              break;
            case 'remove':
              await notifier.remove(task.id);
              break;
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'copy', child: Text('复制页面链接')),
          const PopupMenuItem(
            value: 'copy-download',
            child: Text('复制下载链接'),
          ),
          const PopupMenuItem(
            value: 'open-browser',
            child: Text('在浏览器中打开'),
          ),
          const PopupMenuItem(value: 'rename', child: Text('重命名')),
          if (task.status == DownloadStatus.pending) ...[
            for (final priority in DownloadPriority.values)
              CheckedPopupMenuItem(
                value: 'priority:${priority.name}',
                checked: task.priority == priority,
                child: Text(priority.label),
              ),
          ],
          if (task.status == DownloadStatus.pending) ...[
            CheckedPopupMenuItem(
              value: 'subtitles',
              checked: task.downloadSubtitles,
              child: const Text('下载字幕'),
            ),
            CheckedPopupMenuItem(
              value: 'cover',
              checked: task.downloadCover,
              child: const Text('保存缩略图'),
            ),
            const PopupMenuItem(value: 'throttle', child: Text('限速…')),
          ],
          if (task.isPaused)
            const PopupMenuItem(value: 'resume', child: Text('继续下载'))
          else if (task.isRunning)
            const PopupMenuItem(value: 'pause', child: Text('暂停下载')),
          if (task.status == DownloadStatus.completed &&
              task.outputPath != null) ...[
            if (Platform.isMacOS)
              const PopupMenuItem(
                value: 'preview',
                child: Text('快速预览'),
              ),
            const PopupMenuItem(value: 'open', child: Text('打开所在目录')),
          ],
          if (task.isFailed || task.status == DownloadStatus.cancelled) ...[
            const PopupMenuItem(value: 'retry', child: Text('重试')),
            const PopupMenuItem(value: 'report', child: Text('报告链接…')),
          ],
          if (task.isRunning)
            const PopupMenuItem(value: 'cancel', child: Text('取消下载')),
          const PopupMenuDivider(),
          const PopupMenuItem(value: 'debug', child: Text('调试信息…')),
          if (task.isFinished)
            const PopupMenuItem(value: 'remove', child: Text('移除')),
        ],
      ),
    );
  }

  Future<void> _pickThrottle(
    BuildContext context,
    DownloadListNotifier notifier,
    DownloadTask task,
  ) async {
    const options = <int, String>{
      0: '不限速（使用全局设置）',
      500: '500 KB/s',
      1000: '1 MB/s',
      2000: '2 MB/s',
      5000: '5 MB/s',
    };
    final value = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('本任务限速'),
        children: [
          for (final entry in options.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(entry.key),
              child: Row(
                children: [
                  Icon(
                    task.throttleKbps == entry.key
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(entry.value),
                ],
              ),
            ),
        ],
      ),
    );
    if (value != null) {
      await notifier.setThrottle(task.id, value);
    }
  }

  String _downloadUrl(DownloadTask task) {
    final id = task.formatId.trim();
    if (id.contains('\n')) return id.split('\n').first;
    if (id.startsWith('{')) {
      try {
        final map = jsonDecode(id);
        if (map is Map && map['url'] is String) {
          return map['url'] as String;
        }
      } catch (_) {}
    }
    if (id.startsWith('http://') || id.startsWith('https://')) return id;
    return task.url;
  }

  Future<void> _quickLook(String path) async {
    if (!Platform.isMacOS) return;
    try {
      await Process.start(
        'qlmanage',
        ['-p', path],
        mode: ProcessStartMode.detached,
      );
    } catch (e) {
      debugPrint('[下载行] Quick Look 失败: $e');
    }
  }

  Future<void> _reportLink(DownloadTask task) async {
    final uri = Uri(
      scheme: 'mailto',
      path: AppBrand.supportEmail,
      queryParameters: {
        'subject': '下载失败：${task.title}',
        'body': '链接：${task.url}\n'
            '站点：${task.extractor}\n'
            '错误：${task.error ?? '无'}\n'
            '格式：${task.formatLabel}\n',
      },
    );
    try {
      await launchUrl(uri);
    } catch (e) {
      debugPrint('[下载行] 打开邮件失败: $e');
    }
  }

  Future<void> _rename(
    BuildContext context,
    DownloadListNotifier notifier,
    DownloadTask task,
  ) async {
    final controller = TextEditingController(text: task.title);
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(fontSize: 13),
          onSubmitted: (text) => Navigator.of(ctx).pop(text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null && value.trim().isNotEmpty) {
      await notifier.rename(task.id, value);
    }
  }

  String _metaText(DownloadTask task) {
    final host = Uri.tryParse(task.url)?.host ?? '';
    final site = host.isNotEmpty ? host : task.extractor;
    final parts = <String>[
      if (task.priority != DownloadPriority.normal) task.priority.label,
      if (task.throttleKbps > 0)
        '限速 ${task.throttleKbps >= 1000 ? '${(task.throttleKbps / 1000).toStringAsFixed(1)} MB/s' : '${task.throttleKbps} KB/s'}',
      if (site.isNotEmpty) site,
      if (task.formatLabel.isNotEmpty) task.formatLabel,
      if (task.duration > 0) _formatDuration(task.duration),
    ];
    return parts.join(' - ');
  }

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:'
          '${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String _statusLine(DownloadTask task) {
    final p = task.progress;
    switch (task.status) {
      case DownloadStatus.pending:
        return '等待中';
      case DownloadStatus.downloading:
        final parts = <String>[
          '${task.percentValue}%',
          if (task.speed > 0) _formatSpeed(task.speed),
          if (p?.eta != null) '剩余 ${p!.etaText}',
        ];
        return parts.join(' · ');
      case DownloadStatus.merging:
        return '合并中 · ${task.percentValue}%';
      case DownloadStatus.completed:
        return '已完成';
      case DownloadStatus.failed:
        return task.error == null || task.error!.isEmpty
            ? '下载失败'
            : '失败：${task.error}';
      case DownloadStatus.cancelled:
        return '已取消';
      case DownloadStatus.paused:
        final percent = task.percentValue;
        return percent > 0 ? '已暂停 · $percent%' : '已暂停';
    }
  }

  IconData _statusIcon(DownloadTask task) {
    switch (task.status) {
      case DownloadStatus.pending:
        return Icons.schedule;
      case DownloadStatus.downloading:
      case DownloadStatus.merging:
        return Icons.downloading;
      case DownloadStatus.completed:
        return Icons.check_circle;
      case DownloadStatus.failed:
        return Icons.error_outline;
      case DownloadStatus.cancelled:
        return Icons.cancel_outlined;
      case DownloadStatus.paused:
        return Icons.pause_circle_outline;
    }
  }

  Color _statusColor(DownloadTask task) {
    if (task.isFailed) return const Color(0xFFFF8A80);
    if (task.status == DownloadStatus.completed) return AppTokens.success;
    return Colors.white70;
  }

  Future<void> _openContainingFolder(String path) async {
    try {
      if (Platform.isMacOS) {
        await Process.run('open', ['-R', path]);
      } else if (Platform.isWindows) {
        await Process.run(
          'explorer',
          ['/select,${path.replaceAll('/', '\\')}'],
        );
      }
    } catch (e) {
      debugPrint('[下载行] 打开目录失败: $e');
    }
  }

  String _formatSpeed(int bps) {
    if (bps <= 0) return '';
    const units = ['B/s', 'KB/s', 'MB/s', 'GB/s'];
    double value = bps.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(unit == 0 ? 0 : 1)}${units[unit]}';
  }
}
