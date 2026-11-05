// ignore_for_file: avoid_print, avoid_relative_lib_imports
//
// 多连接 Range 下载器自测（纯 Dart，不依赖 Flutter）：
//   dart tools/chunked_downloader_selftest.dart
//
// 启动本地 HTTP 服务器，验证：
// 1. 4 连接确实并发（服务端观测到的最大并发 > 1）
// 2. 下载内容与源数据逐字节一致
// 3. 服务器不支持 Range 时抛 RangeNotSupportedException
// 4. 取消能及时中断
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../lib/core/engine/chunked_http_downloader.dart';

Future<void> main(List<String> args) async {
  if (args.isNotEmpty) {
    await _realWorld(args.first);
    return;
  }
  final failures = <String>[];
  final server = await _startServer();
  final base = 'http://${server.address.address}:${server.port}';
  final out = File(
    '${Directory.systemTemp.path}/chunked-selftest-${DateTime.now().microsecondsSinceEpoch}.bin',
  );

  try {
    // 1. 正常分块下载
    var maxSeen = 0;
    var lastProgress = 0;
    final bytes = await ChunkedHttpDownloader.download(
      url: '$base/range',
      outputPath: out.path,
      connections: 4,
      chunkSizeBytes: 256 * 1024,
      onProgress: (downloaded, total, speed) {
        lastProgress = downloaded;
      },
    );
    maxSeen = _serverMaxConcurrent;
    final written = await out.readAsBytes();
    if (bytes != _source.length) {
      failures.add('字节数不一致：returns=$bytes source=${_source.length}');
    }
    if (written.length != _source.length) {
      failures.add('文件大小不一致：${written.length} vs ${_source.length}');
    } else {
      for (var i = 0; i < _source.length; i++) {
        if (written[i] != _source[i]) {
          failures.add('内容在偏移 $i 不一致');
          break;
        }
      }
    }
    if (lastProgress != _source.length) {
      failures.add('进度未到 100%：$lastProgress');
    }
    if (maxSeen < 2) {
      failures.add('没有观察到并发连接（max=$maxSeen）');
    }
    print('[ok] 分块下载：${written.length} 字节，服务端最大并发=$maxSeen');

    // 2. 不支持 Range
    _serverMaxConcurrent = 0;
    try {
      await ChunkedHttpDownloader.download(
        url: '$base/norange',
        outputPath: '${out.path}.norange',
        connections: 4,
      );
      failures.add('不支持 Range 时没有抛异常');
    } on RangeNotSupportedException {
      print('[ok] 不支持 Range 时正确回退');
    }

    // 3. 自定义请求头透传
    final authOut = '${out.path}.auth';
    try {
      await ChunkedHttpDownloader.download(
        url: '$base/auth',
        outputPath: authOut,
        headers: {
          'X-Test': 'ok',
          'Referer': 'https://example.com/page',
          'Cookie': 'a=1; b=2',
        },
        connections: 2,
        chunkSizeBytes: 512 * 1024,
      );
      final authBytes = await File(authOut).readAsBytes();
      if (authBytes.length != _source.length) {
        failures.add('带请求头下载大小不一致');
      } else {
        print('[ok] 自定义请求头透传');
      }
    } on ChunkedDownloadException catch (e) {
      failures.add('自定义请求头下载失败：${e.message}');
    } finally {
      final f = File(authOut);
      if (await f.exists()) await f.delete();
    }

    // 4. 取消
    _serverMaxConcurrent = 0;
    final cancelledOut = '${out.path}.cancelled';
    var cancel = false;
    final cancelWatch = Timer(const Duration(milliseconds: 150), () {
      cancel = true;
    });
    try {
      await ChunkedHttpDownloader.download(
        url: '$base/slow',
        outputPath: cancelledOut,
        connections: 4,
        chunkSizeBytes: 256 * 1024,
        shouldCancel: () => cancel,
      );
      failures.add('取消后仍完成了下载');
    } on DownloadCancelledException {
      print('[ok] 取消能中断下载');
    } finally {
      cancelWatch.cancel();
      final f = File(cancelledOut);
      if (await f.exists()) await f.delete();
    }
  } finally {
    if (await out.exists()) await out.delete();
    await server.close(force: true);
  }

  if (failures.isEmpty) {
    print('\n全部自测通过');
  } else {
    print('\n失败：');
    for (final f in failures) {
      print(' - $f');
    }
    exitCode = 1;
  }
}

/// 用真实 URL 跑一次，打印耗时和平均速度（用于和单连接对比）。
Future<void> _realWorld(String url) async {
  final out = File(
    '${Directory.systemTemp.path}/chunked-realworld-${DateTime.now().microsecondsSinceEpoch}.bin',
  );
  final sw = Stopwatch()..start();
  try {
    final bytes = await ChunkedHttpDownloader.download(
      url: url,
      outputPath: out.path,
      connections: 4,
      chunkSizeBytes: 2 * 1024 * 1024,
      onProgress: (downloaded, total, speed) {
        if (total != null && downloaded < total) {
          stdout.write(
            '\r${(downloaded / total * 100).toStringAsFixed(1)}% '
            '${(speed / 1024 / 1024).toStringAsFixed(2)} MiB/s',
          );
        }
      },
    );
    sw.stop();
    final mib = bytes / 1024 / 1024;
    final secs = sw.elapsedMilliseconds / 1000;
    stdout.writeln(
      '\n[ok] $url -> $bytes 字节，${secs.toStringAsFixed(1)}s，'
      '平均 ${(mib / secs).toStringAsFixed(2)} MiB/s',
    );
  } finally {
    if (await out.exists()) await out.delete();
  }
}

final Uint8List _source = Uint8List.fromList(
  List<int>.generate(4 * 1024 * 1024 + 123, (i) => (i * 31 + 7) % 251),
);
var _serverMaxConcurrent = 0;

Future<HttpServer> _startServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var active = 0;
  server.listen((req) async {
    var counted = false;
    try {
      if (req.uri.path == '/norange') {
        if (req.method == 'HEAD') {
          req.response.contentLength = _source.length;
          await req.response.close();
          return;
        }
        req.response.headers.contentLength = _source.length;
        req.response.add(_source);
        await req.response.close();
        return;
      }
      if (req.uri.path == '/auth' &&
          (req.headers.value('x-test') != 'ok' ||
              req.headers.value('referer') != 'https://example.com/page' ||
              req.headers.value('cookie') != 'a=1; b=2')) {
        req.response.statusCode = HttpStatus.forbidden;
        await req.response.close();
        return;
      }

      final slow = req.uri.path == '/slow';
      final range = req.headers.value(HttpHeaders.rangeHeader);
      final match = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(range ?? '');
      if (match == null) {
        req.response.statusCode = HttpStatus.badRequest;
        await req.response.close();
        return;
      }
      final start = int.parse(match.group(1)!);
      final end = math.min(int.parse(match.group(2)!), _source.length - 1);
      active++;
      counted = true;
      _serverMaxConcurrent = math.max(_serverMaxConcurrent, active);
      // 模拟网络延迟，确保并发请求在服务端有重叠窗口。
      await Future<void>.delayed(const Duration(milliseconds: 30));

      req.response.statusCode = HttpStatus.partialContent;
      req.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/${_source.length}',
      );
      req.response.headers.contentLength = end - start + 1;

      const piece = 64 * 1024;
      for (var offset = start; offset <= end; offset += piece) {
        final stop = math.min(offset + piece, end + 1);
        req.response.add(_source.sublist(offset, stop));
        await req.response.flush();
        if (slow) {
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
      }
      await req.response.close();
    } catch (_) {
      // 客户端取消时会断开连接，忽略。
    } finally {
      if (counted) active--;
    }
  });
  return server;
}
