import 'package:downie_test/core/sites/plugins/weibo_plugin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('matches Weibo video and status links', () {
    final plugin = WeiboPlugin();
    bool match(String url) => plugin.matches(Uri.parse(url), url);
    expect(
      match('https://h5.video.weibo.com/show/1034:4574447982805003'),
      isTrue,
    );
    expect(
      match('https://weibo.com/tv/show/1034:4521925930582041'),
      isTrue,
    );
    expect(match('https://weibo.com/1768267801/Jm1dRuUOj'), isTrue);
    expect(match('https://weibo.com/'), isFalse);
    expect(match('https://example.com/tv/show/1'), isFalse);
  });

  test('parses media_info stream URLs', () {
    final info = WeiboPlugin.parseStatus(
      {
        'text_raw': '测试微博视频 <a>链接</a>',
        'user': {'screen_name': '作者'},
        'page_info': {
          'page_pic': 'https://c.example/cover.jpg',
          'media_info': {
            'stream_url_hd': 'https://v.example/hd.mp4',
            'stream_url': 'https://v.example/sd.mp4',
            'duration': 61000,
          },
        },
      },
      id: '1034:4574447982805003',
      pageUrl: 'https://weibo.com/tv/show/1034:4574447982805003',
    );
    expect(info.extractor, 'Weibo');
    expect(info.title, '测试微博视频 链接');
    expect(info.uploader, '作者');
    expect(info.duration, 61);
    expect(info.thumbnail, 'https://c.example/cover.jpg');
    expect(info.formats, hasLength(2));
    expect(info.formats.first.formatId, 'https://v.example/hd.mp4');
    expect(info.formats.first.height, 720);
  });
}
