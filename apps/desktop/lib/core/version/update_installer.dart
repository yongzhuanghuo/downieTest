import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

/// 应用内更新：下载完整安装包并就地替换，然后重启。
///
/// macOS：下载 DMG → 挂载 → 复制 .app 到临时目录 → 退出后脚本替换当前 app → open
/// Windows：下载 EXE → 静默运行 Inno Setup → 安装器启动新版本
class UpdateInstaller {
  UpdateInstaller._();

  static Future<File> download(
    String url, {
    void Function(int received, int total)? onProgress,
    String expectedSha256 = '',
  }) async {
    final dir = await Directory.systemTemp.createTemp('downie6-update-');
    final name = Uri.parse(url).pathSegments.isEmpty
        ? 'update.bin'
        : Uri.parse(url).pathSegments.last;
    final file = File(p.join(dir.path, name));
    final client = http.Client();
    final digestSink = _DigestSink();
    final hasher = sha256.startChunkedConversion(digestSink);
    try {
      final response = await client.send(http.Request('GET', Uri.parse(url)));
      if (response.statusCode != 200) {
        throw Exception('下载失败：HTTP ${response.statusCode}');
      }
      final total = response.contentLength ?? 0;
      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in response.stream) {
        sink.add(chunk);
        hasher.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
      await sink.close();
      hasher.close();

      final expected = expectedSha256.trim().toLowerCase();
      final actual = digestSink.value?.toString() ?? '';
      if (expected.isNotEmpty && actual != expected) {
        await file.delete().catchError((_) => file);
        throw Exception('安装包校验失败：SHA-256 不匹配，已取消安装');
      }
      return file;
    } finally {
      client.close();
    }
  }

  static Future<void> installMacOS(
    File dmg, {
    void Function(String status)? onStatus,
  }) async {
    if (!Platform.isMacOS) {
      throw Exception('当前平台不是 macOS');
    }
    final mount = await Directory.systemTemp.createTemp('downie6-mount-');
    final attach = await Process.run('hdiutil', [
      'attach',
      '-nobrowse',
      '-readonly',
      '-mountpoint',
      mount.path,
      dmg.path,
    ]);
    if (attach.exitCode != 0) {
      throw Exception('挂载 DMG 失败：${attach.stderr}');
    }

    Directory? appDir;
    try {
      onStatus?.call('正在准备安装…');
      for (final entry in Directory(mount.path).listSync()) {
        if (entry is Directory && entry.path.endsWith('.app')) {
          appDir = entry;
          break;
        }
      }
      if (appDir == null) {
        throw Exception('安装包里没有找到 .app');
      }

      final staging = await Directory.systemTemp.createTemp('downie6-app-');
      final stagedApp = p.join(staging.path, p.basename(appDir.path));
      final copy = await Process.run('ditto', [appDir.path, stagedApp]);
      if (copy.exitCode != 0) {
        throw Exception('复制应用失败：${copy.stderr}');
      }
      await Process.run('xattr', ['-dr', 'com.apple.quarantine', stagedApp]);

      final appPath = _currentAppBundlePath();
      final parent = Directory(p.dirname(appPath));
      final writable = await Process.run('/bin/test', ['-w', parent.path]);
      if (writable.exitCode != 0) {
        throw Exception('没有写入权限，请把应用放到「应用程序」目录后再更新');
      }

      final script = File(p.join(staging.path, 'install-update.sh'));
      await script.writeAsString('''#!/bin/sh
set -e
APP="\$1"
NEW="\$2"
PID="\$3"
while kill -0 "\$PID" 2>/dev/null; do sleep 0.5; done
TMP="\$APP.new"
rm -rf "\$TMP"
ditto "\$NEW" "\$TMP"
rm -rf "\$APP"
mv "\$TMP" "\$APP"
xattr -dr com.apple.quarantine "\$APP" 2>/dev/null || true
open "\$APP"
''');

      // 先卸载 DMG，再启动脱离应用的替换脚本
      await Process.run('hdiutil', ['detach', mount.path, '-force']);
      onStatus?.call('安装完成，正在重启…');
      await Process.start('/bin/sh', [
        script.path,
        appPath,
        stagedApp,
        pid.toString(),
      ], mode: ProcessStartMode.detached);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      exit(0);
    } finally {
      // 如果还没 detach（异常路径），尽量卸载
      await Process.run('hdiutil', ['detach', mount.path, '-force']);
    }
  }

  static Future<void> installWindows(
    File installer, {
    void Function(String status)? onStatus,
  }) async {
    if (!Platform.isWindows) {
      throw Exception('当前平台不是 Windows');
    }
    onStatus?.call('正在启动安装程序…');
    await Process.start(installer.path, const [
      '/VERYSILENT',
      '/SUPPRESSMSGBOXES',
      '/NORESTART',
      '/CLOSEAPPLICATIONS',
    ], mode: ProcessStartMode.detached);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    exit(0);
  }

  static String _currentAppBundlePath() {
    final exe = Platform.resolvedExecutable;
    // .../Downie6.app/Contents/MacOS/<exe>
    final macos = Directory(p.dirname(exe));
    final contents = macos.parent;
    return contents.parent.path;
  }
}
