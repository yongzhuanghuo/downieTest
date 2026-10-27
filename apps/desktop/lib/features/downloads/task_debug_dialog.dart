import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/storage/settings_storage.dart';
import '../../data/models/download_task.dart';

/// 单任务调试信息（Downie 的 Download Debugger 的轻量版）。
class TaskDebugDialog extends StatelessWidget {
  final DownloadTask task;

  const TaskDebugDialog({super.key, required this.task});

  static Future<void> show(BuildContext context, DownloadTask task) {
    return showDialog<void>(
      context: context,
      builder: (_) => TaskDebugDialog(task: task),
    );
  }

  String get _text {
    final map = task.toMap();
    map['format_id'] = task.formatId;
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  Future<void> _openTaskLog(BuildContext context) async {
    try {
      final dir = await SettingsStorage.getStorageDir();
      final path = '${dir.path}/logs/task_${task.id}.log';
      final file = File(path);
      if (!await file.exists()) {
        if (context.mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(content: Text('这个任务还没有生成 yt-dlp 日志')),
          );
        }
        return;
      }
      if (Platform.isMacOS) {
        await Process.run('open', ['-t', path]);
      } else if (Platform.isWindows) {
        await Process.run('notepad', [path]);
      }
    } catch (e) {
      debugPrint('[调试] 打开任务日志失败: $e');
    }
  }

  Future<void> _openLogs() async {
    try {
      final dir = await SettingsStorage.getStorageDir();
      final logs = Directory('${dir.path}/logs');
      if (!await logs.exists()) await logs.create(recursive: true);
      await Process.run(
        Platform.isMacOS ? 'open' : 'explorer',
        [logs.path],
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('下载调试信息'),
      content: SizedBox(
        width: 560,
        height: 380,
        child: SingleChildScrollView(
          child: SelectableText(
            _text,
            style: const TextStyle(fontSize: 11, height: 1.45),
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () => _openTaskLog(context),
          icon: const Icon(Icons.description_outlined, size: 15),
          label: const Text('任务日志'),
        ),
        TextButton.icon(
          onPressed: _openLogs,
          icon: const Icon(Icons.folder_open, size: 15),
          label: const Text('打开日志目录'),
        ),
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: _text));
          },
          icon: const Icon(Icons.copy, size: 15),
          label: const Text('复制'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
