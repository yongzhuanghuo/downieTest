import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/branding/app_brand.dart';
import 'help_window.dart';

enum _SupportAction { reportLink, general, help }

/// 支持/报告窗口：报告链接、通用报告、打开帮助。
class SupportDialog extends StatefulWidget {
  final String? reportUrl;

  const SupportDialog({super.key, this.reportUrl});

  static Future<void> show(BuildContext context, {String? reportUrl}) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      builder: (_) => SupportDialog(reportUrl: reportUrl),
    );
  }

  @override
  State<SupportDialog> createState() => _SupportDialogState();
}

class _SupportDialogState extends State<SupportDialog> {
  _SupportAction _selected = _SupportAction.reportLink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    final width = size.width * 0.78 > 920 ? 920.0 : size.width * 0.78;
    final height = size.height - 48 > 560 ? 560.0 : size.height - 48;

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: SizedBox(
        width: width,
        height: height,
        child: Column(
          children: [
            _buildHeader(theme),
            Divider(
              height: 1,
              color: theme.dividerColor.withValues(alpha: 0.4),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  _buildOption(
                    _SupportAction.reportLink,
                    Icons.link,
                    '报告链接',
                    '视频没有下载？请把链接发给我们，我们会尽力解决。',
                  ),
                  _buildOption(
                    _SupportAction.general,
                    Icons.mail_outline,
                    '通用报告',
                    '遇到使用问题或有建议？欢迎通过邮件联系我们。',
                  ),
                  _buildOption(
                    _SupportAction.help,
                    Icons.help_outline,
                    '打开帮助',
                    '浏览帮助手册，里面可能包含你正在寻找的答案。',
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              color: theme.dividerColor.withValues(alpha: 0.4),
            ),
            _buildFooter(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset(AppBrand.logoAsset, width: 56, height: 56),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '我们能为您提供什么帮助？',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  '我们会尽快回复，通常在 24 小时之内。周末和节假日可能稍晚。',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '关闭',
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildOption(
    _SupportAction action,
    IconData icon,
    String title,
    String subtitle,
  ) {
    final theme = Theme.of(context);
    final selected = _selected == action;
    final accent = theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: selected ? accent.withValues(alpha: 0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _selected = action),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? accent.withValues(alpha: 0.45)
                    : theme.dividerColor.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: selected
                        ? accent
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    color: selected
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  selected ? Icons.check_circle : Icons.circle_outlined,
                  color: selected
                      ? accent
                      : theme.colorScheme.outlineVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: _showPrivacy,
            icon: const Icon(Icons.privacy_tip_outlined, size: 16),
            label: const Text('隐私信息…'),
          ),
          TextButton.icon(
            onPressed: () => HelpWindow.show(context),
            icon: const Icon(Icons.help_outline, size: 16),
            label: const Text('显示帮助'),
          ),
          const Spacer(),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _send,
            child: const Text('发送'),
          ),
        ],
      ),
    );
  }

  Future<void> _send() async {
    if (_selected == _SupportAction.help) {
      await HelpWindow.show(context);
      return;
    }

    final isLink = _selected == _SupportAction.reportLink;
    final subject = isLink
        ? '[${AppBrand.name}] 报告链接'
        : '[${AppBrand.name}] 反馈';
    final body = isLink
        ? '链接：${widget.reportUrl ?? '（请粘贴视频链接）'}\n\n问题描述：\n'
        : '问题/建议：\n';
    final uri = Uri(
      scheme: 'mailto',
      path: AppBrand.supportEmail,
      queryParameters: {
        'subject': subject,
        'body': body,
      },
    );

    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('请发送邮件到 ${AppBrand.supportEmail}')),
      );
    }
  }

  Future<void> _showPrivacy() {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('隐私信息'),
        content: Text(AppBrand.privacyNote),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}
