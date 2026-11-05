import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// 分块下载失败（可回退到单连接/ffmpeg）。
class ChunkedDownloadException implements Exception {
  final String message;

  const ChunkedDownloadException(this.message);

  @override
  String toString() => 'ChunkedDownloadException: $message';
}

/// 服务器不支持 Range：调用方应回退到单连接下载。
class RangeNotSupportedException extends ChunkedDownloadException {
  const RangeNotSupportedException(super.message);
}

/// 用户取消。
class DownloadCancelledException extends ChunkedDownloadException {
  const DownloadCancelledException() : super('已取消');
}

/// 下载进度回调：已下载字节、总字节（可为空）、瞬时速度（字节/秒）。
typedef ChunkProgressCallback =
    void Function(int downloadedBytes, int? totalBytes, double bytesPerSecond);

/// 多连接 Range 分块下载器。
///
/// 与 Downie 的 `XUChunkReader.ChunkDownloadPool` 同思路：先探测文件总大小，
/// 按固定块大小切片，用 N 个并发 Range 请求同时拉取，再按偏移写入同一个文件。
/// 单连接被 CDN 限速时，多连接可以把带宽重新拉起来。
///
/// 仅依赖 dart:io，便于独立测试；不支持 Range、SOCKS 代理或任何异常时抛
/// [RangeNotSupportedException] / [ChunkedDownloadException]，由调用方回退。
class ChunkedHttpDownloader {
  ChunkedHttpDownloader._();

  /// 下载 [url] 到 [outputPath]，返回实际字节数。
  ///
  /// [connections] 并发连接数；[chunkSizeBytes] 每块大小（默认 2 MiB，与
  /// Downie 的普通 HTTP 块大小一致）。
  static Future<int> download({
    required String url,
    required String outputPath,
    Map<String, String> headers = const {},
    int connections = 4,
    int chunkSizeBytes = 2 * 1024 * 1024,
    String? proxy,
    ChunkProgressCallback? onProgress,
    bool Function()? shouldCancel,
  }) async {
    final uri = Uri.parse(url);
    final connectionCount = connections.clamp(1, 16);
    final chunkSize = math.max(64 * 1024, chunkSizeBytes);

    final proxyDirective = _proxyDirective(proxy);
    if (proxy != null && proxy.trim().isNotEmpty && proxyDirective == null) {
      throw const RangeNotSupportedException('当前代理类型不支持分块下载');
    }

    final client = HttpClient()
      ..autoUncompress = false
      ..maxConnectionsPerHost = connectionCount
      ..connectionTimeout = const Duration(seconds: 20);
    if (proxyDirective != null) {
      client.findProxy = (_) => proxyDirective;
    }

    RandomAccessFile? raf;
    try {
      final totalBytes = await _probeTotalBytes(client, uri, headers);
      if (totalBytes <= 0) {
        throw const RangeNotSupportedException('服务器未返回文件大小');
      }

      final file = File(outputPath);
      await file.parent.create(recursive: true);
      raf = await file.open(mode: FileMode.write);
      await raf.truncate(totalBytes);

      final chunks = <_Chunk>[];
      for (var start = 0; start < totalBytes; start += chunkSize) {
        chunks.add(_Chunk(start, math.min(start + chunkSize, totalBytes) - 1));
      }

      final writeLock = _Mutex();
      var nextChunk = 0;
      var downloaded = 0;
      var cancelled = false;
      var lastReport = DateTime.now();
      final stopwatch = Stopwatch()..start();

      void report() {
        if (onProgress == null) return;
        final now = DateTime.now();
        if (now.difference(lastReport) < const Duration(milliseconds: 200) &&
            downloaded < totalBytes) {
          return;
        }
        lastReport = now;
        final elapsedMicros = stopwatch.elapsedMicroseconds;
        final speed = elapsedMicros <= 0
            ? 0.0
            : downloaded * 1000000 / elapsedMicros;
        onProgress(downloaded, totalBytes, speed);
      }

      Future<void> worker() async {
        while (true) {
          if (cancelled) throw const DownloadCancelledException();
          final index = nextChunk++;
          if (index >= chunks.length) return;
          final chunk = chunks[index];
          final bytes = await _downloadChunk(
            client,
            uri,
            headers,
            chunk,
            shouldCancel: shouldCancel,
          );
          if (cancelled) throw const DownloadCancelledException();
          await writeLock.run(() async {
            await raf!.setPosition(chunk.start);
            await raf.writeFrom(bytes);
          });
          downloaded += bytes.length;
          report();
        }
      }

      final workerCount = math.min(connectionCount, chunks.length);
      try {
        await Future.wait(List.generate(workerCount, (_) => worker()));
      } catch (e) {
        cancelled = true;
        client.close(force: true);
        rethrow;
      }

      await raf.flush();
      await raf.close();
      raf = null;

      if (await File(outputPath).length() != totalBytes) {
        throw const ChunkedDownloadException('分块写入后文件大小不一致');
      }
      onProgress?.call(totalBytes, totalBytes, 0);
      return totalBytes;
    } finally {
      try {
        await raf?.close();
      } catch (_) {}
      client.close(force: true);
    }
  }

  /// 用 `Range: bytes=0-0` 探测总大小；失败时再试 HEAD。
  static Future<int> _probeTotalBytes(
    HttpClient client,
    Uri uri,
    Map<String, String> headers,
  ) async {
    var rangeError = '';
    try {
      final req = await client.getUrl(uri);
      _applyHeaders(req, headers);
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
      req.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final resp = await req.close().timeout(const Duration(seconds: 30));
      final status = resp.statusCode;
      final contentRange = resp.headers.value(HttpHeaders.contentRangeHeader);
      if (status == HttpStatus.partialContent && contentRange != null) {
        await resp.drain<void>();
        final total = _totalFromContentRange(contentRange);
        if (total != null && total > 0) return total;
      } else {
        // 服务器忽略 Range 时可能返回完整文件，不要在这里把整个文件读一遍。
        await resp.listen(null).cancel();
        rangeError = status == HttpStatus.ok
            ? '服务器忽略了 Range 请求'
            : '探测状态码 $status';
      }
    } catch (e) {
      rangeError = e.toString();
    }

    // 有些服务器不响应 Range 探测，但 HEAD 会给出 Content-Length。
    try {
      final req = await client.headUrl(uri);
      _applyHeaders(req, headers);
      final resp = await req.close().timeout(const Duration(seconds: 30));
      final length = resp.contentLength;
      await resp.drain<void>();
      if (length > 0) return length;
    } catch (_) {}

    throw RangeNotSupportedException('服务器不支持 Range 分块下载（$rangeError）');
  }

  static int? _totalFromContentRange(String value) {
    // bytes 0-0/12345
    final slash = value.lastIndexOf('/');
    if (slash < 0 || slash == value.length - 1) return null;
    return int.tryParse(value.substring(slash + 1).trim());
  }

  static Future<Uint8List> _downloadChunk(
    HttpClient client,
    Uri uri,
    Map<String, String> headers,
    _Chunk chunk, {
    bool Function()? shouldCancel,
    int maxAttempts = 3,
  }) async {
    final expected = chunk.end - chunk.start + 1;
    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (shouldCancel?.call() ?? false) {
        throw const DownloadCancelledException();
      }
      try {
        final req = await client.getUrl(uri);
        _applyHeaders(req, headers);
        req.headers.set(
          HttpHeaders.rangeHeader,
          'bytes=${chunk.start}-${chunk.end}',
        );
        req.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
        final resp = await req.close().timeout(const Duration(seconds: 30));

        if (resp.statusCode == HttpStatus.ok) {
          await resp.drain<void>();
          throw RangeNotSupportedException('分块请求被服务器忽略（返回 200）');
        }
        if (resp.statusCode != HttpStatus.partialContent) {
          await resp.drain<void>();
          throw ChunkedDownloadException('分块请求状态码 ${resp.statusCode}');
        }

        final contentRange = resp.headers.value(HttpHeaders.contentRangeHeader);
        if (contentRange != null) {
          final start = _startFromContentRange(contentRange);
          if (start != null && start != chunk.start) {
            await resp.drain<void>();
            throw ChunkedDownloadException(
              'Content-Range 起点不匹配：期望 ${chunk.start}，实际 $start',
            );
          }
        }

        final builder = BytesBuilder(copy: false);
        await for (final part in resp.timeout(const Duration(seconds: 120))) {
          if (shouldCancel?.call() ?? false) {
            throw const DownloadCancelledException();
          }
          builder.add(part);
          if (builder.length > expected + 1024) {
            throw ChunkedDownloadException('分块返回的数据超过预期大小');
          }
        }
        final bytes = builder.takeBytes();
        if (bytes.length != expected) {
          throw ChunkedDownloadException(
            '分块大小不匹配：期望 $expected，实际 ${bytes.length}',
          );
        }
        return bytes;
      } on RangeNotSupportedException {
        rethrow;
      } on DownloadCancelledException {
        rethrow;
      } catch (e) {
        lastError = e;
        if (attempt < maxAttempts) {
          await Future<void>.delayed(Duration(milliseconds: 300 * attempt));
        }
      }
    }
    throw ChunkedDownloadException('分块下载失败：$lastError');
  }

  static int? _startFromContentRange(String value) {
    // bytes 123-456/789
    final match = RegExp(r'bytes\s+(\d+)-').firstMatch(value);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  static void _applyHeaders(
    HttpClientRequest req,
    Map<String, String> headers,
  ) {
    headers.forEach((key, value) {
      if (key.isEmpty || value.isEmpty) return;
      req.headers.set(key, value);
    });
  }

  static String? _proxyDirective(String? proxy) {
    final raw = proxy?.trim() ?? '';
    if (raw.isEmpty) return null;
    final parsed = Uri.tryParse(raw.contains('://') ? raw : 'http://$raw');
    if (parsed == null || parsed.host.isEmpty) return null;
    final scheme = parsed.scheme.toLowerCase();
    if (scheme == 'socks' || scheme == 'socks5' || scheme == 'socks4') {
      return null;
    }
    final port = parsed.hasPort ? parsed.port : 80;
    return 'PROXY ${parsed.host}:$port';
  }
}

class _Chunk {
  final int start;
  final int end;

  const _Chunk(this.start, this.end);
}

/// 让多个分块的写入串行化，避免抢同一个 RandomAccessFile。
class _Mutex {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() action) {
    final completer = Completer<void>();
    final previous = _tail;
    _tail = completer.future;
    final result = previous.then((_) => action());
    return result.whenComplete(completer.complete);
  }
}
