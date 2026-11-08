import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/license/license_client.dart';
import '../../shared/branding/app_brand.dart';
import 'license_provider.dart';

/// 「许可证代码丢失了？」：输入邮箱，服务端把该邮箱下的卡密发到邮箱。
///
/// 返回用户点「我已拿到卡密」时使用的邮箱（便于调用方回填激活表单）；
/// 取消或关闭返回 null。
Future<String?> showRecoverLicenseDialog(
  BuildContext context, {
  String? email,
}) {
  final typed = (email ?? '').trim();
  final initial = typed.isNotEmpty
      ? typed
      : (LicenseStorage.instance.current?.email ?? '');
  return showDialog<String>(
    context: context,
    builder: (_) => _RecoverLicenseDialog(initialEmail: initial),
  );
}

const _emailPattern = r'^[^@\s]+@[^@\s]+\.[^@\s]+$';

class _RecoverLicenseDialog extends StatefulWidget {
  final String initialEmail;

  const _RecoverLicenseDialog({required this.initialEmail});

  @override
  State<_RecoverLicenseDialog> createState() => _RecoverLicenseDialogState();
}

class _RecoverLicenseDialogState extends State<_RecoverLicenseDialog> {
  late final TextEditingController _emailController;
  bool _busy = false;
  bool _sent = false;
  String _sentTo = '';
  String? _error;
  int _cooldown = 0;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _emailController.dispose();
    super.dispose();
  }

  void _runCooldownTimer() {
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        _cooldown -= 1;
        if (_cooldown <= 0) timer.cancel();
      });
    });
  }

  Future<void> _send() async {
    final email = _emailController.text.trim();
    if (!RegExp(_emailPattern).hasMatch(email)) {
      setState(() => _error = '邮箱格式不正确');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await LicenseClient.instance.recoverLicense(email: email);
    if (!mounted) return;
    if (result.ok && result.found) {
      setState(() {
        _busy = false;
        _sent = true;
        _sentTo = email;
        _cooldown = result.retryAfter > 0 ? result.retryAfter : 60;
      });
      _runCooldownTimer();
    } else {
      setState(() {
        _busy = false;
        _error = result.message ??
            (result.ok ? '该邮箱下没有找到许可证' : '发送失败，请稍后重试');
      });
    }
  }

  Future<void> _openSupportMail() async {
    final email = _sentTo.isNotEmpty
        ? _sentTo
        : _emailController.text.trim();
    final body = StringBuffer('我的许可证代码丢失了，请协助找回。');
    if (email.isNotEmpty) body.write('\n购买邮箱：$email');
    final uri = Uri(
      scheme: 'mailto',
      path: AppBrand.supportEmail,
      queryParameters: {
        'subject': '${AppBrand.name} 许可证代码找回',
        'body': body.toString(),
      },
    );
    try {
      await launchUrl(uri);
    } catch (e) {
      debugPrint('[授权] 打开邮件客户端失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('找回许可证代码'),
      content: SizedBox(
        width: 400,
        child: _sent ? _buildSent(theme) : _buildEmail(theme),
      ),
      actions: _sent ? _sentActions() : _emailActions(),
    );
  }

  Widget _buildEmail(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '输入激活时填写的电子邮箱，我们会把该邮箱下绑定的许可证代码发送到您的邮箱。',
          style: TextStyle(
            fontSize: 13,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _emailController,
          enabled: !_busy,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: '电子邮箱',
            hintText: '您自己的邮箱',
          ),
          onSubmitted: (_) => _busy ? null : _send(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(
            _error!,
            style: TextStyle(fontSize: 12, color: theme.colorScheme.error),
          ),
        ],
        const SizedBox(height: 10),
        TextButton(
          onPressed: _busy ? null : _openSupportMail,
          child: const Text('邮箱未绑定？联系支持'),
        ),
      ],
    );
  }

  Widget _buildSent(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '邮件已发送',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '邮件已发送到 $_sentTo，请查收（没收到请检查垃圾邮件）。'
          '拿到卡密后点「我已拿到卡密」，回到激活表单输入即可。',
          style: TextStyle(
            fontSize: 13,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(
            _error!,
            style: TextStyle(fontSize: 12, color: theme.colorScheme.error),
          ),
        ],
        const SizedBox(height: 10),
        TextButton(
          onPressed: _busy ? null : _openSupportMail,
          child: const Text('仍未收到？联系支持'),
        ),
      ],
    );
  }

  List<Widget> _emailActions() {
    return [
      TextButton(
        onPressed: _busy ? null : () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: _busy ? null : _send,
        child: Text(_busy ? '发送中…' : '发送'),
      ),
    ];
  }

  List<Widget> _sentActions() {
    return [
      TextButton(
        onPressed: _busy
            ? null
            : () => setState(() {
                  _sent = false;
                  _error = null;
                }),
        child: const Text('换个邮箱'),
      ),
      TextButton(
        onPressed: _busy || _cooldown > 0 ? null : _send,
        child: Text(_cooldown > 0 ? '重发 ($_cooldown)' : '重发'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(_sentTo),
        child: const Text('我已拿到卡密'),
      ),
    ];
  }
}
