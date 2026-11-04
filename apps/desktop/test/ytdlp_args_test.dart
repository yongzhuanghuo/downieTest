import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:downie_test/core/engine/ytdlp_runner.dart';

void main() {
  group('buildYouTubeArgs', () {
    test('YouTube 链接带 node runtime 和 web_safari', () {
      final args = buildYouTubeArgs(
        'https://youtu.be/4JoEWdV7tpQ',
        nodePath: '/opt/homebrew/bin/node',
      );
      expect(args, containsAllInOrder(['--js-runtimes', 'node:/opt/homebrew/bin/node']));
      expect(
        args,
        containsAllInOrder([
          '--extractor-args',
          'youtube:player_client=default,web_safari',
        ]),
      );
    });

    test('youtube.com 域名也命中', () {
      expect(
        buildYouTubeArgs(
          'https://www.youtube.com/watch?v=4JoEWdV7tpQ',
          nodePath: '/usr/local/bin/node',
        ),
        isNotEmpty,
      );
    });

    test('非 YouTube 链接不追加参数', () {
      expect(
        buildYouTubeArgs('https://www.bilibili.com/video/BV1xx', nodePath: '/bin/node'),
        isEmpty,
      );
    });

    test('node 缺失时只带 extractor-args', () {
      final args = buildYouTubeArgs('https://youtu.be/4JoEWdV7tpQ');
      expect(args, contains('--extractor-args'));
      expect(args, isNot(contains('--js-runtimes')));
    });
  });

  group('filterCookiePathsForSite', () {
    final sep = Platform.pathSeparator;
    final youtube = 'cookies${sep}youtube.txt';
    final douyin = 'cookies${sep}douyin.txt';

    test('YouTube 配置了浏览器 Cookie 时不再混用任何 cookie 文件', () {
      expect(
        filterCookiePathsForSite(
          [youtube, douyin],
          url: 'https://youtu.be/4JoEWdV7tpQ',
          browser: 'edge',
        ),
        isEmpty,
      );
    });

    test('未配置浏览器 Cookie 时保留 youtube.txt', () {
      expect(
        filterCookiePathsForSite(
          [youtube, douyin],
          url: 'https://youtu.be/4JoEWdV7tpQ',
          browser: '',
        ),
        [youtube, douyin],
      );
    });

    test('非 YouTube 站点不受影响', () {
      expect(
        filterCookiePathsForSite(
          [youtube, douyin],
          url: 'https://www.bilibili.com/video/BV1xx',
          browser: 'edge',
        ),
        [youtube, douyin],
      );
    });
  });
}
