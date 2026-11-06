import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// HLS 下载失败（不应静默回退到 ffmpeg，否则会得到残缺文件）。
class HlsDownloadException implements Exception {
  final String message;

  const HlsDownloadException(this.message);

  @override
  String toString() => 'HlsDownloadException: $message';
}

/// 当前清单用了下载器不支持的特性（直播、BYTERANGE、SAMPLE-AES 等）。
/// 调用方应回退到 yt-dlp。
class HlsUnsupportedException extends HlsDownloadException {
  const HlsUnsupportedException(super.message);
}

/// 用户取消。
class HlsCancelledException extends HlsDownloadException {
  const HlsCancelledException() : super('已取消');
}

/// TLS 握手失败（常见于系统代理不支持 CONNECT / 做了 TLS 拦截）。
/// 调用方应先尝试直连重试，仍失败再回退 yt-dlp。
class HlsTlsException extends HlsDownloadException {
  const HlsTlsException(super.message);
}

/// 已下载分片数、总分片数、已下载字节、瞬时速度（字节/秒）。
typedef HlsProgressCallback =
    void Function(
      int doneSegments,
      int totalSegments,
      int downloadedBytes,
      double bytesPerSecond,
    );

/// HLS 下载结果：本地清单 + 临时目录。
///
/// 调用方用 ffmpeg 在本地解密/合并后，必须调用 [cleanup] 删除临时文件。
class HlsDownloadResult {
  final Directory tempDir;
  final String playlistPath;
  final int bytes;
  final int segments;

  const HlsDownloadResult({
    required this.tempDir,
    required this.playlistPath,
    required this.bytes,
    required this.segments,
  });

  Future<void> cleanup() async {
    try {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    } catch (_) {}
  }
}

/// 原生 HLS 下载器：多连接拉分片，AES 交给本地 ffmpeg。
///
/// 为什么不直接用 yt-dlp：它的 HLS 分片解密是纯 Python AES，实测 16 个
/// 2 秒分片要 22 秒 CPU，`-N 16` 也提不上去；ffmpeg 走网络又是单连接。
/// 这里用 Dart `HttpClient` 复用连接并发下载，key/分片落到临时目录，
/// 最后让 ffmpeg 在本地用系统原生 AES 解密并 remux（2.8MB 约 0.3 秒）。
class HlsDownloader {
  HlsDownloader._();

  static Future<HlsDownloadResult> download({
    required String url,
    Map<String, String> headers = const {},
    int connections = 16,
    String? proxy,
    HlsProgressCallback? onProgress,
    bool Function()? shouldCancel,
  }) async {
    final hasProxy = proxy != null && proxy.trim().isNotEmpty;
    try {
      return await _downloadOnce(
        url: url,
        headers: headers,
        connections: connections,
        proxy: proxy,
        onProgress: onProgress,
        shouldCancel: shouldCancel,
      );
    } on HlsTlsException {
      if (!hasProxy) rethrow;
      // Windows 上常见的系统代理/TLS 拦截问题：改直连再试一次。
      return _downloadOnce(
        url: url,
        headers: headers,
        connections: connections,
        proxy: null,
        onProgress: onProgress,
        shouldCancel: shouldCancel,
      );
    }
  }

  static Future<HlsDownloadResult> _downloadOnce({
    required String url,
    Map<String, String> headers = const {},
    int connections = 16,
    String? proxy,
    HlsProgressCallback? onProgress,
    bool Function()? shouldCancel,
  }) async {
    final connectionCount = connections.clamp(1, 32);
    final proxyDirective = _proxyDirective(proxy);
    if (proxy != null && proxy.trim().isNotEmpty && proxyDirective == null) {
      throw const HlsUnsupportedException('当前代理类型不支持 HLS 分片下载');
    }

    final client = HttpClient()
      ..autoUncompress = false
      ..maxConnectionsPerHost = connectionCount
      ..connectionTimeout = const Duration(seconds: 15)
      ..idleTimeout = const Duration(seconds: 30);
    if (proxyDirective != null) {
      client.findProxy = (_) => proxyDirective;
    }

    Directory? tempDir;
    try {
      final base = Uri.parse(url);
      var manifestUri = base;
      var manifest = await _fetchText(
        client,
        manifestUri,
        headers,
        shouldCancel,
      );

      // master playlist：选最高码率变体。
      if (manifest.contains('#EXT-X-STREAM-INF')) {
        final variants = _parseVariants(manifest, manifestUri);
        if (variants.isEmpty) {
          throw const HlsUnsupportedException('master 清单里没有可用变体');
        }
        variants.sort((a, b) => b.bandwidth.compareTo(a.bandwidth));
        manifestUri = variants.first.uri;
        manifest = await _fetchText(
          client,
          manifestUri,
          headers,
          shouldCancel,
        );
        if (manifest.contains('#EXT-X-STREAM-INF')) {
          throw const HlsUnsupportedException('多层 master 清单暂不支持');
        }
      }

      final isVod =
          manifest.contains('#EXT-X-ENDLIST') ||
          manifest.contains('#EXT-X-PLAYLIST-TYPE:VOD');
      if (!isVod) {
        throw const HlsUnsupportedException('直播 HLS 交给 yt-dlp');
      }
      if (manifest.contains('#EXT-X-BYTERANGE')) {
        throw const HlsUnsupportedException('带 BYTERANGE 的 HLS 交给 yt-dlp');
      }
      if (RegExp(r'#EXT-X-MEDIA:[^\n]*TYPE=AUDIO').hasMatch(manifest)) {
        throw const HlsUnsupportedException('独立音轨 HLS 交给 yt-dlp');
      }

      final parsed = _parseMediaPlaylist(manifest, manifestUri);
      if (parsed.segments.isEmpty) {
        throw const HlsDownloadException('清单里没有分片');
      }

      tempDir = await Directory.systemTemp.createTemp('downie_hls_');

      // 下载 key（去重）。
      final keyFiles = <String, String>{}; // uri|iv -> local file
      for (final segment in parsed.segments) {
        final key = segment.key;
        if (key == null) continue;
        final id = '${key.uri}|${key.ivHex ?? ''}';
        if (keyFiles.containsKey(id)) continue;
        final name = 'key_${keyFiles.length}.bin';
        final file = File('${tempDir.path}/$name');
        await _downloadBytes(
          client,
          key.uri,
          file,
          headers,
          shouldCancel,
        );
        if (await file.length() != 16) {
          throw const HlsDownloadException('AES key 长度不是 16 字节');
        }
        keyFiles[id] = name;
      }

      // 下载 init segment。
      String? initName;
      if (parsed.initUri != null) {
        initName = 'init_0.mp4';
        await _downloadFile(
          client,
          parsed.initUri!,
          File('${tempDir.path}/$initName'),
          headers,
          shouldCancel,
        );
      }

      var downloadedBytes = 0;
      var doneSegments = 0;
      final totalSegments = parsed.segments.length;
      final stopwatch = Stopwatch()..start();
      var lastReport = DateTime.now();

      void report() {
        if (onProgress == null) return;
        final now = DateTime.now();
        if (now.difference(lastReport) < const Duration(milliseconds: 200) &&
            doneSegments < totalSegments) {
          return;
        }
        lastReport = now;
        final micros = stopwatch.elapsedMicroseconds;
        final speed = micros <= 0 ? 0.0 : downloadedBytes * 1000000 / micros;
        onProgress(doneSegments, totalSegments, downloadedBytes, speed);
      }

      var next = 0;
      Future<void> worker() async {
        while (true) {
          if (shouldCancel?.call() ?? false) {
            throw const HlsCancelledException();
          }
          final index = next++;
          if (index >= totalSegments) return;
          final segment = parsed.segments[index];
          final file = File(
            '${tempDir!.path}/seg_$index.${segment.extension}',
          );
          final bytes = await _downloadFile(
            client,
            segment.uri,
            file,
            headers,
            shouldCancel,
          );
          downloadedBytes += bytes;
          doneSegments++;
          report();
        }
      }

      final workerCount = math.min(connectionCount, totalSegments);
      try {
        await Future.wait(List.generate(workerCount, (_) => worker()));
      } on HlsCancelledException {
        rethrow;
      } catch (e) {
        throw HlsDownloadException('分片下载中断: $e');
      }
      report();

      // 生成全本地清单，交给 ffmpeg 解密/合并。
      final playlist = StringBuffer()
        ..writeln('#EXTM3U')
        ..writeln('#EXT-X-VERSION:3')
        ..writeln('#EXT-X-TARGETDURATION:${parsed.targetDuration}')
        ..writeln('#EXT-X-MEDIA-SEQUENCE:0')
        ..writeln('#EXT-X-PLAYLIST-TYPE:VOD');
      if (initName != null) {
        playlist.writeln('#EXT-X-MAP:URI="$initName"');
      }
      for (var i = 0; i < totalSegments; i++) {
        final segment = parsed.segments[i];
        final key = segment.key;
        if (key != null) {
          final name = keyFiles['${key.uri}|${key.ivHex ?? ''}']!;
          final iv = key.ivHex ?? _sequenceIv(segment.sequence);
          playlist.writeln(
            '#EXT-X-KEY:METHOD=AES-128,URI="$name",IV=0x$iv',
          );
        }
        playlist
          ..writeln('#EXTINF:${segment.duration.toStringAsFixed(6)},')
          ..writeln('seg_$i.${segment.extension}');
      }
      playlist.writeln('#EXT-X-ENDLIST');

      final playlistPath = '${tempDir.path}/local.m3u8';
      await File(playlistPath).writeAsString(playlist.toString());
      return HlsDownloadResult(
        tempDir: tempDir,
        playlistPath: playlistPath,
        bytes: downloadedBytes,
        segments: totalSegments,
      );
    } catch (e) {
      if (tempDir != null) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  /// 取清单文本。
  static Future<String> _fetchText(
    HttpClient client,
    Uri uri,
    Map<String, String> headers,
    bool Function()? shouldCancel,
  ) async {
    try {
      final req = await client.getUrl(uri);
      _applyHeaders(req, headers);
      req.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final resp = await req.close().timeout(const Duration(seconds: 30));
      if (resp.statusCode != HttpStatus.ok) {
        await resp.drain<void>();
        throw HlsDownloadException('清单 HTTP ${resp.statusCode}');
      }
      if (shouldCancel?.call() ?? false) {
        await resp.drain<void>();
        throw const HlsCancelledException();
      }
      return utf8.decodeStream(resp.timeout(const Duration(seconds: 60)));
    } on HandshakeException catch (e) {
      throw HlsTlsException('清单 ${uri.host} TLS 握手失败: $e');
    }
  }

  /// 下载二进制（key），返回字节数。
  static Future<int> _downloadBytes(
    HttpClient client,
    Uri uri,
    File file,
    Map<String, String> headers,
    bool Function()? shouldCancel,
  ) async {
    try {
      final req = await client.getUrl(uri);
      _applyHeaders(req, headers);
      req.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final resp = await req.close().timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200 && resp.statusCode != 206) {
        await resp.drain<void>();
        throw HlsDownloadException('key HTTP ${resp.statusCode}');
      }
      final builder = BytesBuilder(copy: false);
      await for (final part in resp.timeout(const Duration(seconds: 60))) {
        if (shouldCancel?.call() ?? false) {
          throw const HlsCancelledException();
        }
        builder.add(part);
      }
      final bytes = builder.takeBytes();
      await file.writeAsBytes(bytes, flush: true);
      return bytes.length;
    } on HandshakeException catch (e) {
      throw HlsTlsException('key ${uri.host} TLS 握手失败: $e');
    }
  }

  /// 下载分片到文件，带重试；返回字节数。
  static Future<int> _downloadFile(
    HttpClient client,
    Uri uri,
    File file,
    Map<String, String> headers,
    bool Function()? shouldCancel,
    {int maxAttempts = 5}
  ) async {
    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (shouldCancel?.call() ?? false) {
        throw const HlsCancelledException();
      }
      IOSink? sink;
      try {
        final req = await client.getUrl(uri);
        _applyHeaders(req, headers);
        req.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
        final resp = await req.close().timeout(const Duration(seconds: 30));
        if (resp.statusCode != 200 && resp.statusCode != 206) {
          await resp.drain<void>();
          throw HlsDownloadException('分片 HTTP ${resp.statusCode}');
        }
        sink = file.openWrite();
        var bytes = 0;
        await for (final part in resp.timeout(const Duration(seconds: 60))) {
          if (shouldCancel?.call() ?? false) {
            throw const HlsCancelledException();
          }
          sink.add(part);
          bytes += part.length;
        }
        await sink.flush();
        await sink.close();
        sink = null;
        return bytes;
      } on HlsCancelledException {
        rethrow;
      } on HandshakeException catch (e) {
        // 重试也过不了 TLS 握手；交给上层决定是否改直连。
        throw HlsTlsException('分片 ${uri.host} TLS 握手失败: $e');
      } catch (e) {
        lastError = e;
        try {
          await sink?.close();
        } catch (_) {}
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {}
        if (attempt < maxAttempts) {
          await Future<void>.delayed(Duration(milliseconds: 250 * attempt));
        }
      }
    }
    throw HlsDownloadException('分片下载失败: $lastError');
  }

  static void _applyHeaders(HttpClientRequest req, Map<String, String> headers) {
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

  static List<_Variant> _parseVariants(String manifest, Uri base) {
    final lines = manifest.split('\n');
    final result = <_Variant>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (!line.startsWith('#EXT-X-STREAM-INF:')) continue;
      var bandwidth = 0;
      for (final attr in _splitAttrs(line.substring(18))) {
        final eq = attr.indexOf('=');
        if (eq < 0) continue;
        if (attr.substring(0, eq).trim() == 'BANDWIDTH') {
          bandwidth = int.tryParse(attr.substring(eq + 1).trim()) ?? 0;
        }
      }
      for (var j = i + 1; j < lines.length; j++) {
        final uriLine = lines[j].trim();
        if (uriLine.isEmpty || uriLine.startsWith('#')) continue;
        result.add(_Variant(bandwidth, base.resolve(uriLine)));
        break;
      }
    }
    return result;
  }

  static _ParsedPlaylist _parseMediaPlaylist(String manifest, Uri base) {
    final segments = <_Segment>[];
    var targetDuration = 0;
    var mediaSequence = 0;
    Uri? initUri;
    _KeySpec? currentKey;
    double? pendingDuration;
    var index = 0;

    for (final raw in manifest.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#EXT-X-TARGETDURATION:')) {
        targetDuration =
            int.tryParse(line.substring(22).trim()) ?? targetDuration;
      } else if (line.startsWith('#EXT-X-MEDIA-SEQUENCE:')) {
        mediaSequence = int.tryParse(line.substring(22).trim()) ?? 0;
      } else if (line.startsWith('#EXT-X-KEY:')) {
        currentKey = _parseKey(line.substring(11), base);
      } else if (line.startsWith('#EXT-X-MAP:')) {
        final attrs = _attrs(line.substring(11));
        final uri = attrs['URI'];
        if (uri == null || uri.isEmpty) {
          throw const HlsUnsupportedException('EXT-X-MAP 缺少 URI');
        }
        if (attrs.containsKey('BYTERANGE')) {
          throw const HlsUnsupportedException('EXT-X-MAP BYTERANGE 暂不支持');
        }
        initUri = base.resolve(uri);
      } else if (line.startsWith('#EXTINF:')) {
        final comma = line.indexOf(',');
        final text = comma < 0 ? line.substring(8) : line.substring(8, comma);
        pendingDuration = double.tryParse(text.trim()) ?? 0;
      } else if (line.startsWith('#')) {
        continue;
      } else {
        if (pendingDuration == null) continue;
        final segmentUri = base.resolve(line);
        segments.add(_Segment(
          uri: segmentUri,
          duration: pendingDuration,
          key: currentKey,
          sequence: mediaSequence + index,
          extension: _segmentExtension(segmentUri),
        ));
        index++;
        pendingDuration = null;
      }
    }
    return _ParsedPlaylist(
      segments: segments,
      initUri: initUri,
      targetDuration: targetDuration > 0
          ? targetDuration
          : _maxDuration(segments),
    );
  }

  static _KeySpec? _parseKey(String attrText, Uri base) {
    final attrs = _attrs(attrText);
    final method = (attrs['METHOD'] ?? '').toUpperCase();
    if (method.isEmpty || method == 'NONE') return null;
    if (method != 'AES-128') {
      throw HlsUnsupportedException('不支持的 HLS 加密方式: $method');
    }
    final uriText = attrs['URI'];
    if (uriText == null || uriText.isEmpty) {
      throw const HlsDownloadException('AES key 缺少 URI');
    }
    var iv = attrs['IV'];
    if (iv != null) {
      iv = iv.toLowerCase().replaceFirst('0x', '');
      if (iv.length > 32) iv = iv.substring(iv.length - 32);
      iv = iv.padLeft(32, '0');
    }
    return _KeySpec(uri: base.resolve(uriText), ivHex: iv);
  }

  /// 解析 `KEY=value,KEY2="value,2"`，逗号在引号内不切。
  static Map<String, String> _attrs(String text) {
    final result = <String, String>{};
    for (final part in _splitAttrs(text)) {
      final eq = part.indexOf('=');
      if (eq < 0) continue;
      var value = part.substring(eq + 1).trim();
      if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
        value = value.substring(1, value.length - 1);
      }
      result[part.substring(0, eq).trim().toUpperCase()] = value;
    }
    return result;
  }

  static List<String> _splitAttrs(String text) {
    final parts = <String>[];
    final buffer = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (ch == '"') inQuotes = !inQuotes;
      if (ch == ',' && !inQuotes) {
        parts.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(ch);
      }
    }
    if (buffer.isNotEmpty) parts.add(buffer.toString());
    return parts;
  }

  static String _segmentExtension(Uri uri) {
    final path = uri.path.toLowerCase();
    for (final ext in ['.m4s', '.ts', '.aac', '.m4a', '.mp4']) {
      if (path.endsWith(ext)) return ext.substring(1);
    }
    return 'ts';
  }

  static String _sequenceIv(int sequence) {
    final hex = sequence.toRadixString(16).padLeft(32, '0');
    return hex;
  }

  static int _maxDuration(List<_Segment> segments) {
    var max = 1;
    for (final s in segments) {
      final value = s.duration.ceil();
      if (value > max) max = value;
    }
    return max;
  }
}

class _Variant {
  final int bandwidth;
  final Uri uri;

  const _Variant(this.bandwidth, this.uri);
}

class _Segment {
  final Uri uri;
  final double duration;
  final _KeySpec? key;
  final int sequence;
  final String extension;

  const _Segment({
    required this.uri,
    required this.duration,
    required this.key,
    required this.sequence,
    required this.extension,
  });
}

class _KeySpec {
  final Uri uri;
  final String? ivHex;

  const _KeySpec({required this.uri, required this.ivHex});
}

class _ParsedPlaylist {
  final List<_Segment> segments;
  final Uri? initUri;
  final int targetDuration;

  const _ParsedPlaylist({
    required this.segments,
    required this.initUri,
    required this.targetDuration,
  });
}
