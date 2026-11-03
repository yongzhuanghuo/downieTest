import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'device_dialog.dart';
import 'license_provider.dart';
import 'registered_window.dart';
import 'trial_window.dart';

export 'trial_window.dart' show showRecoverLicenseDialog;

/// 统一的「授权」入口：
/// - 已授权 → 感谢注册信息窗
/// - 未授权 → 试用大窗口（可指定直接打开激活表单）
///
/// 激活成功后接着打开已授权窗口，完成 Downie 式的状态切换。
Future<void> showLicenseFlow(
  BuildContext context, {
  bool activation = false,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  if (container.read(isProProvider)) {
    await RegisteredWindow.show(context);
    return;
  }

  final activated = await TrialWindow.show(
    context,
    initialActivation: activation,
  );
  if (activated == true && context.mounted) {
    await RegisteredWindow.show(context);
  }
}

/// 「显示许可证代码…」：已授权直接打开信息窗，未授权回退到试用窗口。
Future<void> showRegisteredLicense(BuildContext context) async {
  final container = ProviderScope.containerOf(context, listen: false);
  if (container.read(isProProvider)) {
    await RegisteredWindow.show(context);
  } else {
    await showLicenseFlow(context);
  }
}

/// 「设备管理…」。
Future<void> openDeviceManagement(BuildContext context) {
  return DeviceDialog.show(context);
}

/// 「停用用户许可证」：确认后真正反激活，并回到试用窗口。
Future<void> confirmAndDeactivateLicense(
  BuildContext context,
  WidgetRef ref,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('停用用户许可证'),
      content: const Text(
        '您确定要取消激活许可证？\n\n'
        '取消激活后，应用将进入试用模式。具体变化将在应用重启后生效。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('停用'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;

  final (success, message) = await ref
      .read(licenseNotifierProvider.notifier)
      .deactivateCurrentDevice();
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(context)
      ?.showSnackBar(SnackBar(content: Text(message)));
  if (success) {
    await showLicenseFlow(context);
  }
}
