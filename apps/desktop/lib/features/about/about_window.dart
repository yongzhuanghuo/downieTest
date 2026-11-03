import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../shared/branding/app_brand.dart';
import '../../shared/routes/navigator_key.dart';
import '../../shared/theme/design_tokens.dart';
import '../../shared/widgets/window_panel.dart';
import '../help/support_dialog.dart';
import '../license/license_provider.dart';

/// Downie 式关于窗口：图标、名称、版本号/编译号、授权状态。
///
/// 只保留我们有的入口（支持、隐私说明），不复制 Downie 的厂商/社交链接。
class AboutWindow extends ConsumerStatefulWidget {
  const AboutWindow({super.key});

  static Future<void> show(BuildContext context) {
    return showWindowPanel<void>(
      context: context,
      title: '关于',
      width: 575,
      height: 490,
      showTitleBar: false,
      child: const AboutWindow(),
    );
  }

  @override
  ConsumerState<AboutWindow> createState() => _AboutWindowState();
}

class _AboutWindowState extends ConsumerState<AboutWindow> {
  String _version = '—';
  String _buildNumber = '—';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _version = info.version.isEmpty ? '—' : info.version;
        _buildNumber = info.buildNumber.isEmpty ? '—' : info.buildNumber;
      });
    } catch (e) {
      debugPrint('[关于] 读取版本失败: $e');
    }
  }

  void _openSupport() {
    final ctx = rootNavigatorKey.currentContext;
    Navigator.of(context).maybePop();
    if (ctx != null) SupportDialog.show(ctx);
  }

  Future<void> _openPrivacy() {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('隐私政策'),
        content: SingleChildScrollView(
          child: Text(
            '${AppBrand.privacyNote}\n\n'
            '站点 cookie 保存在本地应用数据目录，用于后续解析/下载。'
            '偏好设置 → 家长控制与隐私可以一键清除站点登录数据或下载历史。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('好'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final primary =
        dark ? AppTokens.textPrimary : AppTokens.textPrimaryLight;
    final secondary =
        dark ? AppTokens.textSecondary : AppTokens.textSecondaryLight;

    final isPro = ref.watch(isProProvider);
    final license = ref.watch(activatedLicenseProvider);
    final trial = ref.watch(trialProvider).asData?.value;

    final String status;
    if (isPro) {
      final email = license?.email.trim() ?? '';
      status = email.isEmpty
          ? '已授权 ${license?.payload.type.label ?? 'PRO'}'
          : '授权给 $email';
    } else if (trial != null) {
      status = trial.isActive
          ? '试用剩余 ${trialDaysRemaining(trial)} 天'
          : '试用版（未购买许可证）';
    } else {
      status = '试用版（未购买许可证）';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 40, 36, 26),
      child: Column(
        children: [
          Image.asset(
            AppBrand.logoAsset,
            width: 170,
            height: 170,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 20),
          Text(
            AppBrand.name,
            style: TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w700,
              color: primary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            AppBrand.tagline,
            style: TextStyle(fontSize: 13, color: secondary),
          ),
          const SizedBox(height: 18),
          Text(
            '版本号 $_version (编译号 $_buildNumber)',
            style: TextStyle(fontSize: 13, color: primary),
          ),
          const SizedBox(height: 6),
          Text(
            status,
            style: TextStyle(fontSize: 13, color: secondary),
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton.icon(
                onPressed: _openSupport,
                icon: Icon(
                  Icons.arrow_circle_right_outlined,
                  size: 16,
                  color: secondary,
                ),
                label: const Text('支持'),
              ),
              const SizedBox(width: 12),
              TextButton.icon(
                onPressed: _openPrivacy,
                icon: Icon(
                  Icons.arrow_circle_right_outlined,
                  size: 16,
                  color: secondary,
                ),
                label: const Text('隐私政策'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
