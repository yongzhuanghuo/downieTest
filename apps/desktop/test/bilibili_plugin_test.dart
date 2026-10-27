import 'package:downie_test/core/sites/plugin_registry.dart';
import 'package:downie_test/core/sites/plugins/bilibili_plugin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('matches bangumi season and episode links', () {
    final plugin = BilibiliPlugin();
    bool match(String url) => plugin.matches(Uri.parse(url), url);
    expect(match('https://www.bilibili.com/bangumi/play/ss28747'), isTrue);
    expect(match('https://www.bilibili.com/bangumi/play/ep123456'), isTrue);
    expect(BilibiliPlugin.looksLikeSeason(
      'https://www.bilibili.com/bangumi/play/ss28747',
    ), isTrue);
    expect(BilibiliPlugin.looksLikeSeason(
      'https://www.bilibili.com/bangumi/play/ep123456',
    ), isFalse);
    expect(BilibiliPlugin.looksLikeSeason(
      'https://www.bilibili.com/video/BV1xx411c7mD',
    ), isFalse);
    expect(BilibiliPlugin.looksLikeVideo(
      'https://www.bilibili.com/video/BV1xx411c7mD?p=2',
    ), isTrue);
    expect(BilibiliPlugin.looksLikeVideo(
      'https://www.bilibili.com/video/av12345',
    ), isTrue);
    expect(BilibiliPlugin.looksLikeVideo(
      'https://www.bilibili.com/bangumi/play/ss28747',
    ), isFalse);
  });

  test('extracts episode URLs in order and de-duplicates', () {
    final urls = BilibiliPlugin.episodeUrlsFromSeason({
      'result': {
        'episodes': [
          {'id': 101, 'cid': 1},
          {'ep_id': 102, 'cid': 2},
          {'id': 101, 'cid': 1},
          {'id': 0, 'cid': 3},
          {'title': '没有 id'},
        ],
      },
    });
    expect(urls, [
      'https://www.bilibili.com/bangumi/play/ep101',
      'https://www.bilibili.com/bangumi/play/ep102',
    ]);
  });

  test('extracts episodes from sections when episodes is absent', () {
    final urls = BilibiliPlugin.episodeUrlsFromSeason({
      'episodes': const [],
      'sections': [
        {
          'episodes': [
            {'id': 201},
            {'id': 202},
          ],
        },
      ],
    });
    expect(urls, hasLength(2));
    expect(urls.last, endsWith('ep202'));
  });

  test('registry routes bangumi links to the bangumi plugin', () {
    final season = PluginRegistry.instance
        .find('https://www.bilibili.com/bangumi/play/ss28747');
    expect(season, isNotNull);
    expect(season!.id, 'BilibiliBangumi');

    final episode = PluginRegistry.instance
        .find('https://www.bilibili.com/bangumi/play/ep123456');
    expect(episode!.id, 'BilibiliBangumi');

    final video = PluginRegistry.instance
        .find('https://www.bilibili.com/video/BV1xx411c7mD');
    expect(video!.id, 'Bilibili');

    expect(PluginRegistry.instance.byId('BilibiliBangumi'), isNotNull);
  });
}
