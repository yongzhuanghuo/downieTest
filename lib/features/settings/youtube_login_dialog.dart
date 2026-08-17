import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../core/storage/youtube_cookies.dart';

/// YouTube 登录弹窗
///
/// 内置浏览器打开 youtube.com，用户登录后点「完成登录」，
/// 抓取 youtube.com 的 cookie 存成 cookies.txt（Netscape 格式）。
class YoutubeLoginDialog extends StatefulWidget {
  const YoutubeLoginDialog({super.key});

  /// 弹出登录框；返回 true 表示登录成功并已保存 cookie
  static Future<bool> show(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const YoutubeLoginDialog(),
    );
    return ok ?? false;
  }

  @override
  State<YoutubeLoginDialog> createState() => _YoutubeLoginDialogState();
}

class _YoutubeLoginDialogState extends State<YoutubeLoginDialog> {
  bool _saving = false;

  Future<void> _finish() async {
    setState(() => _saving = true);
    try {
      final cookies = await CookieManager.instance()
          .getCookies(url: WebUri('https://www.youtube.com'));
      await YoutubeCookies.saveCookies(cookies);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存 Cookie 失败：$e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      child: SizedBox(
        width: 900,
        height: 650,
        child: Column(
          children: [
            // 标题栏
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: theme.dividerColor)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.login, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('登录 YouTube 账号', style: theme.textTheme.titleMedium),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: '取消',
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
            ),
            // 内置浏览器
            Expanded(
              child: InAppWebView(
                initialUrlRequest: URLRequest(
                  url: WebUri('https://www.youtube.com'),
                ),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                ),
              ),
            ),
            // 底部按钮
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: theme.dividerColor)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '登录完成后点击「完成登录」',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _saving ? null : _finish,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: Text(_saving ? '保存中...' : '完成登录'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
