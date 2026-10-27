import 'package:downie_test/features/home/home_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('extractUrls', () {
    test('extracts URL from douyin share text', () {
      const text = '7.68 复制打开抖音，看看【某某】的作品 '
          'https://v.douyin.com/iAbCdEf/ 复制此链接，打开Dou音搜索';
      expect(extractUrls(text), ['https://v.douyin.com/iAbCdEf/']);
    });

    test('extracts multiple URLs in order and dedupes', () {
      const text = 'https://example.com/1\n'
          'https://example.com/2，https://example.com/1';
      expect(
        extractUrls(text),
        ['https://example.com/1', 'https://example.com/2'],
      );
    });

    test('strips full-width and half-width trailing punctuation', () {
      const text = '（https://example.com/a） https://example.com/b。'
          'https://example.com/c,';
      expect(
        extractUrls(text),
        [
          'https://example.com/a',
          'https://example.com/b',
          'https://example.com/c',
        ],
      );
    });

    test('extracts scheme-less douyin/bilibili share links', () {
      const text = '4.64 复制打开抖音，看看这个视频 v.douyin.com/iAbCdEf/ '
          '复制此链接';
      expect(
        extractVideoUrls(text),
        ['https://v.douyin.com/iAbCdEf/'],
      );
      expect(firstVideoUrl(text), 'https://v.douyin.com/iAbCdEf/');

      expect(
        extractVideoUrls('B站视频 b23.tv/abc123 好看'),
        ['https://b23.tv/abc123'],
      );
      expect(
        extractVideoUrls('www.douyin.com/video/7300000000000000000'),
        ['https://www.douyin.com/video/7300000000000000000'],
      );
    });

    test('wholeHttpUrl keeps Chinese characters in the path', () {
      const url = 'https://example.com/视频/第一集';
      expect(wholeHttpUrl(url), url);
      expect(wholeHttpUrl('看这个 $url 很好看'), isNull);
      expect(wholeHttpUrl('example.com/video'), isNull);
      expect(
        wholeHttpUrl('https://example.com/video。'),
        'https://example.com/video',
      );
    });

    test('returns empty for text without a URL', () {
      expect(extractUrls('没有链接'), isEmpty);
      expect(extractFirstUrl('没有链接'), isNull);
    });
  });
}
