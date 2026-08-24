import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/download_task.dart';
import 'download_provider.dart';

/// 下载页 - 下载队列 + 进度
class DownloadsPage extends ConsumerWidget {
  const DownloadsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tasks = ref.watch(downloadListProvider);
    final hasFinished = tasks.any((t) => t.isFinished);

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('下载队列', style: theme.textTheme.headlineSmall),
                      const SizedBox(height: 4),
                      Text(
                        '进行中和已完成的下载任务',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (hasFinished)
                  TextButton.icon(
                    onPressed: () => ref
                        .read(downloadListProvider.notifier)
                        .clearFinished(),
                    icon: const Icon(Icons.cleaning_services),
                    label: const Text('清空已结束'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: tasks.isEmpty
                  ? _buildEmpty(theme)
                  : ListView.separated(
                      itemCount: tasks.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, i) =>
                          _buildTaskCard(theme, ref, tasks[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.download_done,
            size: 64,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            '暂无下载任务',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '在首页粘贴链接开始下载',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskCard(
    ThemeData theme,
    WidgetRef ref,
    DownloadTask task,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusIcon(theme, task),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${task.extractor} · ${task.formatLabel}'
                    '${task.fileSize > 0 ? ' · ${_formatBytes(task.fileSize)}' : ''}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (task.isRunning) _buildProgress(theme, task),
                  if (task.status == DownloadStatus.completed &&
                      task.outputPath != null)
                    _buildCompletedInfo(theme, task),
                  if (task.status == DownloadStatus.failed ||
                      task.status == DownloadStatus.cancelled)
                    _buildErrorInfo(theme, task),
                ],
              ),
            ),
            _buildActions(theme, ref, task),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon(ThemeData theme, DownloadTask task) {
    IconData icon;
    Color color;
    switch (task.status) {
      case DownloadStatus.pending:
        icon = Icons.schedule;
        color = theme.colorScheme.onSurfaceVariant;
        break;
      case DownloadStatus.downloading:
      case DownloadStatus.merging:
        icon = Icons.downloading;
        color = theme.colorScheme.primary;
        break;
      case DownloadStatus.completed:
        icon = Icons.check_circle;
        color = theme.colorScheme.primary;
        break;
      case DownloadStatus.failed:
        icon = Icons.error;
        color = theme.colorScheme.error;
        break;
      case DownloadStatus.cancelled:
        icon = Icons.cancel;
        color = theme.colorScheme.onSurfaceVariant;
        break;
    }
    return Icon(icon, color: color);
  }

  Widget _buildProgress(ThemeData theme, DownloadTask task) {
    final p = task.progress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(
          value: task.status == DownloadStatus.merging
              ? null
              : task.percentValue / 100,
          minHeight: 6,
          borderRadius: BorderRadius.circular(3),
        ),
        const SizedBox(height: 4),
        Text(
          '${task.statusText} · ${task.percentValue}%'
          '${task.speed > 0 ? ' · ${_formatSpeed(task.speed)}' : ''}'
          '${p != null && p.eta != null ? ' · 剩余 ${p.etaText}' : ''}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildCompletedInfo(ThemeData theme, DownloadTask task) {
    return Row(
      children: [
        Icon(Icons.check_circle, size: 14, color: theme.colorScheme.primary),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            '已保存到下载目录',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        TextButton.icon(
          onPressed: () => _openFile(task.outputPath!),
          icon: const Icon(Icons.folder_open, size: 16),
          label: const Text('打开', style: TextStyle(fontSize: 12)),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    );
  }

  Widget _buildErrorInfo(ThemeData theme, DownloadTask task) {
    final msg = task.error ??
        (task.status == DownloadStatus.cancelled ? '已取消' : '未知错误');
    return Text(
      '${task.statusText}：$msg',
      style: TextStyle(
        color: task.isFailed
            ? theme.colorScheme.error
            : theme.colorScheme.onSurfaceVariant,
        fontSize: 12,
      ),
    );
  }

  Widget _buildActions(
    ThemeData theme,
    WidgetRef ref,
    DownloadTask task,
  ) {
    final notifier = ref.read(downloadListProvider.notifier);

    if (task.isRunning) {
      return IconButton(
        icon: const Icon(Icons.stop_circle_outlined),
        tooltip: '取消下载',
        color: theme.colorScheme.error,
        onPressed: () => notifier.cancel(task.id),
      );
    }

    // 已结束：显示重试 + 删除
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (task.isFailed || task.status == DownloadStatus.cancelled)
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重试',
            color: theme.colorScheme.primary,
            onPressed: () => notifier.retry(task.id),
          ),
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: '移除',
          onPressed: () => notifier.remove(task.id),
        ),
      ],
    );
  }

  // ==================== 工具方法 ====================

  Future<void> _openFile(String path) async {
    // 打开文件所在目录（不选中文件，避免 explorer /select 路径解析问题）
    final dir = File(path).parent.path;
    try {
      if (Platform.isMacOS) {
        await Process.run('open', [dir]);
      } else if (Platform.isWindows) {
        await Process.run('explorer', [dir]);
      }
    } catch (e) {
      debugPrint('[打开目录] 失败: $e');
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double v = bytes.toDouble();
    int i = 0;
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    return '${v.toStringAsFixed(i == 0 ? 0 : 1)}${units[i]}';
  }

  String _formatSpeed(int bps) {
    if (bps <= 0) return '';
    const units = ['B/s', 'KB/s', 'MB/s', 'GB/s'];
    double v = bps.toDouble();
    int i = 0;
    while (v >= 1024 && i < units.length - 1) {
      v /= 1024;
      i++;
    }
    return '${v.toStringAsFixed(i == 0 ? 0 : 1)}${units[i]}';
  }
}
