import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/platform/window_close_coordinator.dart';
import '../../shared/branding/app_brand.dart';
import '../../shared/widgets/restore_glyph.dart';
import 'help_window.dart';
import 'support_report.dart';

/// Downie 式支持窗口：邮箱、链接、需要账户、问题描述和诊断信息。
///
/// 发送使用 mailto 打开系统邮件客户端；没有默认客户端时自动提供
/// 「复制报告」，避免邮件按钮变成死路。
class SupportDialog extends StatefulWidget {
  final String reportUrl;
  final String initialMessage;
  final String account;
  final String? taskId;

  const SupportDialog({
    super.key,
    this.reportUrl = '',
    this.initialMessage = '',
    this.account = '',
    this.taskId,
  });

  static Future<void> show(
    BuildContext context, {
    String reportUrl = '',
    String initialMessage = '',
    String account = '',
    String? taskId,
  }) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, __, ___) => SupportDialog(
          reportUrl: reportUrl,
          initialMessage: initialMessage,
          account: account,
          taskId: taskId,
        ),
      ),
    );
  }

  @override
  State<SupportDialog> createState() => _SupportDialogState();
}

class _SupportDialogState extends State<SupportDialog> with WindowListener {
  static const _boxName = 'downlo_support';
  static const _emailKey = 'lastEmail';

  final _emailController = TextEditingController();
  final _urlController = TextEditingController();
  final _accountController = TextEditingController();
  final _messageController = TextEditingController();

  bool _includeDiagnostics = true;
  bool _closing = false;
  bool _sending = false;
  bool _openedMailClient = false;
  bool _maximized = false;
  String? _emailError;
  String _diagnostics = '';
  SupportReport? _lastReport;

  @override
  void initState() {
    super.initState();
    _urlController.text = widget.reportUrl;
    _accountController.text = widget.account;
    if (widget.initialMessage.isNotEmpty) {
      _messageController.text = widget.initialMessage;
    }
    windowManager.addListener(this);
    WindowCloseCoordinator.instance.push(this, _close);
    _syncMaximized();
    _loadLastEmail();
    _loadDiagnostics();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    WindowCloseCoordinator.instance.pop(this);
    _emailController.dispose();
    _urlController.dispose();
    _accountController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadLastEmail() async {
    try {
      final box = await Hive.openBox(_boxName);
      final email = box.get(_emailKey)?.toString() ?? '';
      if (email.isNotEmpty && mounted) {
        _emailController.text = email;
      }
    } catch (_) {}
  }

  Future<void> _saveEmail(String email) async {
    try {
      final box = await Hive.openBox(_boxName);
      await box.put(_emailKey, email);
    } catch (_) {}
  }

  Future<void> _loadDiagnostics() async {
    final text = await collectSupportDiagnostics(taskId: widget.taskId);
    if (mounted) setState(() => _diagnostics = text);
  }

  Future<void> _syncMaximized() async {
    try {
      final maximized = await windowManager.isMaximized();
      final fullscreen = await windowManager.isFullScreen();
      if (mounted) setState(() => _maximized = maximized || fullscreen);
    } catch (_) {}
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _maximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _maximized = false);
  }

  @override
  void onWindowEnterFullScreen() {
    if (mounted) setState(() => _maximized = true);
  }

  @override
  void onWindowLeaveFullScreen() {
    if (mounted) setState(() => _maximized = false);
  }

  Future<void> _toggleMaximize() async {
    try {
      if (await windowManager.isFullScreen()) {
        await windowManager.setFullScreen(false);
      } else if (await windowManager.isMaximized()) {
        await windowManager.unmaximize();
      } else {
        await windowManager.maximize();
      }
      await _syncMaximized();
    } catch (_) {}
  }

  void _close() {
    if (_closing || !mounted) return;
    _closing = true;
    Navigator.of(context).maybePop();
  }

  SupportReport _report() {
    return buildSupportReport(
      email: _emailController.text,
      url: _urlController.text,
      account: _accountController.text,
      message: _messageController.text,
      diagnostics: _includeDiagnostics ? _diagnostics : '',
    );
  }

  Future<void> _send() async {
    final error = validateSupportEmail(_emailController.text);
    if (error != null) {
      setState(() => _emailError = error);
      return;
    }
    setState(() {
      _emailError = null;
      _sending = true;
      _openedMailClient = false;
      _lastReport = _report();
    });
    await _saveEmail(_emailController.text.trim());
    final report = _lastReport!;
    var opened = false;
    try {
      opened = await launchUrl(
        report.mailtoUri,
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
    if (!mounted) return;
    setState(() {
      _sending = false;
      _openedMailClient = opened;
    });
    if (!opened) {
      await _showCopyFallback(report);
    }
  }

  Future<void> _copyReport() async {
    final report = _report();
    _lastReport = report;
    await Clipboard.setData(ClipboardData(text: report.clipboardText));
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('报告已复制，可粘贴到任意邮箱发送')),
    );
  }

  Future<void> _showCopyFallback(SupportReport report) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('未找到邮件客户端'),
        content: SizedBox(
          width: 560,
          height: 320,
          child: SelectableText(report.clipboardText),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: report.clipboardText),
              );
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('复制报告'),
          ),
          TextButton(
            onPressed: () {
              Clipboard.setData(
                ClipboardData(text: AppBrand.supportEmail),
              );
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('复制邮箱地址'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final secondary =
        dark ? theme.colorScheme.onSurfaceVariant : const Color(0xFF6E6E73);
    final isMac = Platform.isMacOS;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): _close,
        SingleActivator(
          LogicalKeyboardKey.keyW,
          meta: isMac,
          control: !isMac,
        ): _close,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: theme.colorScheme.surface,
          body: Column(
            children: [
              _buildHeader(theme),
              Divider(
                height: 1,
                color: theme.dividerColor.withValues(alpha: 0.4),
              ),
              Expanded(
                child: Scrollbar(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(40, 30, 40, 28),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '我们能为您提供什么帮助？',
                              style: theme.textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '我们会尽快回复您的报告，通常 24 小时之内。'
                              '周末和公共假期可能稍晚。',
                              style: TextStyle(
                                fontSize: 12.5,
                                height: 1.45,
                                color: secondary,
                              ),
                            ),
                            const SizedBox(height: 24),
                            _fieldLabel(theme, '您的邮箱'),
                            SizedBox(
                              width: 360,
                              child: TextField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                style: const TextStyle(fontSize: 13),
                                decoration: InputDecoration(
                                  hintText: 'buyer@example.com',
                                  errorText: _emailError,
                                  isDense: true,
                                ),
                                onChanged: (_) {
                                  if (_emailError != null) {
                                    setState(() => _emailError = null);
                                  }
                                },
                              ),
                            ),
                            const SizedBox(height: 14),
                            _fieldLabel(theme, '链接'),
                            TextField(
                              controller: _urlController,
                              style: const TextStyle(fontSize: 13),
                              decoration: const InputDecoration(
                                hintText: '相关视频链接（可选）',
                                isDense: true,
                              ),
                            ),
                            const SizedBox(height: 14),
                            _fieldLabel(theme, '需要账户'),
                            TextField(
                              controller: _accountController,
                              style: const TextStyle(fontSize: 13),
                              decoration: const InputDecoration(
                                hintText: '需要登录的站点/账户（可选）',
                                isDense: true,
                              ),
                            ),
                            const SizedBox(height: 14),
                            _fieldLabel(theme, '问题描述'),
                            TextField(
                              controller: _messageController,
                              minLines: 7,
                              maxLines: 12,
                              style: const TextStyle(fontSize: 13, height: 1.45),
                              decoration: const InputDecoration(
                                hintText: '请描述你遇到的问题、期望结果，以及复现步骤…',
                                alignLabelWithHint: true,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Checkbox(
                                  value: _includeDiagnostics,
                                  onChanged: (value) => setState(
                                    () => _includeDiagnostics = value ?? false,
                                  ),
                                ),
                                const SizedBox(width: 2),
                                Expanded(
                                  child: Text(
                                    '附带诊断信息（版本、系统、最近日志）',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: secondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (_includeDiagnostics)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surfaceContainerLow
                                      .withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: SelectableText(
                                  _diagnostics.isEmpty
                                      ? '正在收集诊断信息…'
                                      : _diagnostics,
                                  maxLines: 6,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    height: 1.35,
                                    color: secondary,
                                  ),
                                ),
                              ),
                            if (_openedMailClient) ...[
                              const SizedBox(height: 14),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary
                                      .withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '已打开邮件客户端，请确认发送。'
                                  '如果没有打开，请点「复制报告」后粘贴到任意邮箱。',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
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
      ),
    );
  }

  Widget _fieldLabel(ThemeData theme, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => windowManager.startDragging(),
      onDoubleTap: _toggleMaximize,
      child: Container(
        height: 52,
        padding: EdgeInsets.fromLTRB(Platform.isMacOS ? 92 : 16, 0, 8, 0),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.asset(AppBrand.logoAsset, width: 26, height: 26),
            ),
            const SizedBox(width: 9),
            Text(
              '联系支持',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            if (Platform.isWindows) ...[
              IconButton(
                tooltip: '最小化',
                icon: const Icon(Icons.remove, size: 15),
                onPressed: () => windowManager.minimize(),
              ),
              IconButton(
                tooltip: _maximized ? '还原' : '最大化',
                icon: _maximized
                    ? RestoreGlyph(
                        color: theme.colorScheme.onSurfaceVariant,
                        size: 12,
                      )
                    : const Icon(Icons.crop_square, size: 13),
                onPressed: _toggleMaximize,
              ),
            ],
            IconButton(
              tooltip: '关闭',
              icon: const Icon(Icons.close, size: 20),
              onPressed: _close,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
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
            onPressed: _copyReport,
            child: const Text('复制报告'),
          ),
          const SizedBox(width: 6),
          TextButton(
            onPressed: _close,
            child: const Text('取消'),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _sending ? null : _send,
            child: _sending
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('发送'),
          ),
        ],
      ),
    );
  }
}
