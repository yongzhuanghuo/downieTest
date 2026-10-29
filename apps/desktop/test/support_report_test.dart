import 'dart:convert';
import 'dart:io';

import 'package:downie_test/features/help/support_report.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('email validation', () {
    expect(validateSupportEmail(''), isNotNull);
    expect(validateSupportEmail('not-an-email'), isNotNull);
    expect(validateSupportEmail('a@b'), isNotNull);
    expect(validateSupportEmail('buyer@example.com'), isNull);
  });

  test('link report includes all fields', () {
    final report = buildSupportReport(
      email: 'buyer@example.com',
      url: 'https://youtu.be/PHkxkeeoLyw',
      account: 'YouTube',
      message: '无效的配置',
      diagnostics: '版本：2.0.33\n系统：macOS',
    );
    expect(report.subject, contains('报告链接'));
    expect(report.body, contains('buyer@example.com'));
    expect(report.body, contains('https://youtu.be/PHkxkeeoLyw'));
    expect(report.body, contains('需要账户：YouTube'));
    expect(report.body, contains('无效的配置'));
    expect(report.body, contains('--- 诊断信息 ---'));
    expect(report.body, contains('版本：2.0.33'));
  });

  test('general report omits empty link/account and diagnostics', () {
    final report = buildSupportReport(
      email: 'buyer@example.com',
      message: '建议',
    );
    expect(report.subject, contains('反馈'));
    expect(report.body, isNot(contains('链接：')));
    expect(report.body, isNot(contains('需要账户：')));
    expect(report.body, isNot(contains('--- 诊断信息 ---')));
  });

  test('mailto URI encodes subject and body', () {
    final report = buildSupportReport(
      email: 'buyer@example.com',
      url: 'https://example.com/watch?v=1&t=2',
      message: '中文 & 特殊字符',
    );
    final uri = report.mailtoUri;
    expect(uri.scheme, 'mailto');
    expect(uri.path, 'huoyongzhuang@qq.com');
    expect(uri.queryParameters['subject'], report.subject);
    expect(uri.queryParameters['body'], report.body);
    expect(uri.toString(), contains('%26'));
  });

  test('clipboard text has recipient and subject', () {
    final report = buildSupportReport(
      email: 'buyer@example.com',
      message: 'hello',
    );
    expect(report.clipboardText, contains('收件人：huoyongzhuang@qq.com'));
    expect(report.clipboardText, contains('主题：'));
    expect(report.clipboardText, contains('hello'));
  });

  test('server payload keeps all form fields', () {
    final report = buildSupportReport(
      email: 'buyer@example.com',
      url: 'https://youtu.be/PHkxkeeoLyw',
      account: 'YouTube',
      message: '无效的配置',
      diagnostics: '版本：2.0.33',
    );
    expect(report.toJson(), {
      'email': 'buyer@example.com',
      'url': 'https://youtu.be/PHkxkeeoLyw',
      'account': 'YouTube',
      'message': '无效的配置',
      'diagnostics': '版本：2.0.33',
    });
  });

  test('sendSupportReport posts to server and parses success', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response.bytes(
        utf8.encode(jsonEncode({'ok': true, 'message': '已发送'})),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final report = buildSupportReport(
      email: 'buyer@example.com',
      url: 'https://youtu.be/PHkxkeeoLyw',
      message: '无效的配置',
    );
    final result = await sendSupportReport(report, client: client);
    expect(result.ok, isTrue);
    expect(result.message, '已发送');
    expect(captured.url.path, '/api/support/report');
    expect(captured.method, 'POST');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['email'], 'buyer@example.com');
    expect(body['platform'], Platform.operatingSystem);
  });

  test('sendSupportReport surfaces server failure message', () async {
    final client = MockClient(
      (_) async => http.Response.bytes(
        utf8.encode(jsonEncode({
          'ok': false,
          'error': 'MAIL_NOT_CONFIGURED',
          'message': '服务端未配置支持邮箱',
        })),
        503,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    final result = await sendSupportReport(
      buildSupportReport(email: 'buyer@example.com', message: 'hello'),
      client: client,
    );
    expect(result.ok, isFalse);
    expect(result.message, contains('未配置支持邮箱'));
  });
}
