import 'dart:convert';

import 'package:downie_test/core/engine/ytdlp_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('looksLikePlaylist', () {
    test('detects list query and playlist paths', () {
      expect(
        YtDlpRunner.looksLikePlaylist(
          'https://www.youtube.com/watch?v=abc&list=PL123',
        ),
        isTrue,
      );
      expect(
        YtDlpRunner.looksLikePlaylist(
          'https://www.youtube.com/playlist?list=PL123',
        ),
        isTrue,
      );
      expect(
        YtDlpRunner.looksLikePlaylist('https://vimeo.com/album/123'),
        isTrue,
      );
      expect(
        YtDlpRunner.looksLikePlaylist('https://www.youtube.com/watch?v=abc'),
        isFalse,
      );
    });
  });

  group('parsePlaylistJson', () {
    test('parses entries, resolves relative URLs, dedupes and skips bad lines', () {
      final lines = [
        jsonEncode({
          'id': 'one',
          'title': '第一集',
          'webpage_url': 'https://example.com/v/1',
          'duration': 61,
          'uploader': '作者',
          'extractor_key': 'Example',
          'thumbnail': 'https://example.com/1.jpg',
        }),
        jsonEncode({
          'id': 'two',
          'title': '第二集',
          'url': '/v/2',
          'duration': 62,
          'extractor': 'Example',
          'thumbnails': [
            {'url': 'https://example.com/2-small.jpg'},
            {'url': 'https://example.com/2.jpg'},
          ],
        }),
        jsonEncode({
          'id': 'one',
          'title': '重复',
          'webpage_url': 'https://example.com/v/1',
        }),
        'not-json',
        jsonEncode({'title': '没有地址'}),
      ];

      final entries = YtDlpRunner.parsePlaylistJson(
        '${lines.take(2).join('\n')}\n${lines.skip(2).join('\n')}',
        'https://example.com/playlist/abc',
      );

      expect(entries, hasLength(2));
      expect(entries[0].title, '第一集');
      expect(entries[0].videoId, 'one');
      expect(entries[0].formats.single.formatId, 'bv*+ba/b');
      expect(entries[1].url, 'https://example.com/v/2');
      expect(entries[1].thumbnail, 'https://example.com/2.jpg');
    });

    test('respects the entry limit', () {
      final stdout = List.generate(
        5,
        (i) => jsonEncode({
          'id': '$i',
          'title': 'v$i',
          'webpage_url': 'https://example.com/v/$i',
        }),
      ).join('\n');
      expect(
        YtDlpRunner.parsePlaylistJson(
          stdout,
          'https://example.com/playlist',
          limit: 3,
        ),
        hasLength(3),
      );
    });
  });
}
