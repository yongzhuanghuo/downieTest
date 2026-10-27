import 'dart:async';
import 'dart:io';

import 'package:downie_test/core/engine/douyin_downloader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('direct HTTP downloader writes the full body', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final payload = List<int>.generate(64 * 1024, (i) => i % 251);
    server.listen((request) async {
      request.response.headers.contentType = ContentType('video', 'mp4');
      request.response.contentLength = payload.length;
      request.response.add(payload);
      await request.response.close();
    });
    final dir = await Directory.systemTemp.createTemp('downie-dl-test');
    final output = '${dir.path}/out.mp4';
    try {
      final percent = <double?>[];
      final result = await DouyinDownloader.download(
        url: 'http://127.0.0.1:${server.port}/video.mp4',
        outputPath: output,
        onProgress: (p) => percent.add(p.percent),
      );
      expect(result, output);
      expect(await File(output).length(), payload.length);
      expect(percent, isNotEmpty);
    } finally {
      await server.close(force: true);
      await dir.delete(recursive: true);
    }
  });
}
