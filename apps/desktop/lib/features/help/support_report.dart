import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

import '../../core/storage/settings_storage.dart';
import '../../shared/branding/app_brand.dart';

/// 支持报告内容。与 Downie 的 Support 窗口字段对齐：
/// 邮箱、相关链接、需要账户（站点）、消息、诊断信息。
class SupportReport {
  final String email;
  final String url;
  final String account;
  final String message;
  final String diagnostics;

  const SupportReport({
    required this.email,
    required this.url,
    required this.account,
    required this.message,
    required this.diagnostics,
  });

  String get subject => url.isEmpty
      ? '[${AppBrand.name}] 反馈'
      : '[${AppBrand.name}] 报告链接';

  String get body {
    final buffer = StringBuffer();
    buffer.writeln('联系邮箱：$email');
    if (url.isNotEmpty) buffer.writeln('链接：$url');
    if (account.isNotEmpty) buffer.writeln('需要账户：$account');
    buffer.writeln();
    buffer.writeln('问题描述：');
    buffer.writeln(message.trim().isEmpty ? '（未填写）' : message.trim());
    if (diagnostics.trim().isNotEmpty) {
      buffer.writeln();
      buffer.writeln('--- 诊断信息 ---');
      buffer.writeln(diagnostics.trim());
    }
    return buffer.toString();
  }

  /// 复制给用户粘贴到任意邮箱的完整文本。
  String get clipboardText => '收件人：${AppBrand.supportEmail}\n'
      '主题：$subject\n\n$body';

  Uri get mailtoUri => Uri(
        scheme: 'mailto',
        path: AppBrand.supportEmail,
        queryParameters: {'subject': subject, 'body': body},
      );
}

/// 返回 null 表示合法；否则返回中文错误提示。
String? validateSupportEmail(String value) {
  final email = value.trim();
  if (email.isEmpty) return '请输入邮箱地址';
  if (email.length > 255) return '邮箱地址过长';
  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
    return '邮箱格式不正确';
  }
  return null;
}

SupportReport buildSupportReport({
  required String email,
  String url = '',
  String account = '',
  String message = '',
  String diagnostics = '',
}) {
  return SupportReport(
    email: email.trim(),
    url: url.trim(),
    account: account.trim(),
    message: message,
    diagnostics: diagnostics,
  );
}

/// 收集会随报告发送的诊断信息：版本、系统、最近应用日志。
/// 不包含下载视频内容；日志可能含链接/标题，用户在界面可取消勾选。
Future<String> collectSupportDiagnostics({String? taskId}) async {
  final buffer = StringBuffer();
  try {
    final info = await PackageInfo.fromPlatform();
    buffer.writeln('版本：${info.version} (${info.buildNumber})');
  } catch (_) {
    buffer.writeln('版本：未知');
  }
  buffer.writeln('系统：${Platform.operatingSystem} '
      '${Platform.operatingSystemVersion}');
  buffer.writeln('时间：${DateTime.now().toIso8601String()}');

  try {
    final dir = await SettingsStorage.getStorageDir();
    final logDir = Directory('${dir.path}/logs');
    if (await logDir.exists()) {
      final files = await logDir
          .list()
          .where((e) => e is File && e.path.endsWith('.log'))
          .cast<File>()
          .toList();
      files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      if (files.isNotEmpty) {
        final tail = await _readTail(files.first, maxLines: 120);
        if (tail.isNotEmpty) {
          buffer.writeln();
          buffer.writeln('最近日志（${files.first.path}）：');
          buffer.writeln(tail);
        }
      }
      if (taskId != null && taskId.isNotEmpty) {
        final taskLog = File('${logDir.path}/task_$taskId.log');
        if (await taskLog.exists()) {
          final tail = await _readTail(taskLog, maxLines: 200);
          if (tail.isNotEmpty) {
            buffer.writeln();
            buffer.writeln('任务日志（${taskLog.path}）：');
            buffer.writeln(tail);
          }
        }
      }
    }
  } catch (_) {}

  final text = buffer.toString();
  const maxChars = 20000;
  if (text.length <= maxChars) return text;
  return '${text.substring(0, maxChars)}\n...(诊断信息已截断)';
}

Future<String> _readTail(File file, {required int maxLines}) async {
  try {
    final lines = await file.readAsLines();
    final start = lines.length > maxLines ? lines.length - maxLines : 0;
    return lines.sublist(start).join('\n');
  } catch (_) {
    return '';
  }
}
