import 'package:downie_test/core/sites/generic_html_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('extracts meta, video, JSON-LD and escaped URLs', () {
    const html = '''
<html><head>
<meta property="og:title" content="Demo">
<meta property="og:video" content="https://cdn.example.com/a.mp4?x=1&amp;y=2">
<meta name="twitter:player:stream" content="//cdn.example.com/b.m3u8">
</head><body>
<video src="/media/c.mp4"></video>
<script>var u = "https:\\/\\/cdn.example.com\\/d.mpd";</script>
<script type="application/ld+json">{"contentUrl":"https://cdn.example.com/e.flv"}</script>
</body></html>
''';

    final urls = GenericHtmlExtractor.extractMediaUrls(
      html,
      'https://example.com/page',
    );

    expect(urls, contains('https://cdn.example.com/a.mp4?x=1&y=2'));
    expect(urls, contains('https://cdn.example.com/b.m3u8'));
    expect(urls, contains('https://example.com/media/c.mp4'));
    expect(urls, contains('https://cdn.example.com/d.mpd'));
    expect(urls, contains('https://cdn.example.com/e.flv'));
  });

  test('extracts lazy-loaded sources and itemprop/JSON video fields', () {
    const html = '''
<html><head>
<meta itemprop="contentUrl" content="https://cdn.example.com/a.mp4">
</head><body>
<video data-src="/media/lazy.mp4"></video>
<source data-url="https://cdn.example.com/b.m3u8">
<script>window.__DATA__ = {"video_url":"https://cdn.example.com/c.mp4"};</script>
</body></html>
''';
    final urls = GenericHtmlExtractor.extractMediaUrls(
      html,
      'https://example.com/page',
    );
    expect(urls, contains('https://cdn.example.com/a.mp4'));
    expect(urls, contains('https://example.com/media/lazy.mp4'));
    expect(urls, contains('https://cdn.example.com/b.m3u8'));
    expect(urls, contains('https://cdn.example.com/c.mp4'));
  });

  test('deduplicates and preserves order', () {
    const html = '''
<video src="https://cdn.example.com/a.mp4"></video>
<source src="https://cdn.example.com/a.mp4">
<source src="https://cdn.example.com/b.mp4">
''';
    final urls = GenericHtmlExtractor.extractMediaUrls(
      html,
      'https://example.com/',
    );
    expect(urls, [
      'https://cdn.example.com/a.mp4',
      'https://cdn.example.com/b.mp4',
    ]);
  });

  test('ignores non-media pages', () {
    final urls = GenericHtmlExtractor.extractMediaUrls(
      '<html><body>hello</body></html>',
      'https://example.com/',
    );
    expect(urls, isEmpty);
  });
}
