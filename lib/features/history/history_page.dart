import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/downloads_dao.dart';
import '../../data/models/download_task.dart';

/// 历史记录 Provider
///
/// 从 SQLite 读取已完成的下载任务，带刷新方法。
final historyProvider =
    AsyncNotifierProvider<HistoryNotifier, List<DownloadTask>>(
        HistoryNotifier.new);

class HistoryNotifier extends AsyncNotifier<List<DownloadTask>> {
  final DownloadsDao _dao = DownloadsDao.instance;

  @override
  Future<List<DownloadTask>> build() async {
    return _dao.findHistory(limit: 500);
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _dao.findHistory(limit: 500));
  }

  /// 从历史中删除
  Future<void> delete(String id) async {
    await _dao.deleteById(id);
    await refresh();
  }

  /// 清空全部历史
  Future<void> clearAll() async {
    final list = await _dao.findHistory();
    for (final t in list) {
      await _dao.deleteById(t.id);
    }
    await refresh();
  }
}

/// 历史记录页
class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final history = ref.watch(historyProvider);

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
                      Text('历史记录', style: theme.textTheme.headlineSmall),
                      const SizedBox(height: 4),
                      Text(
                        '查看所有已完成的下载记录',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                history.when(
                  data: (list) => list.isEmpty
                      ? const SizedBox.shrink()
                      : TextButton.icon(
                          onPressed: () => _confirmClear(context, ref),
                          icon: const Icon(Icons.delete_sweep_outlined),
                          label: const Text('清空历史'),
                        ),
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => ref.read(historyProvider.notifier).refresh(),
                  tooltip: '刷新',
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: history.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.red),
                      const SizedBox(height: 8),
                      Text('加载失败: $e'),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: () =>
                            ref.read(historyProvider.notifier).refresh(),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
                data: (list) => list.isEmpty
                    ? _buildEmpty(theme)
                    : ListView.separated(
                        itemCount: list.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 10),
                        itemBuilder: (_, i) =>
                            _buildItem(context, theme, ref, list[i]),
                      ),
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
            Icons.history,
            size: 64,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            '暂无历史记录',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '已完成的下载会显示在这里',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(
    BuildContext context,
    ThemeData theme,
    WidgetRef ref,
    DownloadTask t,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              Icons.check_circle,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${t.extractor} · ${t.formatLabel}'
                    '${t.fileSize > 0 ? ' · ${_formatBytes(t.fileSize)}' : ''}'
                    ' · ${_formatDate(t.completedAt ?? t.createdAt)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            // 操作
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (t.outputPath != null && File(t.outputPath!).existsSync())
                  IconButton(
                    icon: const Icon(Icons.folder_open),
                    tooltip: '打开文件',
                    onPressed: () => _openFile(t.outputPath!),
                  ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: '从历史中删除',
                  onPressed: () =>
                      ref.read(historyProvider.notifier).delete(t.id),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空历史记录'),
        content: const Text('确认清空全部历史记录？已下载的文件不会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确认清空'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(historyProvider.notifier).clearAll();
    }
  }

  Future<void> _openFile(String path) async {
    if (Platform.isMacOS) {
      await Process.run('open', ['-R', path]);
    } else if (Platform.isWindows) {
      await Process.run('explorer', ['/select,', path]);
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

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(day).inDays;
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    if (diff == 0) return '今天 $hh:$mm';
    if (diff == 1) return '昨天 $hh:$mm';
    if (diff < 7) return '${diff}天前';
    return '${dt.year.toString().padLeft(4, "0")}-${dt.month.toString().padLeft(2, "0")}-${dt.day.toString().padLeft(2, "0")}';
  }
}
