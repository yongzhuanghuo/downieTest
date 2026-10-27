import 'dart:io';

import 'package:downie_test/core/engine/douyin_downloader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('direct HTTP downloader writes the full body', () async {
    final payload = List<int>.generate(64 * 1024, (i) => i % 251);
    final client = MockClient((request) async {
      expect(request.headers['Referer'], 'https://www.douyin.com/');
      return http.Response.bytes(
        payload,
        200,
        headers: {'content-type': 'video/mp4'},
      );
    });
    final dir = await Directory.systemTemp.createTemp('downie-dl-test');
    final output = '${dir.path}/out.mp4';
    try {
      final percent = <double?>[];
      final result = await DouyinDownloader.download(
        url: 'https://example.com/video.mp4',
        outputPath: output,
        client: client,
        onProgress: (p) => percent.add(p.percent),
      );
      expect(result, output);
      expect(await File(output).length(), payload.length);
      expect(percent, isNotEmpty);
      expect(percent.last, closeTo(1.0, 0.001));
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('206 partial content is accepted', () async {
    final client = MockClient((_) async => http.Response.bytes(
          [1, 2, 3, 4],
          206,
        ));
    final dir = await Directory.systemTemp.createTemp('downie-dl-test');
    final output = '${dir.path}/part.mp4';
    try {
      await DouyinDownloader.download(
        url: 'https://example.com/video.mp4',
        outputPath: output,
        client: client,
        onProgress: (_) {},
      );
      expect(await File(output).length(), 4);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('non-2xx response throws', () async {
    final client = MockClient((_) async => http.Response.bytes([1], 403));
    final dir = await Directory.systemTemp.createTemp('downie-dl-test');
    try {
      await expectLater(
        DouyinDownloader.download(
          url: 'https://example.com/video.mp4',
          outputPath: '${dir.path}/bad.mp4',
          client: client,
          onProgress: (_) {},
        ),
        throwsA(isA<DouyinDownloadException>()),
      );
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
