import 'package:downie_test/core/sites/plugins/tiktok_plugin.dart';
import 'package:downie_test/core/sites/site_plugin.dart';
import 'package:flutter_test/flutter_test.dart';

const _html = '''
<html><body>
<script id="__UNIVERSAL_DATA_FOR_REHYDRATION__" type="application/json">
{"__DEFAULT_SCOPE__":{"webapp.video-detail":{"itemInfo":{"itemStruct":{
"id":"6756589355923410178",
"desc":"lucu ya monyet",
"video":{
  "duration":14,
  "height":1024,
  "cover":"https://p16.example/cover.jpg",
  "playAddr":"https://v16.example/play.mp4",
  "bitrateInfo":[
    {"Bitrate":1466976,"GearName":"normal_540_0","PlayAddr":{"DataSize":"2652843","Width":576,"Height":1024,"UrlList":["https://v16.example/540.mp4"]}},
    {"Bitrate":3000000,"GearName":"normal_720_0","PlayAddr":{"DataSize":"5262843","Width":720,"Height":1280,"UrlList":["https://v16.example/720.mp4"]}}
  ]
},
"author":{"nickname":"Protein Hewani"}
}}}}}
</script>
</body></html>
''';

void main() {
  test('matches TikTok video and short links', () {
    final plugin = TikTokPlugin();
    expect(
      plugin.matches(Uri.parse('https://www.tiktok.com/@user/video/123'), ''),
      isTrue,
    );
    expect(plugin.matches(Uri.parse('https://vm.tiktok.com/abc'), ''), isTrue);
    expect(
      plugin.matches(
        Uri.parse(
          'https://www.tiktok.com/shortdrama/episode/7666394344965854229/7',
        ),
        '',
      ),
      isTrue,
    );
    expect(
      plugin.matches(Uri.parse('https://www.tiktok.com/@user'), ''),
      isFalse,
    );
    expect(
      plugin.matches(Uri.parse('https://example.com/video/123'), ''),
      isFalse,
    );
  });

  test('parses short drama episode URLs', () {
    final parsed = TikTokPlugin.shortDramaFromUrl(
      'https://www.tiktok.com/shortdrama/episode/7666394344965854229/7'
      '?is_from_webapp=1&sender_device=pc',
    );
    expect(parsed?.dramaId, '7666394344965854229');
    expect(parsed?.episode, 7);

    expect(
      TikTokPlugin.shortDramaFromUrl(
        'https://www.tiktok.com/shortdrama/episode/abc/7',
      ),
      isNull,
    );
    expect(
      TikTokPlugin.shortDramaFromUrl(
        'https://www.tiktok.com/shortdrama/episode/123/0',
      ),
      isNull,
    );
    expect(
      TikTokPlugin.shortDramaFromUrl('https://www.tiktok.com/@user/video/123'),
      isNull,
    );
  });

  test('parses a short drama API item into formats', () {
    final info = TikTokPlugin.parseVideoItem(
      {
        'id': '7666394435252489492',
        'desc': 'Giant Clam',
        'author': {
          'nickname': 'HappyShortDrama_A',
          'uniqueId': 'fantasyminidrama',
        },
        'video': {
          'duration': 64,
          'height': 1080,
          'cover': 'https://p16.example/cover.jpg',
          'bitrateInfo': [
            {
              'Bitrate': 3000000,
              'GearName': 'normal_720_0',
              'PlayAddr': {
                'DataSize': '2652843',
                'Width': 720,
                'Height': 1280,
                'UrlList': ['https://v16.example/720.mp4'],
              },
            },
            {
              'Bitrate': 6000000,
              'GearName': 'normal_1080_0',
              'PlayAddr': {
                'DataSize': '5262843',
                'Width': 1080,
                'Height': 1920,
                'UrlList': ['https://v16.example/1080.mp4'],
              },
            },
          ],
        },
      },
      pageUrl:
          'https://www.tiktok.com/@fantasyminidrama/video/7666394435252489492',
      titleOverride: 'The Secret Ingredient · EP7 · Giant Clam',
    );

    expect(info.videoId, '7666394435252489492');
    expect(info.title, 'The Secret Ingredient · EP7 · Giant Clam');
    expect(info.uploader, 'HappyShortDrama_A');
    expect(info.duration, 64);
    expect(info.thumbnail, 'https://p16.example/cover.jpg');
    expect(info.formats, hasLength(2));
    expect(info.formats.first.formatId, 'https://v16.example/1080.mp4');
    expect(info.formats.first.height, 1920);
    expect(info.formats.first.fileSize, 5262843);
  });

  test('short drama item without playback addresses throws', () {
    expect(
      () => TikTokPlugin.parseVideoItem({
        'id': '7666394435252489492',
        'desc': 'Giant Clam',
        'video': {'duration': 64, 'playAddr': null, 'bitrateInfo': null},
      }),
      throwsA(isA<SitePluginException>()),
    );
  });

  test('parses hydration data into formats', () {
    final info = TikTokPlugin.parseHydration(
      _html,
      pageUrl: 'https://www.tiktok.com/@user/video/6756589355923410178',
    );
    expect(info.extractor, 'TikTok');
    expect(info.videoId, '6756589355923410178');
    expect(info.title, 'lucu ya monyet');
    expect(info.uploader, 'Protein Hewani');
    expect(info.duration, 14);
    expect(info.formats, hasLength(2));
    expect(info.formats.first.formatId, 'https://v16.example/720.mp4');
    expect(info.formats.first.height, 1280);
    expect(info.formats.first.fileSize, 5262843);
    expect(info.formats.first.label, '1280p');
    expect(info.formats[1].formatId, 'https://v16.example/540.mp4');
  });
}
