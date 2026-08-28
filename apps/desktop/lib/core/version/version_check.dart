import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/routes/navigator_key.dart';

/// 后端 API 基础地址（与 license_client 同源，独立声明避免动授权契约）
const String _kApiBase = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'http://127.0.0.1:3000',
);

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
      .get(Uri.parse('$_kApiBase/api/version/latest?platform=$platform'))
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

/// 弹「发现新版本」对话框，引导用户打开浏览器下载安装。
Future<void> showUpdateDialog(UpdateInfo info) async {
  final ctx = rootNavigatorKey.currentContext;
  if (ctx == null) return;

  await showDialog<void>(
    context: ctx,
    barrierDismissible: !info.force,
    builder: (dialogCtx) => AlertDialog(
      title: Text('发现新版本 v${info.version}'),
      content: Text(info.changelog.isEmpty ? '点击下方按钮前往下载最新版。' : info.changelog),
      actions: [
        if (!info.force)
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('稍后'),
          ),
        FilledButton(
          onPressed: () async {
            Navigator.of(dialogCtx).pop();
            final uri = Uri.parse(info.url);
            if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
              debugPrint('[更新] 打开下载链接失败: ${info.url}');
            }
          },
          child: const Text('立即更新'),
        ),
      ],
    ),
  );
}
