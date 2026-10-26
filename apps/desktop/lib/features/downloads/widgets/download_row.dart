import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/download_task.dart';
import '../../../shared/branding/app_brand.dart';
import '../../../shared/theme/design_tokens.dart';
import '../download_provider.dart';

/// 全宽下载行：缩略图 banner + 标题/状态/操作覆盖层。
///
/// 对应 Downie 主窗口的单条下载；没有独立详情面板。
class DownloadRow extends ConsumerWidget {
  final DownloadTask task;

  const DownloadRow({super.key, required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(downloadListProvider.notifier);
    final running = task.status == DownloadStatus.downloading ||
        task.status == DownloadStatus.merging;

    return SizedBox(
      height: 150,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _background(context),
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
                      onPressed: task.isRunning
                          ? () => notifier.cancel(task.id)
                          : () => notifier.remove(task.id),
                      tooltip: task.isRunning ? '取消下载' : '移除',
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
                    _formatPill(task),
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

  Widget _background(BuildContext context) {
    if (task.thumbnail.isNotEmpty) {
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

  Widget _formatPill(DownloadTask task) {
    final label = task.formatLabel.isEmpty
        ? (task.audioOnly ? 'AUDIO' : task.ext.toUpperCase())
        : task.formatLabel;
    return Container(
      constraints: const BoxConstraints(maxWidth: 120),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 10, color: Colors.white70),
      ),
    );
  }

  String _metaText(DownloadTask task) {
    final parts = <String>[
      if (task.extractor.isNotEmpty) task.extractor,
      if (task.formatLabel.isNotEmpty) task.formatLabel,
      if (task.fileSize > 0) _formatBytes(task.fileSize),
    ];
    return parts.join(' · ');
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
    }
  }

  Color _statusColor(DownloadTask task) {
    if (task.isFailed) return const Color(0xFFFF8A80);
    if (task.status == DownloadStatus.completed) return AppTokens.success;
    return Colors.white70;
  }

  Future<void> _openContainingFolder(String path) async {
    try {
      final dir = File(path).parent.path;
      await Process.run(
        Platform.isMacOS ? 'open' : 'explorer',
        [dir],
      );
    } catch (e) {
      debugPrint('[下载行] 打开目录失败: $e');
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(unit == 0 ? 0 : 1)}${units[unit]}';
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
