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

  group('effectiveHttpChunkSizeMb', () {
    test('YouTube 未手动设置分块时默认 10 MiB', () {
      expect(effectiveHttpChunkSizeMb('https://youtu.be/abc', 0), 10);
      expect(
        effectiveHttpChunkSizeMb('https://www.youtube.com/watch?v=abc', 0),
        10,
      );
    });

    test('用户手动设置分块时以设置为准', () {
      expect(effectiveHttpChunkSizeMb('https://youtu.be/abc', 5), 5);
    });

    test('非 YouTube 站点默认不分块', () {
      expect(effectiveHttpChunkSizeMb('https://v.douyin.com/abc', 0), 0);
    });
  });

  group('parseProgressLine', () {
    test('普通 HTTP 进度行', () {
      final p = YtDlpRunner.parseProgressLine(
        '[download]  50.0% of 100.00MiB at 5.00MiB/s ETA 00:10',
      );
      expect(p, isNotNull);
      expect(p!.percent, closeTo(0.5, 1e-9));
      expect(p.totalBytes, 100 * 1024 * 1024);
      expect(p.speed, 5 * 1024 * 1024);
      expect(p.eta, 10);
    });

    test('HLS 原生下载器：估算大小 + frag 后缀 + Unknown ETA', () {
      final p = YtDlpRunner.parseProgressLine(
        '[download]  11.8% of ~  23.00KiB at 0.00B/s ETA Unknown (frag 0/23)',
      );
      expect(p, isNotNull);
      // 分片数优先于 yt-dlp 按估算字节算的百分比。
      expect(p!.percent, 0);
      expect(p.totalBytes, 23 * 1024);
      expect(p.speed, 0);
      expect(p.eta, isNull);
    });

    test('HLS 分片进度按 frag 计数推进', () {
      final p = YtDlpRunner.parseProgressLine(
        '[download]  98.4% of ~  11.64MiB at 372.76KiB/s ETA 00:03 (frag 50/51)',
      );
      expect(p!.percent, closeTo(50 / 51, 1e-9));
    });

    test('汇总行没有 at/ETA 也能解析出百分比', () {
      final p = YtDlpRunner.parseProgressLine(
        '[download] 100% of   65.16MiB in 00:03:11 at 347.96KiB/s',
      );
      expect(p, isNotNull);
      expect(p!.percent, 1.0);
      expect(p.speed, closeTo(347.96 * 1024, 1));
    });
  });

  group('canDirectDownload', () {
    Map<String, dynamic> json({
      String videoExt = 'mp4',
      String audioExt = 'm4a',
      String videoProtocol = 'https',
      String audioProtocol = 'https',
      bool fragments = false,
      bool requested = true,
    }) {
      final video = {
        'format_id': '137',
        'ext': videoExt,
        'protocol': videoProtocol,
        'vcodec': 'avc1.640028',
        'acodec': 'none',
        'url': 'https://example.com/v',
        'filesize': 1000,
        if (fragments) 'fragments': [
          {'path': 'v0.m4s'},
        ],
      };
      final audio = {
        'format_id': '140',
        'ext': audioExt,
        'protocol': audioProtocol,
        'vcodec': 'none',
        'acodec': 'mp4a.40.2',
        'url': 'https://example.com/a',
        'filesize': 100,
        if (fragments) 'fragments': [
          {'path': 'a0.m4s'},
        ],
      };
      return {
        if (requested) 'requested_formats': [video, audio],
        'formats': [video, audio],
      };
    }

    test('mp4 + m4a 直链可以分块下载', () {
      expect(
        YtDlpRunner.canDirectDownload(json(), '137+140', '/tmp/out.mp4'),
        isTrue,
      );
    });

    test('webm + webm 输出 webm 可以分块下载', () {
      expect(
        YtDlpRunner.canDirectDownload(
          json(videoExt: 'webm', audioExt: 'webm'),
          '137+140',
          '/tmp/out.webm',
        ),
        isTrue,
      );
    });

    test('容器不匹配时回退', () {
      expect(
        YtDlpRunner.canDirectDownload(json(), '137+140', '/tmp/out.webm'),
        isFalse,
      );
      expect(
        YtDlpRunner.canDirectDownload(
          json(videoExt: 'webm', audioExt: 'm4a'),
          '137+140',
          '/tmp/out.mp4',
        ),
        isFalse,
      );
    });

    test('HLS 分片格式不走直链下载', () {
      expect(
        YtDlpRunner.canDirectDownload(
          json(videoProtocol: 'm3u8_native'),
          '137+140',
          '/tmp/out.mp4',
        ),
        isFalse,
      );
    });

    test('带 fragments 的格式不走直链下载', () {
      expect(
        YtDlpRunner.canDirectDownload(
          json(fragments: true),
          '137+140',
          '/tmp/out.mp4',
        ),
        isFalse,
      );
    });

    test('没有 requested_formats 时按 format_id 从 formats 里找', () {
      expect(
        YtDlpRunner.canDirectDownload(
          json(requested: false),
          '137+140',
          '/tmp/out.mp4',
        ),
        isTrue,
      );
    });

    test('选中的 format_id 不存在时回退', () {
      expect(
        YtDlpRunner.canDirectDownload(json(), '999+140', '/tmp/out.mp4'),
        isFalse,
      );
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
