import 'dart:io';

import 'package:flutter/foundation.dart';

/// 开机自启动。
///
/// - macOS：写 `~/Library/LaunchAgents/com.downie6.desktop.plist`
/// - Windows：写 HKCU Run 注册表项
///
/// 失败返回 false，由设置页保持开关原状态。
class AutoStart {
  AutoStart._();

  static const _macLabel = 'com.downie6.desktop';

  static Future<bool> setEnabled(bool enabled) async {
    try {
      if (Platform.isMacOS) return _setMac(enabled);
      if (Platform.isWindows) return _setWindows(enabled);
      return false;
    } catch (e) {
      debugPrint('[自启动] 设置失败: $e');
      return false;
    }
  }

  static Future<bool> _setMac(bool enabled) async {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) return false;
    final dir = Directory('$home/Library/LaunchAgents');
    final file = File('${dir.path}/$_macLabel.plist');
    final exe = Platform.resolvedExecutable;

    if (!enabled) {
      if (await file.exists()) {
        await Process.run('launchctl', ['unload', file.path]);
        await file.delete();
      }
      return true;
    }

    await dir.create(recursive: true);
    // 打包态优先用 open -a 启动 .app，LaunchServices 才能正确激活窗口。
    final appBundle = File(exe).parent.parent.parent;
    final args = appBundle.path.endsWith('.app')
        ? ['/usr/bin/open', '-a', appBundle.path]
        : [exe];
    final argXml = args
        .map((arg) => '<string>${_xmlEscape(arg)}</string>')
        .join();
    final plist = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$_macLabel</string>
  <key>ProgramArguments</key>
  <array>$argXml</array>
  <key>RunAtLoad</key><true/>
</dict>
</plist>
''';
    await file.writeAsString(plist);
    // 已加载时先卸载，保证新路径生效
    await Process.run('launchctl', ['unload', file.path]);
    final result = await Process.run('launchctl', ['load', file.path]);
    if (result.exitCode != 0) {
      debugPrint('[自启动] launchctl load 失败: ${result.stderr}');
      return false;
    }
    return true;
  }

  static Future<bool> _setWindows(bool enabled) async {
    final exe = Platform.resolvedExecutable;
    final key = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
    if (!enabled) {
      await Process.run(
        'reg',
        ['delete', key, '/v', 'Downie6', '/f'],
      );
      // 本来就不存在时 reg 返回非 0，视为成功
      return true;
    }
    final result = await Process.run(
      'reg',
      ['add', key, '/v', 'Downie6', '/t', 'REG_SZ', '/d', '"$exe"', '/f'],
    );
    if (result.exitCode != 0) {
      debugPrint('[自启动] 写入注册表失败: ${result.stderr}');
      return false;
    }
    return true;
  }

  static String _xmlEscape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
