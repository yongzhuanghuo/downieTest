import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/license/license_client.dart';
import '../../shared/branding/app_brand.dart';
import '../../shared/routes/navigator_key.dart';
import '../../shared/theme/design_tokens.dart';
import '../../shared/widgets/window_panel.dart';
import '../help/support_dialog.dart';
import 'license_provider.dart';

/// Downie 式试用窗口。
///
/// 未授权时是一个独立的大窗口：图标、试用说明、剩余天数进度条，
/// 以及「继续试用 / 输入许可证代码」两个入口。点「输入许可证代码」
/// 后在同一窗口内展开电子邮箱 + 许可证代码表单。
class TrialWindow extends ConsumerStatefulWidget {
  /// 打开时直接显示激活表单（菜单「输入许可证代码…」）。
  final bool initialActivation;

  const TrialWindow({super.key, this.initialActivation = false});

  static Future<bool?> show(
    BuildContext context, {
    bool initialActivation = false,
  }) {
    return showWindowPanel<bool>(
      context: context,
      title: '试用',
      width: 758,
      height: 466,
      showTitleBar: false,
      child: TrialWindow(initialActivation: initialActivation),
    );
  }

  @override
  ConsumerState<TrialWindow> createState() => _TrialWindowState();
}

class _TrialWindowState extends ConsumerState<TrialWindow> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  late bool _showActivation;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _showActivation = widget.initialActivation;
    _emailController.text = LicenseStorage.instance.current?.email ?? '';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(trialProvider.notifier).refresh();
      }
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    if (_busy) return;
    final code = _codeController.text.trim();
    final email = _emailController.text.trim();
    if (code.isEmpty) {
      setState(() => _message = '请输入许可证代码');
      return;
    }
    if (email.isEmpty) {
      setState(() => _message = '请输入购买时使用的电子邮箱');
      return;
    }
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _message = '电子邮箱格式不正确');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    final (ok, message) = await ref
        .read(licenseNotifierProvider.notifier)
        .activate(code, email: email);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = ok ? null : message;
    });
    if (ok && mounted) {
      Navigator.of(context).maybePop(true);
    }
  }

  Future<void> _openSupport() async {
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null) return;
    Navigator.of(context).maybePop();
    await SupportDialog.show(ctx);
  }

  Future<void> _openRecovery() {
    return showRecoverLicenseDialog(
      context,
      email: _emailController.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isPro = ref.watch(isProProvider);
    if (isPro) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop(true);
      });
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final trialAsync = ref.watch(trialProvider);
    final trial = trialAsync.asData?.value;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 40, 32, 26),
      child: _showActivation
          ? _buildActivation(context)
          : _buildTrial(context, trialAsync, trial),
    );
  }

  Widget _buildTrial(
    BuildContext context,
    AsyncValue<TrialInfo?> trialAsync,
    TrialInfo? trial,
  ) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final primary =
        dark ? AppTokens.textPrimary : AppTokens.textPrimaryLight;
    final secondary =
        dark ? AppTokens.textSecondary : AppTokens.textSecondaryLight;
    final accent = dark ? AppTokens.accent : AppTokens.accentLight;

    final loading = trialAsync.isLoading && trial == null;
    final failed = trial == null && !loading;
    final expired = trial != null && !trial.isActive;
    final days = trialDaysRemaining(trial);
    final progress = (days / 14).clamp(0.0, 1.0).toDouble();

    final title = loading
        ? '正在获取试用状态…'
        : failed
            ? '无法获取试用状态'
            : expired
                ? '试用结束'
                : '感谢您试用 ${AppBrand.name}！';

    final body = loading
        ? '正在向服务器确认本机的试用资格，请稍候。'
        : failed
            ? '暂时无法获取试用状态，请检查网络后重试，或直接输入许可证代码。'
            : expired
                ? '试用期已过。您需要购买副本或输入有效的许可证代码才能继续使用 ${AppBrand.name}。'
                : '您可以继续免费使用 ${AppBrand.name} 在接下来的 $days 天，不受任何限制。'
                    '试用期结束后，您需要购买副本或输入有效的许可证代码才能继续使用。';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Image.asset(
              AppBrand.logoAsset,
              width: 128,
              height: 128,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: primary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    body,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: secondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const Spacer(),
        if (loading)
          const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (failed)
          Center(
            child: TextButton(
              onPressed: () =>
                  ref.read(trialProvider.notifier).forceRefresh(),
              child: const Text('重试'),
            ),
          )
        else ...[
          Center(
            child: Text(
              expired ? '试用已结束' : '剩余 $days 天',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: secondary,
              ),
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: expired ? 0 : progress,
              minHeight: 8,
              backgroundColor: theme.dividerColor.withValues(alpha: 0.25),
              color: accent,
            ),
          ),
        ],
        const Spacer(),
        Row(
          children: [
            if (!loading && !failed && !expired)
              TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('继续试用'),
              ),
            const Spacer(),
            if (AppBrand.purchaseUrl.isNotEmpty)
              TextButton(
                onPressed: () async {
                  await launchUrl(Uri.parse(AppBrand.purchaseUrl));
                },
                child: const Text('立即购买'),
              ),
            if (AppBrand.purchaseUrl.isNotEmpty) const SizedBox(width: 8),
            TextButton(
              onPressed: () {
                setState(() {
                  _showActivation = true;
                  _message = null;
                });
              },
              child: const Text('输入许可证代码'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActivation(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final primary =
        dark ? AppTokens.textPrimary : AppTokens.textPrimaryLight;
    final secondary =
        dark ? AppTokens.textSecondary : AppTokens.textSecondaryLight;
    final error = dark ? AppTokens.error : AppTokens.errorLight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Image.asset(
              AppBrand.logoAsset,
              width: 96,
              height: 96,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '输入许可证代码',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '请填写购买时使用的电子邮箱和许可证代码，该邮箱会与许可证代码绑定。',
                    style: TextStyle(fontSize: 13, color: secondary),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        _FormRow(
          label: '电子邮箱',
          child: TextField(
            controller: _emailController,
            enabled: !_busy,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              hintText: '你自己的邮箱（购买时使用的）',
            ),
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(left: 104),
          child: Text(
            '请填写你自己的邮箱（购买时使用的邮箱），用于绑定授权和找回许可证代码。',
            style: TextStyle(fontSize: 11, color: secondary),
          ),
        ),
        const SizedBox(height: 12),
        _FormRow(
          label: '许可证代码',
          child: TextField(
            controller: _codeController,
            enabled: !_busy,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              hintText: 'XXXXX-XXXXX-XXXXX-XXXXX',
            ),
            onSubmitted: (_) => _activate(),
          ),
        ),
        if (_message != null) ...[
          const SizedBox(height: 10),
          Text(
            _message!,
            style: TextStyle(fontSize: 12, color: error),
          ),
        ],
        const Spacer(),
        Row(
          children: [
            TextButton(
              onPressed: _busy ? null : _openSupport,
              child: const Text('获取支持'),
            ),
            const SizedBox(width: 4),
            TextButton(
              onPressed: _busy ? null : _openRecovery,
              child: const Text('许可证代码丢失了?'),
            ),
            const Spacer(),
            TextButton(
              onPressed: _busy
                  ? null
                  : () {
                      setState(() {
                        _showActivation = false;
                        _message = null;
                      });
                    },
              child: const Text('返回试用信息'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _busy ? null : _activate,
              child: _busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('激活许可证'),
            ),
          ],
        ),
      ],
    );
  }
}

class _FormRow extends StatelessWidget {
  final String label;
  final Widget child;

  const _FormRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final secondary =
        dark ? AppTokens.textSecondary : AppTokens.textSecondaryLight;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: secondary,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(child: child),
      ],
    );
  }
}

/// 「许可证代码丢失了?」：按用户选择走邮件联系支持，不做服务端找回。
Future<void> showRecoverLicenseDialog(
  BuildContext context, {
  String? email,
}) async {
  final proceed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('许可证代码丢失了？'),
      content: const Text(
        '请使用购买时使用的电子邮箱地址联系支持，'
        '我们会在核实后重新发送许可证代码。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('联系支持'),
        ),
      ],
    ),
  );
  if (proceed != true) return;

  final body = StringBuffer('我的许可证代码丢失了，请协助找回。');
  if (email != null && email.isNotEmpty) {
    body.write('\n购买邮箱：$email');
  }
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
