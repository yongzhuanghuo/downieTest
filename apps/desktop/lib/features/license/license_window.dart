import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/license/license_client.dart';
import '../../shared/branding/app_brand.dart';
import '../../shared/theme/design_tokens.dart';
import '../../shared/widgets/window_panel.dart';
import '../settings/settings_provider.dart';
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
  final _emailController = TextEditingController();
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _codeController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    if (_busy) return;
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _message = '请输入授权码');
      return;
    }
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _message = '请输入购买邮箱');
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
    final settings = ref.watch(settingsProvider);
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
                settings.hideLicenseCode ? '授权码已隐藏' : license.code,
                style: TextStyle(fontSize: 12, color: secondary),
              ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _busy ? null : _deactivate,
                  icon: const Icon(Icons.key_off_outlined, size: 14),
                  label: const Text('反激活此设备'),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _busy ? null : _manageDevices,
                  icon: const Icon(Icons.devices, size: 14),
                  label: const Text('设备管理'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
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
          Text('购买邮箱（找回授权码用）', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _emailController,
            enabled: !_busy,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              hintText: 'you@example.com',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('输入授权码', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
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
                color: (_message!.contains('成功') ||
                        _message!.contains('已反激活'))
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

  Future<void> _manageDevices() async {
    await showDialog<void>(
      context: context,
      builder: (_) => const _DeviceDialog(),
    );
  }

  Future<void> _deactivate() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('反激活此设备'),
        content: const Text(
          '反激活后本机将不能再使用该授权，需要重新激活才能继续下载。'
          '服务器会释放一个设备名额，确定继续吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('反激活'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() {
      _busy = true;
      _message = null;
    });
    final (success, message) = await ref
        .read(licenseNotifierProvider.notifier)
        .deactivateCurrentDevice();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = message;
    });
    if (!success) return;
    // 反激活成功后 isPro 变 false，保留窗口让用户看到试用/激活界面
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

class _DeviceDialog extends ConsumerStatefulWidget {
  const _DeviceDialog();

  @override
  ConsumerState<_DeviceDialog> createState() => _DeviceDialogState();
}

class _DeviceDialogState extends ConsumerState<_DeviceDialog> {
  List<DeviceInfo>? _devices;
  bool _loading = true;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final devices =
        await ref.read(licenseNotifierProvider.notifier).listDevices();
    if (!mounted) return;
    setState(() {
      _devices = devices;
      _loading = false;
      if (devices == null) _message = '无法连接服务器，请检查网络后重试';
    });
  }

  Future<void> _unbind(DeviceInfo device) async {
    final fp = device.deviceFp;
    if (fp == null || fp.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('解绑设备'),
        content: Text('确定解绑「${device.deviceName ?? _short(fp)}」吗？'
            '该设备会释放一个授权名额。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('解绑'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final (success, message) =
        await ref.read(licenseNotifierProvider.notifier).unbindDevice(fp);
    if (!mounted) return;
    setState(() => _message = message);
    if (success) await _load();
  }

  String _short(String fp) =>
      fp.length <= 12 ? fp : '${fp.substring(0, 6)}***${fp.substring(fp.length - 6)}';

  String _date(String? value) {
    if (value == null || value.isEmpty) return '';
    return value.length >= 10 ? value.substring(0, 10) : value;
  }

  @override
  Widget build(BuildContext context) {
    final license = ref.watch(activatedLicenseProvider);
    final maxDevices = license?.payload.maxDevices ?? 4;
    return AlertDialog(
      title: Text('设备管理（${_devices?.length ?? 0}/$maxDevices）'),
      content: SizedBox(
        width: 400,
        height: 280,
        child: _loading
            ? const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : _devices == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_message ?? '设备列表加载失败'),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _load,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _devices!.isEmpty
                            ? const Center(child: Text('暂无绑定设备'))
                            : ListView.separated(
                                itemCount: _devices!.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final device = _devices![index];
                                  final fp = device.deviceFp ?? '';
                                  final current = device.isCurrent == true;
                                  return ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    leading: Icon(
                                      current
                                          ? Icons.laptop_mac
                                          : Icons.devices_other,
                                      size: 18,
                                    ),
                                    title: Text(
                                      device.deviceName?.isNotEmpty == true
                                          ? device.deviceName!
                                          : _short(fp),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      [
                                        if (fp.isNotEmpty) _short(fp),
                                        if (current) '当前设备',
                                        if (_date(device.lastSeen).isNotEmpty)
                                          '最近 ${_date(device.lastSeen)}',
                                      ].join(' · '),
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                    trailing: current || fp.isEmpty
                                        ? null
                                        : TextButton(
                                            onPressed: () => _unbind(device),
                                            child: const Text('解绑'),
                                          ),
                                  );
                                },
                              ),
                      ),
                      if (_message != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          _message!,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ],
                  ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : _load,
          child: const Text('刷新'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
