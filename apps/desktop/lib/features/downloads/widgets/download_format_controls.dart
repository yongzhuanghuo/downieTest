import 'package:flutter/material.dart';

import '../../../data/models/download_task.dart';
import '../../../data/models/format_option.dart';
import '../../../shared/theme/design_tokens.dart';

/// 下载卡片上可选的分辨率列表。
///
/// 只列视频格式（纯音频由「后处理 → 仅音频」负责）；同名/同分辨率
/// 的重复项只保留一个，按高度从高到低排列。没有视频格式时退回原始列表，
/// 避免纯音频任务无法切换。
List<FormatOption> downloadFormatOptions(DownloadTask task) {
  final source = task.availableFormats;
  if (source.isEmpty) return const [];

  final videos = source.where((f) => !f.audioOnly).toList();
  final pool = videos.isEmpty ? source : videos;

  final options = <FormatOption>[];
  final seen = <String>{};
  for (final format in pool) {
    final key =
        '${format.height}|${format.ext.toLowerCase()}|'
        '${_formatLabel(format)}';
    if (seen.add(key)) options.add(format);
  }

  options.sort((a, b) {
    final byHeight = b.height.compareTo(a.height);
    if (byHeight != 0) return byHeight;
    final aMp4 = a.ext.toLowerCase() == 'mp4';
    final bMp4 = b.ext.toLowerCase() == 'mp4';
    if (aMp4 != bMp4) return aMp4 ? -1 : 1;
    return _formatLabel(a).compareTo(_formatLabel(b));
  });
  return options;
}

String _formatLabel(FormatOption format) {
  if (format.label.isNotEmpty) return format.label;
  if (format.height > 0) return '${format.height}p';
  return format.ext.toUpperCase();
}

/// 卡片上的画质下拉框 + 字幕/封面勾选。
///
/// 不依赖 Riverpod，回调由 [DownloadRow] 接到下载队列。
class DownloadFormatControls extends StatelessWidget {
  final DownloadTask task;
  final ValueChanged<FormatOption> onFormatSelected;
  final ValueChanged<bool> onSubtitlesChanged;
  final ValueChanged<bool> onCoverChanged;
  final VoidCallback onRefreshFormats;

  const DownloadFormatControls({
    super.key,
    required this.task,
    required this.onFormatSelected,
    required this.onSubtitlesChanged,
    required this.onCoverChanged,
    required this.onRefreshFormats,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _formatMenu(),
        const SizedBox(width: 4),
        _optionToggle(
          label: '字幕',
          value: task.downloadSubtitles,
          enabled: task.canConfigure,
          tooltip: task.downloadSubtitles ? '不下载字幕' : '下载字幕',
          onChanged: onSubtitlesChanged,
        ),
        const SizedBox(width: 4),
        _optionToggle(
          label: '封面',
          value: task.downloadCover,
          enabled: task.canConfigure,
          tooltip: task.downloadCover ? '不保存封面' : '保存封面',
          onChanged: onCoverChanged,
        ),
      ],
    );
  }

  Widget _formatMenu() {
    final formats = downloadFormatOptions(task);
    final label = task.formatLabel.isNotEmpty
        ? task.formatLabel
        : (task.audioOnly ? 'AUDIO' : task.ext.toUpperCase());

    if (!task.canConfigure) {
      return Tooltip(message: '解析完成后可修改', child: DownloadPill(label));
    }

    // 老任务恢复后格式列表可能为空：给一次重新解析的入口。
    if (formats.isEmpty) {
      return PopupMenuButton<String>(
        tooltip: '获取可用分辨率',
        onSelected: (_) => onRefreshFormats(),
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'refresh', child: Text('重新获取分辨率')),
        ],
        child: DownloadPill(label, chevron: true),
      );
    }

    return PopupMenuButton<FormatOption>(
      tooltip: '选择分辨率',
      onSelected: onFormatSelected,
      itemBuilder: (context) => [
        for (final format in formats)
          CheckedPopupMenuItem<FormatOption>(
            value: format,
            checked: _isCurrent(format),
            child: Text(
              _formatLabel(format) +
                  ((format.fileSize ?? 0) > 0
                      ? ' · ${format.fileSizeText}'
                      : ''),
            ),
          ),
      ],
      child: DownloadPill(label, chevron: true),
    );
  }

  bool _isCurrent(FormatOption format) {
    if (format.formatId == task.formatId) return true;
    if (format.height != task.height) return false;
    if (format.ext.toLowerCase() != task.ext.toLowerCase()) return false;
    if (task.formatLabel.isEmpty) return true;
    return _formatLabel(format) == task.formatLabel;
  }

  Widget _optionToggle({
    required String label,
    required bool value,
    required bool enabled,
    required String tooltip,
    required ValueChanged<bool> onChanged,
  }) {
    final checkedColor = !enabled
        ? Colors.white30
        : (value ? AppTokens.accent : Colors.white54);
    final textColor = !enabled
        ? Colors.white30
        : (value ? Colors.white : Colors.white70);

    return Tooltip(
      message: enabled ? tooltip : '解析完成后可修改',
      child: InkWell(
        onTap: enabled ? () => onChanged(!value) : null,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: value
                ? AppTokens.accent.withValues(alpha: enabled ? 0.22 : 0.10)
                : Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: value && enabled ? AppTokens.accent : Colors.white24,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                value ? Icons.check_box : Icons.check_box_outline_blank,
                size: 12,
                color: checkedColor,
              ),
              const SizedBox(width: 3),
              Text(label, style: TextStyle(fontSize: 10, color: textColor)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 卡片上统一的小胶囊样式（画质/后处理等）。
class DownloadPill extends StatelessWidget {
  final String label;
  final bool chevron;

  const DownloadPill(this.label, {super.key, this.chevron = false});

  @override
  Widget build(BuildContext context) {
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
}
