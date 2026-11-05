import 'package:downie_test/core/sites/plugins/xiaohongshu_plugin.dart';
import 'package:downie_test/core/sites/site_plugin.dart';
import 'package:flutter_test/flutter_test.dart';

const _html = '''
<!doctype html><html><head>
<meta property="og:image" content="//picasso-static.xiaohongshu.com/logo.png">
<meta property="og:image" content="http://sns-webpic-qc.xhscdn.com/cover.jpg">
<meta property="og:videotime" content="01:57">
<meta property="og:videoquality" content="高清">
<meta property="og:title" content="绝望周末系列～ - 小红书">
<meta property="og:video" content="https://sns-video-v3.xhscdn.com/stream/1/video.mp4?sign=abc&amp;t=123">
</head><body></body></html>
''';

void main() {
  test('matches Xiaohongshu note and share hosts', () {
    final plugin = XiaohongshuPlugin();
    expect(
      plugin.matches(
        Uri.parse('https://www.xiaohongshu.com/discovery/item/abc'),
        '',
      ),
      isTrue,
    );
    expect(plugin.matches(Uri.parse('https://xhslink.cn/o/abc'), ''), isTrue);
    expect(plugin.matches(Uri.parse('https://xhslink.com/a/abc'), ''), isTrue);
    expect(
      plugin.matches(Uri.parse('https://example.com/note/1'), ''),
      isFalse,
    );
  });

  test('parses og tags into a downloadable video', () {
    final info = XiaohongshuPlugin.parseHtml(
      _html,
      pageUrl:
          'https://www.xiaohongshu.com/discovery/item/6ae785930000000025001dde',
    );

    expect(info.extractor, 'Xiaohongshu');
    expect(info.videoId, '6ae785930000000025001dde');
    expect(info.title, '绝望周末系列～');
    expect(info.duration, 117);
    expect(info.thumbnail, 'http://sns-webpic-qc.xhscdn.com/cover.jpg');
    expect(info.formats, hasLength(1));
    expect(
      info.formats.single.formatId,
      'https://sns-video-v3.xhscdn.com/stream/1/video.mp4?sign=abc&t=123',
    );
    expect(info.formats.single.label, '原画 MP4');
  });

  test('login wall without og:video asks for login', () {
    expect(
      () => XiaohongshuPlugin.parseHtml(
        '<html><body>登录后查看 小红书</body></html>',
        pageUrl: 'https://www.xiaohongshu.com/discovery/item/abc',
      ),
      throwsA(
        isA<SitePluginException>().having(
          (e) => e.requiresLogin,
          'requiresLogin',
          isTrue,
        ),
      ),
    );
  });

  test('image note without video reports no video', () {
    expect(
      () => XiaohongshuPlugin.parseHtml(
        '<html><body>图片笔记</body></html>',
        pageUrl: 'https://www.xiaohongshu.com/discovery/item/abc',
      ),
      throwsA(
        isA<SitePluginException>().having(
          (e) => e.requiresLogin,
          'requiresLogin',
          isFalse,
        ),
      ),
    );
  });
}
