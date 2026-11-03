import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/branding/app_brand.dart';
import '../../shared/theme/design_tokens.dart';
import '../../shared/widgets/window_panel.dart';
import '../settings/settings_provider.dart';
import 'license_provider.dart';

/// 已授权窗口：Downie 式「感谢您的注册！」信息卡。
///
/// 只展示电子邮箱和许可证代码；设备管理、停用许可证在应用菜单里。
class RegisteredWindow extends ConsumerWidget {
  const RegisteredWindow({super.key});

  static Future<void> show(BuildContext context) {
    return showWindowPanel<void>(
      context: context,
      title: '授权',
      width: 480,
      height: 349,
      showTitleBar: false,
      child: const RegisteredWindow(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final primary =
        dark ? AppTokens.textPrimary : AppTokens.textPrimaryLight;
    final secondary =
        dark ? AppTokens.textSecondary : AppTokens.textSecondaryLight;
    final license = ref.watch(activatedLicenseProvider);
    final settings = ref.watch(settingsProvider);

    final email = license?.email.trim() ?? '';
    final code = license?.code ?? '';
    final shownCode = settings.hideLicenseCode
        ? '•••••-•••••-•••••-•••••'
        : (code.isEmpty ? '—' : code);

    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 24, 40, 22),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Image.asset(
            AppBrand.logoAsset,
            width: 154,
            height: 154,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 22),
          Text(
            license == null ? '当前设备未激活' : '感谢您的注册！',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: primary,
            ),
          ),
          const Spacer(),
          _InfoRow(
            label: '电子邮箱',
            value: email.isEmpty ? '—' : email,
            labelColor: secondary,
            valueColor: primary,
          ),
          const SizedBox(height: 10),
          _InfoRow(
            label: '许可证代码',
            value: shownCode,
            labelColor: secondary,
            valueColor: primary,
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color labelColor;
  final Color valueColor;

  const _InfoRow({
    required this.label,
    required this.value,
    required this.labelColor,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 76,
          child: Text(
            label,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: labelColor,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SelectableText(
            value,
            style: TextStyle(fontSize: 13, color: valueColor),
          ),
        ),
      ],
    );
  }
}
