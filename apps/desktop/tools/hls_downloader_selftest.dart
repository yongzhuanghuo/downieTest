// ignore_for_file: avoid_print, avoid_relative_lib_imports
//
// HLS 下载器自测（纯 Dart，不依赖 Flutter）：
//   dart tools/hls_downloader_selftest.dart
// 可选指定 ffmpeg：FFMPEG=/path/to/ffmpeg dart tools/hls_downloader_selftest.dart
//
// 流程：用 ffmpeg 现场生成一份 AES-128 加密的 HLS（10 个分片），
// 起本地 HTTP 服务，跑 HlsDownloader 并发下载，再用 ffmpeg 本地解密合并，
// 校验时长/音视频轨/并发数/取消。
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import '../lib/core/engine/hls_downloader.dart';

Future<void> main(List<String> args) async {
  if (args.isNotEmpty) {
    await _realWorld(args.first);
    return;
  }
  final ffmpeg = _findFfmpeg();
  if (ffmpeg == null) {
    print('[skip] 未找到 ffmpeg；设置 FFMPEG=/path/to/ffmpeg 后重试');
    return;
  }

  final failures = <String>[];
  final dir = await Directory.systemTemp.createTemp('hls-selftest-');
  HttpServer? server;
  HlsDownloadResult? result;
  try {
    final prepared = await _prepareFixture(ffmpeg, dir);
    if (!prepared) {
      failures.add('ffmpeg 生成测试 HLS 失败');
    } else {
      var maxConcurrent = 0;
      server = await _serve(dir, (active) {
        maxConcurrent = math.max(maxConcurrent, active);
      });
      final url = 'http://127.0.0.1:${server.port}/index.m3u8';

      result = await HlsDownloader.download(
        url: url,
        connections: 8,
        headers: {'User-Agent': 'hls-selftest', 'Referer': 'https://example.com/'},
        onProgress: (done, total, bytes, speed) {},
      );
      final expected = _segmentCount(dir);
      if (result.segments != expected) {
        failures.add('分片数不一致：${result.segments} vs $expected');
      }
      if (result.bytes <= 0) failures.add('下载字节数为 0');
      if (maxConcurrent < 2) {
        failures.add('未观察到并发（max=$maxConcurrent）');
      }
      final playlist = await File(result.playlistPath).readAsString();
      if (!playlist.contains('#EXT-X-KEY:METHOD=AES-128')) {
        failures.add('本地清单缺少 AES key');
      }
      if ('#EXTINF'.allMatches(playlist).length != expected) {
        failures.add('本地清单分片数不对');
      }

      final out = '${dir.path}/out.mp4';
      final remux = await Process.run(ffmpeg, [
        '-y', '-hide_banner', '-loglevel', 'error',
        '-allowed_extensions', 'ALL',
        '-i', result.playlistPath,
        '-c', 'copy', '-f', 'mp4', out,
      ]);
      if (remux.exitCode != 0) {
        failures.add('ffmpeg 解密/合并失败：${remux.stderr}');
      } else {
        final info = await Process.run(ffmpeg, ['-hide_banner', '-i', out]);
        final text = info.stderr.toString();
        if (!text.contains('Duration: 00:00:1')) {
          failures.add('输出时长异常：${_firstLine(text, 'Duration')}');
        }
        if (!text.contains('Video:') || !text.contains('Audio:')) {
          failures.add('输出缺少视频或音频轨');
        }
        print(
          '[ok] 下载 ${result.segments} 片 / ${result.bytes} 字节，'
          '并发=$maxConcurrent，本地解密合并成功',
        );
      }

      // 取消：worker 在启动前检查 shouldCancel。
      try {
        await HlsDownloader.download(
          url: url,
          connections: 4,
          shouldCancel: () => true,
        );
        failures.add('取消后仍完成了下载');
      } on HlsCancelledException {
        print('[ok] 取消能中断下载');
      }
    }
  } finally {
    await result?.cleanup();
    await server?.close(force: true);
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
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

/// 用真实清单跑一次，打印耗时/速度（可用于对比 yt-dlp/ffmpeg）。
Future<void> _realWorld(String url) async {
  final sw = Stopwatch()..start();
  final result = await HlsDownloader.download(
    url: url,
    connections: 16,
    headers: {
      'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
          'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15',
      'Referer': 'https://appy8id8hls6032.h5.xiaoeknow.com/',
    },
    onProgress: (done, total, bytes, speed) {
      stdout.write(
        '\r$done/$total '
        '${(speed / 1024 / 1024).toStringAsFixed(2)} MiB/s',
      );
    },
  );
  sw.stop();
  final seconds = sw.elapsedMilliseconds / 1000;
  stdout.writeln(
    '\n[ok] ${result.segments} 片 / ${result.bytes} 字节，'
    '${seconds.toStringAsFixed(2)}s，'
    '${(result.bytes / 1024 / 1024 / seconds).toStringAsFixed(2)} MiB/s',
  );
  final ffmpeg = _findFfmpeg();
  if (ffmpeg != null) {
    final out = '${result.tempDir.path}/out.mp4';
    final r = await Process.run(ffmpeg, [
      '-y', '-hide_banner', '-loglevel', 'error',
      '-allowed_extensions', 'ALL',
      '-i', result.playlistPath,
      '-c', 'copy', '-f', 'mp4', out,
    ]);
    if (r.exitCode == 0) {
      final size = await File(out).length();
      print('[ok] 本地解密/合并 ${(size / 1024 / 1024).toStringAsFixed(2)} MiB');
    } else {
      print('[error] ffmpeg: ${r.stderr}');
    }
  }
  await result.cleanup();
}

/// 生成 10 秒、AES-128 加密、1 秒一片的 HLS。
Future<bool> _prepareFixture(String ffmpeg, Directory dir) async {
  final random = math.Random.secure();
  final key = List<int>.generate(16, (_) => random.nextInt(256));
  final iv = List<int>.generate(16, (_) => random.nextInt(256));
  await File('${dir.path}/key.bin').writeAsBytes(key);
  final ivHex = iv.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  await File('${dir.path}/key.info').writeAsString(
    'key.bin\n${dir.path}/key.bin\n$ivHex\n',
  );

  final result = await Process.run(ffmpeg, [
    '-y', '-hide_banner', '-loglevel', 'error',
    '-f', 'lavfi', '-i', 'testsrc=size=320x240:rate=25',
    '-f', 'lavfi', '-i', 'sine=frequency=440',
    '-t', '10',
    '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-g', '25',
    '-c:a', 'aac', '-shortest',
    '-f', 'hls',
    '-hls_time', '1',
    '-hls_playlist_type', 'vod',
    '-hls_key_info_file', '${dir.path}/key.info',
    '-hls_segment_filename', '${dir.path}/seg_%03d.ts',
    '${dir.path}/index.m3u8',
  ]);
  if (result.exitCode != 0) {
    print('[ffmpeg] ${result.stderr}');
    return false;
  }
  return File('${dir.path}/index.m3u8').existsSync();
}

Future<HttpServer> _serve(
  Directory dir,
  void Function(int active) onConcurrency,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var active = 0;
  server.listen((req) async {
    final name = req.uri.pathSegments.isEmpty
        ? ''
        : req.uri.pathSegments.last;
    final file = File('${dir.path}/$name');
    if (!await file.exists()) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }
    active++;
    onConcurrency(active);
    try {
      // 制造一点延迟，确保并发窗口可观察。
      await Future<void>.delayed(const Duration(milliseconds: 15));
      final bytes = await file.readAsBytes();
      req.response.headers.contentLength = bytes.length;
      req.response.add(bytes);
      await req.response.close();
    } finally {
      active--;
    }
  });
  return server;
}

int _segmentCount(Directory dir) => dir
    .listSync()
    .whereType<File>()
    .where((f) => f.path.endsWith('.ts'))
    .length;

String _firstLine(String text, String key) {
  for (final line in text.split('\n')) {
    if (line.contains(key)) return line.trim();
  }
  return '(未找到 $key)';
}

String? _findFfmpeg() {
  final env = Platform.environment['FFMPEG'];
  if (env != null && File(env).existsSync()) return env;
  final home = Platform.environment['HOME'] ?? '';
  final candidates = [
    '$home/Library/Application Support/com.example.downieTest/bin/ffmpeg',
    '/opt/homebrew/bin/ffmpeg',
    '/usr/local/bin/ffmpeg',
  ];
  for (final path in candidates) {
    if (File(path).existsSync()) return path;
  }
  final which = Process.runSync('which', ['ffmpeg']);
  if (which.exitCode == 0) {
    final path = which.stdout.toString().trim();
    if (path.isNotEmpty) return path;
  }
  return null;
}
