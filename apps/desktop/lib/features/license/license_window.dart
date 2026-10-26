import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/branding/app_brand.dart';
import '../../shared/theme/design_tokens.dart';
import '../../shared/widgets/window_panel.dart';
import 'license_provider.dart';

/// Downie 式授权/试用窗口：14 天试用进度 + 授权码激活。
class LicenseWindow extends ConsumerStatefulWidget {
  const LicenseWindow({super.key});

  static Future<void> show(BuildContext context) async {
    await showWindowPanel<void>(
      context: context,
      title: '授权',
      width: 480,
      height: 380,
      child: const LicenseWindow(),
    );
  }

  @override
  ConsumerState<LicenseWindow> createState() => _LicenseWindowState();
}

class _LicenseWindowState extends ConsumerState<LicenseWindow> {
  final _codeController = TextEditingController();
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    if (_busy) return;
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _message = '请输入授权码');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    final (ok, message) =
        await ref.read(licenseNotifierProvider.notifier).activate(code);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = message;
    });
    if (ok) {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (mounted) Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trialAsync = ref.watch(trialProvider);
    final trial = trialAsync.asData?.value;
    final isPro = ref.watch(isProProvider);
    final license = ref.watch(activatedLicenseProvider);
    final days = trial?.daysRemaining ?? 0;
    final progress = (days / 14).clamp(0.0, 1.0);
    final dark = theme.brightness == Brightness.dark;
    final secondary =
        dark ? AppTokens.textSecondary : AppTokens.textSecondaryLight;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isPro) ...[
            Row(
              children: [
                const Icon(Icons.verified, size: 18, color: AppTokens.success),
                const SizedBox(width: AppSpacing.md),
                Text(
                  '已授权 ${license?.payload.type.label ?? 'PRO'}',
                  style: theme.textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (license != null)
              SelectableText(
                license.code,
                style: TextStyle(fontSize: 12, color: secondary),
              ),
            const SizedBox(height: AppSpacing.xl),
          ] else ...[
            Text(
              trial == null
                  ? '正在获取试用状态…'
                  : trial.isActive
                      ? '免费试用剩余 $days 天'
                      : '14 天试用已结束',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: theme.dividerColor.withValues(alpha: 0.3),
                color: AppTokens.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              '试用期内可无限下载；卸载重装不会重置。试用结束后需要授权码。',
              style: TextStyle(fontSize: 11, color: secondary),
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
          Text('输入授权码', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _codeController,
            enabled: !_busy,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              hintText: 'XXXXXXXX-XXXXXXXX-XXXXXXXX-XXXXXXXX-XXXXXXXX',
            ),
            onSubmitted: (_) => _activate(),
          ),
          if (_message != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              _message!,
              style: TextStyle(
                fontSize: 11,
                color: _message!.startsWith('激活成功')
                    ? AppTokens.success
                    : AppTokens.error,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          Row(
            children: [
              TextButton(
                onPressed: _openRecovery,
                child: const Text('找回授权码'),
              ),
              const Spacer(),
              if (!isPro && (trial?.isActive ?? false))
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('继续试用'),
                ),
              const SizedBox(width: AppSpacing.md),
              FilledButton(
                onPressed: _busy ? null : _activate,
                child: _busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('激活'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openRecovery() async {
    final uri = Uri(
      scheme: 'mailto',
      path: AppBrand.supportEmail,
      queryParameters: {'subject': '${AppBrand.name} 授权码找回'},
    );
    await launchUrl(uri);
  }
}
