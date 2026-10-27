import 'dart:convert';

import 'package:downie_test/core/sites/site_coverage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final data = SiteCoverageData.fromJson(
    jsonDecode(jsonEncode({
      'total': 3,
      'counts': {
        'native': 1,
        'native_partial': 0,
        'ytdlp': 1,
        'generic': 1,
        'drm': 0,
      },
      'sites': [
        {
          'site': 'Douyin',
          'className': 'DouyinDownloader',
          'domains': ['https://www.douyin.com'],
          'status': 'native',
          'verified': true,
          'priority': 'P0',
          'ytdlpExtractors': ['Douyin'],
          'notes': '',
        },
        {
          'site': 'YouTube',
          'className': 'YouTubeDownloader',
          'domains': ['https://www.youtube.com'],
          'status': 'ytdlp',
          'verified': false,
          'priority': 'P0',
          'ytdlpExtractors': ['youtube'],
          'notes': '',
        },
        {
          'site': 'UnknownSite',
          'className': 'UnknownSiteDownloader',
          'domains': [],
          'status': 'generic',
          'verified': false,
          'priority': 'P1',
          'ytdlpExtractors': [],
          'notes': '未复刻',
        },
      ],
    }) as Map<String, dynamic>),
  );

  test('counts and status labels', () {
    expect(data.total, 3);
    expect(data.counts[SiteCoverageStatus.native], 1);
    expect(data.counts[SiteCoverageStatus.ytdlp], 1);
    expect(data.sites, hasLength(3));
    expect(
      SiteCoverageStatus.ytdlp.label,
      'yt-dlp（待验证）',
    );
    expect(data.sites.first.verified, isTrue);
  });

  test('search matches site, domain and extractor', () {
    expect(data.sites.first.matches('douyin'), isTrue);
    expect(data.sites.first.matches('youtube.com'), isFalse);
    expect(data.sites[1].matches('youtube.com'), isTrue);
    expect(data.sites[1].matches('YouTube'), isTrue);
    expect(data.sites[2].matches('不存在'), isFalse);
  });
}
