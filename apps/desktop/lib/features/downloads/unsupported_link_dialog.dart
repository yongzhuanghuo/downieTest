import 'package:flutter/material.dart';

import '../../shared/theme/design_tokens.dart';

enum UnsupportedAction { extract, support, ignore }

class UnsupportedResult {
  final UnsupportedAction action;
  final bool autoUge;

  const UnsupportedResult(this.action, this.autoUge);
}

/// Downie 风格的「不支持的链接」提示。
class UnsupportedLinkDialog extends StatefulWidget {
  final bool initialAutoUge;

  const UnsupportedLinkDialog({super.key, this.initialAutoUge = false});

  static Future<UnsupportedResult?> show(
    BuildContext context, {
    bool initialAutoUge = false,
  }) {
    return showDialog<UnsupportedResult>(
      context: context,
      builder: (_) => UnsupportedLinkDialog(initialAutoUge: initialAutoUge),
    );
  }

  @override
  State<UnsupportedLinkDialog> createState() => _UnsupportedLinkDialogState();
}

class _UnsupportedLinkDialogState extends State<UnsupportedLinkDialog> {
  late bool _autoUge = widget.initialAutoUge;

  void _finish(UnsupportedAction action) {
    Navigator.of(context).pop(UnsupportedResult(action, _autoUge));
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
        width: 470,
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
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
              '有一些下载链接被跳过，因为 Downie6 无法识别它们。',
              style: TextStyle(
                fontSize: 15,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: text,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              '但不要放弃尝试！Downie6 还有两个秘密武器：您可以尝试使用'
              '「用户自定义提取」，在内置浏览器中打开链接，Downie6 会检测出'
              '可供下载的媒体和链接；或者点击主程序窗口右上角的「联系支持」按钮，'
              '请求添加对该链接的支持。',
              style: TextStyle(fontSize: 12, height: 1.45, color: secondary),
            ),
            const SizedBox(height: AppSpacing.lg),
            InkWell(
              onTap: () => setState(() => _autoUge = !_autoUge),
              borderRadius: BorderRadius.circular(AppRadius.control),
              child: Row(
                children: [
                  Checkbox(
                    value: _autoUge,
                    onChanged: (value) =>
                        setState(() => _autoUge = value ?? false),
                  ),
                  Expanded(
                    child: Text(
                      '始终在「用户自定义提取」中打开不支持的链接',
                      style: TextStyle(fontSize: 12, color: secondary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _DialogButton(
              label: '尝试使用「用户自定义提取」',
              background: dark ? AppTokens.hover : const Color(0xFFF3F3F5),
              textColor: text,
              onTap: () => _finish(UnsupportedAction.extract),
            ),
            const SizedBox(height: AppSpacing.sm),
            _DialogButton(
              label: '请求添加支持…',
              background: dark ? AppTokens.hover : const Color(0xFFF3F3F5),
              textColor: text,
              onTap: () => _finish(UnsupportedAction.support),
            ),
            const SizedBox(height: AppSpacing.sm),
            _DialogButton(
              label: '忽略',
              background: dark ? AppTokens.hover : const Color(0xFFF3F3F5),
              textColor: text,
              onTap: () => _finish(UnsupportedAction.ignore),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogButton extends StatelessWidget {
  final String label;
  final Color background;
  final Color textColor;
  final VoidCallback onTap;

  const _DialogButton({
    required this.label,
    required this.background,
    required this.textColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.button),
      child: Container(
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 12, color: textColor),
        ),
      ),
    );
  }
}
