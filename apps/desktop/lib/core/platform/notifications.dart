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

  static DateTime? _lastShown;

  static Future<void> downloadComplete(String title) =>
      _downloadFinished(title, failed: false);

  static Future<void> downloadFailed(String title) =>
      _downloadFinished(title, failed: true);

  static Future<void> _downloadFinished(
    String title, {
    required bool failed,
  }) async {
    if (!SettingsStorage.instance.current.notifyOnComplete) return;
    // 播放列表/并发下载完成时间很近，节流避免刷屏
    final now = DateTime.now();
    if (_lastShown != null &&
        now.difference(_lastShown!) < const Duration(seconds: 3)) {
      return;
    }
    _lastShown = now;
    final body = _clean(
      title.isEmpty
          ? (failed ? '下载失败' : '下载完成')
          : (failed ? '下载失败：$title' : title),
    );
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
