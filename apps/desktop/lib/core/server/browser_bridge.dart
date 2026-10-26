import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../storage/settings_storage.dart';

/// 本机浏览器接收端口。
///
/// 浏览器扩展/书签把当前页面 URL 发到 `127.0.0.1:8765/add`，应用复用正常
/// 解析流程并加入队列。只监听回环地址，并用随机 token 防止网页随意调用。
class BrowserBridge {
  BrowserBridge._();
  static final instance = BrowserBridge._();

  static const int defaultPort = 8765;

  HttpServer? _server;
  String _token = '';
  int _port = defaultPort;
  Future<bool> Function(String url)? _onUrl;

  bool get isRunning => _server != null;
  int get port => _port;

  static String generateToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// 启动或复用服务；token/端口变化时重启。
  Future<bool> start({
    required String token,
    required Future<bool> Function(String url) onUrl,
    int port = defaultPort,
  }) async {
    if (_server != null && _token == token && _port == port) {
      _onUrl = onUrl;
      return true;
    }
    await stop();
    _token = token;
    _port = port;
    _onUrl = onUrl;
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
      _port = _server!.port;
      _server!.listen(_handle);
      debugPrint('[浏览器接收] 已监听 127.0.0.1:$_port');
      return true;
    } catch (e) {
      debugPrint('[浏览器接收] 启动失败: $e');
      _server = null;
      return false;
    }
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    if (server != null) {
      await server.close(force: true);
      debugPrint('[浏览器接收] 已停止');
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set('Access-Control-Allow-Methods', 'GET, OPTIONS');
    response.headers.set('Cache-Control', 'no-store');

    try {
      if (request.method == 'OPTIONS') {
        response.statusCode = HttpStatus.noContent;
        await response.close();
        return;
      }
      if (request.method != 'GET') {
        await _text(response, HttpStatus.methodNotAllowed, '只接受 GET');
        return;
      }

      final uri = request.uri;
      if (uri.path == '/ping') {
        await _text(response, HttpStatus.ok, 'Downie6');
        return;
      }
      if (uri.path != '/add') {
        await _text(response, HttpStatus.notFound, 'Not Found');
        return;
      }

      final token = uri.queryParameters['token'] ?? '';
      if (_token.isEmpty || token != _token) {
        await _text(response, HttpStatus.forbidden, 'token 无效');
        return;
      }
      final url = uri.queryParameters['url']?.trim() ?? '';
      if (!_isHttpUrl(url)) {
        await _text(response, HttpStatus.badRequest, '缺少有效的 http(s) 链接');
        return;
      }

      final handler = _onUrl;
      if (handler == null) {
        await _text(response, HttpStatus.serviceUnavailable, '应用尚未就绪');
        return;
      }
      final ok = await handler(url);
      final message = ok ? '已加入下载队列：$url' : '解析失败或试用已结束';
      if (uri.queryParameters['response'] == 'html') {
        await _html(
          response,
          ok ? HttpStatus.ok : HttpStatus.unprocessableEntity,
          message,
          autoClose: ok,
        );
      } else {
        await _text(
          response,
          ok ? HttpStatus.ok : HttpStatus.unprocessableEntity,
          message,
        );
      }
    } catch (e) {
      debugPrint('[浏览器接收] 处理失败: $e');
      try {
        await _text(response, HttpStatus.internalServerError, '处理失败');
      } catch (_) {}
    }
  }

  static bool _isHttpUrl(String url) {
    if (url.length > 4096) return false;
    final uri = Uri.tryParse(url);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  static Future<void> _text(
    HttpResponse response,
    int status,
    String message,
  ) async {
    response.statusCode = status;
    response.headers.contentType = ContentType.text;
    response.write(message);
    await response.close();
  }

  static Future<void> _html(
    HttpResponse response,
    int status,
    String message, {
    required bool autoClose,
  }) async {
    response.statusCode = status;
    response.headers.contentType = ContentType.html;
    final safe = const HtmlEscape().convert(message);
    response.write('''<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8">
<title>Downie6</title>
<style>
body{margin:0;padding:18px;font:14px/1.5 -apple-system,"Segoe UI","PingFang SC",sans-serif;
background:#1e1e1e;color:#f5f5f5}
p{word-break:break-all}
</style></head><body>
<p>$safe</p>
${autoClose ? '<script>setTimeout(function(){window.close()},1200)</script>' : ''}
</body></html>''');
    await response.close();
  }

  /// 把内置浏览器扩展写到应用数据目录，返回目录路径。
  ///
  /// 打包后资源在 assets 里，不能直接让浏览器加载；复制出来再
  /// 在 Chrome/Edge 里「加载已解压的扩展程序」。
  static Future<String> exportExtension() async {
    final base = await SettingsStorage.getStorageDir();
    final dir = Directory('${base.path}/browser-extension');
    await dir.create(recursive: true);
    const files = ['manifest.json', 'popup.html', 'popup.js'];
    for (final name in files) {
      final content = await rootBundle.loadString('browser-extension/$name');
      await File('${dir.path}/$name').writeAsString(content);
    }
    return dir.path;
  }

  /// 给设置页展示的书签脚本：把当前页 URL 发给应用。
  static String bookmarklet({required String token, int port = defaultPort}) {
    final base = 'http://127.0.0.1:$port/add';
    // 用新窗口而不是 location.href，避免把原视频页面替换成结果页
    return "javascript:(function(){window.open('$base?url='"
        "+encodeURIComponent(location.href)"
        "+'&token=${Uri.encodeQueryComponent(token)}&response=html',"
        "'downie6','width=420,height=180')})()";
  }
}
