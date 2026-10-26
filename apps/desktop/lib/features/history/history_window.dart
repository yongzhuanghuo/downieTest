import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/download_task.dart';
import '../../shared/theme/design_tokens.dart';
import '../../shared/widgets/window_panel.dart';
import 'history_page.dart';

/// Downie 风格的简单历史窗口。
class HistoryWindow extends ConsumerWidget {
  const HistoryWindow({super.key});

  static Future<void?> show(BuildContext context) {
    return showWindowPanel<void>(
      context: context,
      title: '历史记录',
      width: 600,
      height: 420,
      child: const HistoryWindow(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final divider = dark ? AppTokens.divider : AppTokens.dividerLight;

    return history.when(
      loading: () => const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (error, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 28),
            const SizedBox(height: AppSpacing.md),
            const Text('历史记录加载失败'),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: () => ref.read(historyProvider.notifier).refresh(),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
      data: (items) {
        if (items.isEmpty) {
          return const Center(child: Text('暂无历史记录'));
        }
        return Column(
          children: [
            SizedBox(
              height: 38,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Row(
                  children: [
                    Text('${items.length} 条记录'),
                    const Spacer(),
                    TextButton(
                      onPressed: () => _confirmClear(context, ref),
                      child: const Text('清空'),
                    ),
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: divider),
            Expanded(
              child: Scrollbar(
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: items.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: divider),
                  itemBuilder: (context, index) =>
                      _HistoryRow(task: items[index]),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空历史记录'),
        content: const Text('确认清空全部历史记录？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(historyProvider.notifier).clearAll();
    }
  }
}

class _HistoryRow extends ConsumerWidget {
  final DownloadTask task;

  const _HistoryRow({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final secondary =
        dark ? AppTokens.textSecondary : AppTokens.textSecondaryLight;
    final text = dark ? AppTokens.textPrimary : AppTokens.textPrimaryLight;
    final canOpen = task.outputPath != null &&
        File(task.outputPath!).existsSync();

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title.isEmpty ? '未命名视频' : task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: text),
                ),
                const SizedBox(height: 3),
                Text(
                  _meta(task),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: secondary),
                ),
              ],
            ),
          ),
          if (canOpen)
            IconButton(
              onPressed: () => _openContainingFolder(task.outputPath!),
              tooltip: '在文件夹中显示',
              icon: const Icon(Icons.arrow_forward, size: 14),
              color: secondary,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 26, height: 26),
            ),
          IconButton(
            onPressed: () => ref.read(historyProvider.notifier).delete(task.id),
            tooltip: '删除',
            icon: const Icon(Icons.close, size: 14),
            color: secondary,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 26, height: 26),
          ),
        ],
      ),
    );
  }

  String _meta(DownloadTask task) {
    final parts = <String>[
      if (task.extractor.isNotEmpty) task.extractor,
      if (task.formatLabel.isNotEmpty) task.formatLabel,
      if (task.fileSize > 0) _formatBytes(task.fileSize),
      if (task.completedAt != null) _date(task.completedAt!),
    ];
    return parts.join(' · ');
  }

  String _formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(unit == 0 ? 0 : 1)}${units[unit]}';
  }

  String _date(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) return '今天';
    if (diff.inDays == 1) return '昨天';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _openContainingFolder(String path) async {
    try {
      final dir = File(path).parent.path;
      await Process.run(
        Platform.isMacOS ? 'open' : 'explorer',
        [dir],
      );
    } catch (e) {
      debugPrint('[历史] 打开目录失败: $e');
    }
  }
}
