import 'package:downie_test/core/storage/site_cookies.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SiteCookies.siteForUrl', () {
    test('matches registered domains and subdomains', () {
      expect(
        SiteCookies.siteForUrl('https://www.youtube.com/watch?v=abc')?.id,
        'youtube',
      );
      expect(
        SiteCookies.siteForUrl('https://youtu.be/abc')?.id,
        'youtube',
      );
      expect(
        SiteCookies.siteForUrl('https://x.com/user/status/1')?.id,
        'twitter',
      );
      expect(
        SiteCookies.siteForUrl('https://space.bilibili.com/1')?.id,
        'bilibili',
      );
    });

    test('does not match lookalike domains or unknown sites', () {
      expect(
        SiteCookies.siteForUrl('https://notyoutube.com/watch?v=abc'),
        isNull,
      );
      expect(
        SiteCookies.siteForUrl('https://example.com/video'),
        isNull,
      );
    });
  });
}
