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
            // 状态图标
            _buildStatusIcon(theme, task),
            const SizedBox(width: 12),
            // 主体
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
                    '${task.extractor} · ${task.formatLabel}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (task.isRunning) _buildProgress(theme, task),
                  if (task.status == DownloadStatus.completed &&
                      task.outputPath != null)
                    _buildCompletedInfo(theme, task),
                  if (task.status == DownloadStatus.failed)
                    Text(
                      '失败：${task.error ?? '未知错误'}',
                      style: TextStyle(
                        color: theme.colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            // 操作按钮
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
          value: task.percentValue / 100,
          minHeight: 6,
          borderRadius: BorderRadius.circular(3),
        ),
        const SizedBox(height: 4),
        Text(
          '${task.statusText} · ${task.percentValue}%'
          '${p != null && p.speed > 0 ? ' · ${p.speedText}' : ''}'
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
        Icon(Icons.check_circle,
            size: 14, color: theme.colorScheme.primary),
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

  Widget _buildActions(
    ThemeData theme,
    WidgetRef ref,
    DownloadTask task,
  ) {
    if (task.isRunning) {
      return IconButton(
        icon: const Icon(Icons.stop_circle_outlined),
        tooltip: '取消下载',
        color: theme.colorScheme.error,
        onPressed: () =>
            ref.read(downloadListProvider.notifier).cancel(task.id),
      );
    }
    return IconButton(
      icon: const Icon(Icons.delete_outline),
      tooltip: '移除',
      onPressed: () =>
          ref.read(downloadListProvider.notifier).remove(task.id),
    );
  }

  Future<void> _openFile(String path) async {
    // macOS 用 open 打开文件所在位置
    if (Platform.isMacOS) {
      await Process.run('open', ['-R', path]);
    } else if (Platform.isWindows) {
      await Process.run('explorer', ['/select,', path]);
    }
  }
}
