import 'package:flutter/material.dart';

import '../../data/models/format_option.dart';
import '../../data/models/video_info.dart';
import '../../shared/theme/design_tokens.dart';

/// Downie 风格的「选择画质」弹窗（仅在偏好设置为“每次询问”时出现）。
class QualityPickerDialog extends StatefulWidget {
  final VideoInfo info;

  const QualityPickerDialog({super.key, required this.info});

  static Future<FormatOption?> show(
    BuildContext context,
    VideoInfo info,
  ) {
    return showDialog<FormatOption>(
      context: context,
      builder: (_) => QualityPickerDialog(info: info),
    );
  }

  @override
  State<QualityPickerDialog> createState() => _QualityPickerDialogState();
}

class _QualityPickerDialogState extends State<QualityPickerDialog> {
  late final List<FormatOption> _formats;
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    _formats = widget.info.formats;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final panel = dark ? AppTokens.panel : AppTokens.panelLight;
    final divider = dark ? AppTokens.divider : AppTokens.dividerLight;
    final text = dark ? AppTokens.textPrimary : AppTokens.textPrimaryLight;
    final secondary =
        dark ? AppTokens.textSecondary : AppTokens.textSecondaryLight;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        width: 430,
        constraints: const BoxConstraints(maxHeight: 520),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(AppRadius.window),
          border: Border.all(color: divider),
          boxShadow: const [
            BoxShadow(
              color: Color(0x55000000),
              blurRadius: 28,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '选择画质',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: text,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.info.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: secondary),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 320,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _formats.length,
                itemBuilder: (context, index) {
                  final format = _formats[index];
                  final selected = index == _selected;
                  return InkWell(
                    onTap: () => setState(() => _selected = index),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            selected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            size: 16,
                            color: selected
                                ? AppTokens.accent
                                : secondary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  format.audioOnly
                                      ? '${format.label} · 仅音频'
                                      : format.qualityTag == 'SD'
                                          ? format.label
                                          : '${format.qualityTag} · ${format.label}',
                                  style: TextStyle(fontSize: 12, color: text),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  [
                                    format.ext.toUpperCase(),
                                    if (format.height > 0)
                                      '${format.height}p',
                                    if (format.fps != null) '${format.fps}fps',
                                    if (format.fileSize != null)
                                      format.fileSizeText,
                                  ].join(' · '),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: secondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (index == 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppTokens.accent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                '推荐',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: AppTokens.accent,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 6),
                FilledButton(
                  onPressed: _formats.isEmpty
                      ? null
                      : () => Navigator.of(context)
                          .pop(_formats[_selected]),
                  child: const Text('添加下载'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
