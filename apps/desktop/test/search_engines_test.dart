import 'package:downie_test/core/sites/search_engines.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveAddressInput', () {
    test('keeps full URLs', () {
      expect(
        resolveAddressInput('https://example.com/a?b=1', engineId: 1),
        'https://example.com/a?b=1',
      );
      expect(
        resolveAddressInput('http://example.com', engineId: 1),
        'http://example.com',
      );
    });

    test('adds https to bare domains', () {
      expect(
        resolveAddressInput('www.bilibili.com/video/BV1', engineId: 1),
        'https://www.bilibili.com/video/BV1',
      );
      expect(
        resolveAddressInput('example.com:8080/path', engineId: 1),
        'https://example.com:8080/path',
      );
    });

    test('searches for keywords with the selected engine', () {
      final bing = resolveAddressInput('视频 下载', engineId: 1);
      expect(bing, startsWith('https://www.bing.com/search?q='));
      expect(bing, contains(Uri.encodeQueryComponent('视频 下载')));

      expect(
        resolveAddressInput('cat videos', engineId: 0),
        startsWith('https://www.google.com/search?q='),
      );
      expect(
        resolveAddressInput('猫', engineId: 2),
        startsWith('https://www.baidu.com/s?wd='),
      );
    });

    test('empty input returns empty', () {
      expect(resolveAddressInput('   ', engineId: 1), isEmpty);
    });

    test('unknown engine falls back to Bing', () {
      expect(
        resolveAddressInput('keyword', engineId: 99),
        startsWith('https://www.bing.com/search?q='),
      );
    });
  });
}
