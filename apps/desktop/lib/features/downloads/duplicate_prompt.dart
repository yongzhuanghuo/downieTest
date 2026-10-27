import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/download_task.dart';
import '../../data/models/video_info.dart';
import '../settings/settings_provider.dart';
import 'download_provider.dart';

/// 重复下载询问。返回 true 表示继续添加。
Future<bool> confirmDuplicateDownload(
  BuildContext context,
  WidgetRef ref,
  VideoInfo info,
) async {
  final settings = ref.read(settingsProvider);
  if (!settings.duplicatePrompt) return true;

  final existing = ref
      .read(downloadListProvider)
      .where((t) =>
          t.url == info.url &&
          (t.isRunning ||
              t.isPending ||
              t.status == DownloadStatus.completed))
      .firstOrNull;
  if (existing == null) return true;

  final active = existing.isRunning || existing.isPending;
  final text = active
      ? '这个链接已经在下载队列里，仍要再添加一份吗？'
      : '这个视频以前下载过（${existing.title}），仍要重新下载吗？';
  if (!context.mounted) return false;
  return await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(active ? '已在队列中' : '已经下载过'),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('仍然添加'),
            ),
          ],
        ),
      ) ??
      false;
}
