import 'package:downie_test/core/storage/file_naming.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('renderFilenameTemplate', () {
    test('uses title and strips path separators', () {
      expect(
        renderFilenameTemplate(
          '{title}',
          title: 'a/b:c*?"<>|',
          extractor: 'YouTube',
          url: 'https://example.com/v',
          now: DateTime(2026, 10, 26),
        ),
        'a_b_c______',
      );
    });

    test('expands all placeholders', () {
      final name = renderFilenameTemplate(
        '{date}_{extractor}_{id}_{title}',
        title: '视频',
        extractor: 'Bilibili',
        url: 'https://example.com/v',
        now: DateTime(2026, 10, 26),
      );
      expect(name, startsWith('2026-10-26_Bilibili_'));
      expect(name, endsWith('_视频'));
      expect(shortUrlId('https://example.com/v'), hasLength(8));
    });

    test('expands original endpoint name without extension', () {
      final name = renderFilenameTemplate(
        '{original}_{title}',
        title: '视频',
        extractor: 'Example',
        url: 'https://cdn.example.com/media/clip.mp4?token=1',
        now: DateTime(2026, 10, 26),
      );
      expect(name, 'clip_视频');
      expect(
        originalFileName('https://example.com/%E8%A7%86%E9%A2%91.webm'),
        '视频',
      );
      expect(originalFileName('https://example.com/'), '');
    });

    test('falls back when title is empty', () {
      final name = renderFilenameTemplate(
        '{title}',
        title: '',
        extractor: 'YouTube',
        url: 'https://example.com/v',
        now: DateTime(2026, 10, 26),
      );
      expect(name, 'video_${shortUrlId('https://example.com/v')}');
    });

    test('removes trailing dots/spaces and limits length', () {
      expect(sanitizePathSegment('name...  '), 'name');
      final long = renderFilenameTemplate(
        '{title}',
        title: 'x' * 300,
        extractor: 'YouTube',
        url: 'https://example.com/v',
      );
      expect(long.length, lessThanOrEqualTo(160));
    });
  });
}
