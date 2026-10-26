import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../shared/branding/app_brand.dart';
import '../storage/settings_storage.dart';

/// 系统下载完成通知。
///
/// 不引第三方插件：macOS 用 osascript，Windows 用 PowerShell 的
/// NotifyIcon 气泡。失败只写日志，不影响下载主流程。
class SystemNotifications {
  SystemNotifications._();

  static Future<void> downloadComplete(String title) async {
    if (!SettingsStorage.instance.current.notifyOnComplete) return;
    final body = _clean(title.isEmpty ? '下载完成' : title);
    try {
      if (Platform.isMacOS) {
        final script = 'display notification "${_appleScript(body)}" '
            'with title "${_appleScript(AppBrand.name)}"';
        await Process.run('osascript', ['-e', script]);
      } else if (Platform.isWindows) {
        final script = _windowsScript(body);
        await Process.run(
          'powershell',
          [
            '-NoProfile',
            '-NonInteractive',
            '-WindowStyle',
            'Hidden',
            '-Command',
            script,
          ],
        );
      }
    } catch (e) {
      debugPrint('[通知] 发送失败: $e');
    }
  }

  static String _clean(String text) {
    final oneLine = text.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    return oneLine.length <= 180 ? oneLine : '${oneLine.substring(0, 177)}...';
  }

  static String _appleScript(String text) {
    return text.replaceAll('\\', r'\\').replaceAll('"', r'\"');
  }

  static String _windowsScript(String text) {
    final safe = text.replaceAll("'", "''");
    return r'''
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$n = New-Object System.Windows.Forms.NotifyIcon
$n.Icon = [System.Drawing.SystemIcons]::Information
$n.Visible = $true
$n.ShowBalloonTip(4000, 'APP_NAME', 'BODY', 'Info')
Start-Sleep -Seconds 5
$n.Dispose()
'''
        .replaceAll('APP_NAME', AppBrand.name.replaceAll("'", "''"))
        .replaceAll('BODY', safe);
  }
}
