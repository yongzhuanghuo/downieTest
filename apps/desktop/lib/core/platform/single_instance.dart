import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 单实例与命令行转发。
///
/// Windows 通过 downie6:// 协议启动时，如果应用已在运行，新进程会把命令行
/// 参数发给已有实例后退出，避免两个实例同时写 SQLite/Hive。
/// macOS 正常由系统保证单实例，这里也不会造成冲突。
class SingleInstance {
  SingleInstance._();

  static const int port = 47653;
  static const String _appTag = 'downie6-ipc-v1';

  static ServerSocket? _server;
  // 单订阅控制器会缓冲监听前到达的事件（主实例启动早期可能收到转发）。
  static final StreamController<List<String>> _incoming =
      StreamController<List<String>>();

  /// 已有实例转发的命令行参数。
  static Stream<List<String>> get incoming => _incoming.stream;

  /// 返回 true：参数已转交给已有实例，本进程应退出。
  /// 返回 false：本进程是主实例（或无法建立 IPC，继续正常启动）。
  static Future<bool> claim(List<String> args) async {
    if (!Platform.isWindows) return false;

    // 正常启动时端口未监听，connect 会立刻失败，不会拖慢启动。
    if (await _tryForward(args)) return true;

    try {
      _server = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        port,
        shared: false,
      );
      _server!.listen(_handleSocket, onError: (_) {});
      return false;
    } on SocketException {
      // 端口被占用：可能是另一实例刚绑定，稍等后重试转发。
    }

    for (var attempt = 0; attempt < 8; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (await _tryForward(args)) return true;
    }
    debugPrint('[单实例] 端口 $port 被占用但无法转发，继续启动');
    return false;
  }

  static Future<bool> _tryForward(List<String> args) async {
    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(milliseconds: 300),
      );
      socket.write('${jsonEncode({'app': _appTag, 'args': args})}\n');
      await socket.flush();

      final reply = await socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .first
          .timeout(const Duration(milliseconds: 800));
      socket.destroy();
      return reply.contains('OK');
    } catch (_) {
      return false;
    }
  }

  static void _handleSocket(Socket socket) {
    final buffer = StringBuffer();
    socket.listen(
      (data) {
        buffer.write(utf8.decode(data, allowMalformed: true));
        final text = buffer.toString();
        if (!text.contains('\n')) return;
        final line = text.split('\n').first;
        try {
          final decoded = jsonDecode(line);
          if (decoded is Map && decoded['app'] == _appTag) {
            final args = (decoded['args'] as List?)
                    ?.whereType<String>()
                    .toList() ??
                const <String>[];
            if (args.isNotEmpty) _incoming.add(args);
            socket.write('OK\n');
            unawaited(socket.flush().then((_) => socket.destroy()));
            return;
          }
        } catch (_) {}
        socket.write('NO\n');
        unawaited(socket.flush().then((_) => socket.destroy()));
      },
      onError: (_) => socket.destroy(),
      cancelOnError: true,
    );
  }

}
