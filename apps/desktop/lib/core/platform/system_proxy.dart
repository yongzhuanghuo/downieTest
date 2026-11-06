import 'dart:io';

import 'package:flutter/foundation.dart';

/// 读取系统代理。
///
/// WebView / URLSession 会自动走系统代理，但 ffmpeg 子进程不会。
/// 用户自定义提取抓到直链后，下载器需要把同一个代理传给 ffmpeg，
/// 否则在需要代理的网络里会出现 `Connection timed out`。
class SystemProxy {
  SystemProxy._();

  static Future<String?> detect() async {
    if (Platform.isMacOS) return _detectMacOS();
    if (Platform.isWindows) return _detectWindows();
    return null;
  }

  /// 用户显式配置的代理可能是 `127.0.0.1:7897`，补上 scheme。
  static String normalize(String proxy) {
    final value = proxy.trim();
    if (value.isEmpty) return '';
    return value.contains('://') ? value : 'http://$value';
  }

  /// 解析 `scutil --proxy` 输出（纯函数，便于单测）。
  static String? parseScutilProxy(String output) {
    String? value(String key) {
      final match = RegExp('$key\\s*:\\s*(\\S+)').firstMatch(output);
      return match?.group(1);
    }

    if (value('HTTPSEnable') == '1') {
      final host = value('HTTPSProxy');
      final port = value('HTTPSPort');
      if (host != null && port != null) return 'http://$host:$port';
    }
    if (value('HTTPEnable') == '1') {
      final host = value('HTTPProxy');
      final port = value('HTTPPort');
      if (host != null && port != null) return 'http://$host:$port';
    }
    if (value('SOCKSEnable') == '1') {
      final host = value('SOCKSProxy');
      final port = value('SOCKSPort');
      if (host != null && port != null) return 'socks5://$host:$port';
    }
    return null;
  }

  /// 解析 Windows 注册表的 ProxyEnable / ProxyServer（纯函数，便于单测）。
  static String? parseWindowsProxy(
    String enableOutput,
    String serverOutput,
  ) {
    if (!RegExp(r'ProxyEnable\s+REG_DWORD\s+0x1', caseSensitive: false)
        .hasMatch(enableOutput)) {
      return null;
    }
    final match = RegExp(
      r'ProxyServer\s+REG_SZ\s+(.+)',
      caseSensitive: false,
    ).firstMatch(serverOutput);
    final raw = match?.group(1)?.trim() ?? '';
    if (raw.isEmpty) return null;

    // ProxyServer 可能是：
    //   host:port
    //   http=host:port;https=host:port
    //   socks=host:port（Clash 等只开 SOCKS 时）
    // Dart HttpClient 不支持 SOCKS，HLS/分块下载会据此回退 yt-dlp/ffmpeg。
    String? entry(String name) {
      final match = RegExp(
        '(?:^|;)\\s*$name=([^;]+)',
        caseSensitive: false,
      ).firstMatch(raw);
      return match?.group(1)?.trim();
    }

    final https = entry('https');
    final http = entry('http');
    final socks = entry('socks') ?? entry('socks5');
    if (https != null && https.isNotEmpty) {
      return https.contains('://') ? https : 'http://$https';
    }
    if (http != null && http.isNotEmpty) {
      return http.contains('://') ? http : 'http://$http';
    }
    if (socks != null && socks.isNotEmpty) {
      return socks.contains('://') ? socks : 'socks5://$socks';
    }
    final value = raw.trim();
    if (value.isEmpty) return null;
    return value.contains('://') ? value : 'http://$value';
  }

  static Future<String?> _detectMacOS() async {
    try {
      final result = await Process.run('scutil', ['--proxy']);
      if (result.exitCode != 0) return null;
      return parseScutilProxy(result.stdout.toString());
    } catch (e) {
      debugPrint('[代理] 读取 macOS 系统代理失败: $e');
      return null;
    }
  }

  static Future<String?> _detectWindows() async {
    try {
      final enable = await Process.run('reg', [
        'query',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
        '/v',
        'ProxyEnable',
      ]);
      if (enable.exitCode != 0) return null;
      final server = await Process.run('reg', [
        'query',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
        '/v',
        'ProxyServer',
      ]);
      if (server.exitCode != 0) return null;
      return parseWindowsProxy(
        enable.stdout.toString(),
        server.stdout.toString(),
      );
    } catch (e) {
      debugPrint('[代理] 读取 Windows 系统代理失败: $e');
      return null;
    }
  }
}
