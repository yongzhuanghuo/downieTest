import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../core/platform/webview2.dart';
import '../../core/storage/site_cookies.dart';
import '../../core/storage/site_registry.dart';

/// 站点登录弹窗（通用）
///
/// 内置浏览器打开 [SiteConfig.loginUrl]，用户登录后点「完成登录」，
/// 抓取该站 cookie 存成 cookies/{siteId}.txt。
class SiteLoginDialog extends StatefulWidget {
  final SiteConfig site;
  final WebViewEnvironment? environment;

  const SiteLoginDialog({super.key, required this.site, this.environment});

  /// 弹出登录框；返回 true 表示登录成功并已保存 cookie
  static Future<bool> show(BuildContext context, SiteConfig site) async {
    // Windows 上禁用 GPU 硬件加速，避免虚拟机/部分显卡白屏
    WebViewEnvironment? env;
    if (Platform.isWindows) {
      try {
        env = await WebViewEnvironment.create(
          settings: WebViewEnvironmentSettings(
            additionalBrowserArguments: '--disable-gpu --disable-gpu-compositing',
          ),
        );
      } catch (e) {
        debugPrint('[登录] WebView2 环境创建失败: $e');
      }
    }
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SiteLoginDialog(site: site, environment: env),
    );
    return ok ?? false;
  }

  @override
  State<SiteLoginDialog> createState() => _SiteLoginDialogState();
}

class _SiteLoginDialogState extends State<SiteLoginDialog> {
  bool _saving = false;
  bool _webView2Missing = false;

  @override
  void initState() {
    super.initState();
    // Windows 没装 WebView2 会空白，这里先检测，缺了就提示
    final available = isWebView2Available();
    _webView2Missing = !available;
    debugPrint('[登录] WebView2 可用: $available');
  }

  Future<void> _finish() async {
    setState(() => _saving = true);
    try {
      final cookies = await CookieManager.instance()
          .getCookies(url: WebUri(widget.site.loginUrl));
      debugPrint('[登录] ${widget.site.name} 抓到 ${cookies.length} 条 cookie');
      await SiteCookies.saveCookies(widget.site.id, cookies);
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

  /// Windows 缺 WebView2 时显示的提示（引导用户去安装）
  Widget _buildWebView2Missing(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text('未检测到 WebView2 运行时', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '登录页需要微软 WebView2 内核才能显示，请安装后重新登录',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                openWebView2DownloadPage();
              },
              icon: const Icon(Icons.download),
              label: const Text('去下载 WebView2'),
            ),
          ],
        ),
      ),
    );
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
                    child: Text(
                      '登录 ${widget.site.name}',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: '取消',
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _webView2Missing
                  ? _buildWebView2Missing(theme)
                  : InAppWebView(
                      webViewEnvironment: widget.environment,
                      initialUrlRequest:
                          URLRequest(url: WebUri(widget.site.loginUrl)),
                      initialSettings:
                          InAppWebViewSettings(javaScriptEnabled: true),
                    ),
            ),
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
                    onPressed: (_saving || _webView2Missing) ? null : _finish,
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
