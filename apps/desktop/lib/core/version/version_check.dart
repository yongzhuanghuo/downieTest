import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/routes/navigator_key.dart';
import '../api/api_base.dart';
import 'update_installer.dart';

/// 新版本信息（服务端 /api/version/latest 返回）
class UpdateInfo {
  final String version;
  final String url;
  final String changelog;
  final bool force;

  const UpdateInfo({
    required this.version,
    required this.url,
    required this.changelog,
    required this.force,
  });
}

/// 检查服务端有无新版本。返回 null = 已是最新；返回 UpdateInfo = 有新版本。
///
/// 对比 build 号（pubspec 的 `+N`），不做语义化版本对比。
Future<UpdateInfo?> checkForUpdate() async {
  final info = await PackageInfo.fromPlatform();
  final localBuild = int.tryParse(info.buildNumber) ?? 0;
  final platform = Platform.isMacOS ? 'macos' : 'windows';

  final resp = await http
      .get(Uri.parse('$kApiBase/api/version/latest?platform=$platform'))
      .timeout(const Duration(seconds: 15));
  if (resp.statusCode != 200) return null;
  final j = jsonDecode(resp.body) as Map<String, dynamic>;

  final latestBuild = (j['build'] as num?)?.toInt() ?? 0;
  final url = (j['url'] as String?) ?? '';
  if (latestBuild <= localBuild || url.isEmpty) return null;

  return UpdateInfo(
    version: (j['version'] as String?) ?? '',
    url: url,
    changelog: (j['changelog'] as String?) ?? '',
    force: (j['force'] as bool?) ?? false,
  );
}

/// 全局新版本状态：非 null = 有新版（侧边栏更新图标显示红点）。
/// 启动自动检查和侧边栏手动点击都会写入这里。
final updateInfoProvider = StateProvider<UpdateInfo?>((ref) => null);

/// 检查一次更新并把结果写入 [updateInfoProvider]。返回 true = 发现新版本。
/// 网络失败会抛异常，由调用方决定静默还是提示。
Future<bool> refreshUpdateState(WidgetRef ref) async {
  final info = await checkForUpdate();
  ref.read(updateInfoProvider.notifier).state = info;
  return info != null;
}

/// 弹「发现新版本」窗口：应用内下载、安装并重启。
Future<void> showUpdateDialog(UpdateInfo info) async {
  final ctx = rootNavigatorKey.currentContext;
  if (ctx == null) return;

  await showDialog<void>(
    context: ctx,
    barrierDismissible: !info.force,
    builder: (_) => _UpdateDialog(info: info),
  );
}

class _UpdateDialog extends StatefulWidget {
  final UpdateInfo info;

  const _UpdateDialog({required this.info});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _installing = false;
  double? _progress;
  String _status = '';
  String? _error;

  Future<void> _install() async {
    if (_installing) return;
    setState(() {
      _installing = true;
      _error = null;
      _progress = null;
      _status = '正在下载…';
    });
    try {
      final file = await UpdateInstaller.download(
        widget.info.url,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _progress = total > 0 ? received / total : null;
            _status = total > 0
                ? '正在下载 ${_formatBytes(received)} / ${_formatBytes(total)}'
                : '正在下载 ${_formatBytes(received)}';
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _progress = null;
        _status = '下载完成，正在安装…';
      });
      if (Platform.isMacOS) {
        await UpdateInstaller.installMacOS(
          file,
          onStatus: (status) {
            if (mounted) setState(() => _status = status);
          },
        );
      } else {
        await UpdateInstaller.installWindows(
          file,
          onStatus: (status) {
            if (mounted) setState(() => _status = status);
          },
        );
      }
    } catch (e) {
      debugPrint('[更新] 安装失败: $e');
      if (mounted) {
        setState(() {
          _installing = false;
          _error = '$e';
          _status = '';
        });
      }
    }
  }

  Future<void> _openBrowser() async {
    final uri = Uri.parse(widget.info.url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      debugPrint('[更新] 打开下载链接失败: ${widget.info.url}');
    }
  }

  String _formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB'];
    double value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(unit == 0 ? 0 : 1)}${units[unit]}';
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    return AlertDialog(
      title: Text('发现新版本 v${info.version}'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(info.changelog.isEmpty ? '有新版本可用。' : info.changelog),
            if (_installing) ...[
              const SizedBox(height: 20),
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 8),
              Text(_status, style: const TextStyle(fontSize: 12)),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                '应用内更新失败：$_error',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 4),
              const Text(
                '可以改用浏览器下载安装包。',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!info.force)
          TextButton(
            onPressed: _installing ? null : () => Navigator.of(context).pop(),
            child: const Text('稍后'),
          ),
        TextButton(
          onPressed: _installing ? null : _openBrowser,
          child: const Text('浏览器下载'),
        ),
        FilledButton(
          onPressed: _installing ? null : _install,
          child: Text(_installing ? '正在更新…' : '下载并安装'),
        ),
      ],
    );
  }
}
