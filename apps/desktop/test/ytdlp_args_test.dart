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
}
