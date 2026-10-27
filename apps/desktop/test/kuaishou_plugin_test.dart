import 'package:downie_test/core/sites/plugins/kuaishou_plugin.dart';
import 'package:flutter_test/flutter_test.dart';

const _html = '''
<html><body>
<script>window.__APOLLO_STATE__ = {"defaultClient":{
"VisionVideoDetailPhoto:3xtjq56v8axfvue":{
  "photoId":"3xtjq56v8axfvue",
  "caption":"测试快手视频",
  "photoUrl":"https://v.example/kuaishou.mp4",
  "coverUrl":"https://c.example/cover.jpg",
  "height":1280,
  "duration":12000
}}};</script>
</body></html>
''';

void main() {
  test('matches Kuaishou video links only', () {
    final plugin = KuaishouPlugin();
    expect(
      plugin.matches(
        Uri.parse('https://www.kuaishou.com/short-video/3xtjq56v8axfvue'),
        '',
      ),
      isTrue,
    );
    expect(plugin.matches(Uri.parse('https://v.kuaishou.com/abc'), ''), isTrue);
    expect(plugin.matches(Uri.parse('https://www.kuaishou.com/'), ''), isFalse);
    expect(
      plugin.matches(Uri.parse('https://live.kuaishou.com/u/abc'), ''),
      isFalse,
    );
  });

  test('parses Apollo state', () {
    final info = KuaishouPlugin.parseHtml(
      _html,
      pageUrl: 'https://www.kuaishou.com/short-video/3xtjq56v8axfvue',
    );
    expect(info.extractor, 'Kuaishou');
    expect(info.videoId, '3xtjq56v8axfvue');
    expect(info.title, '测试快手视频');
    expect(info.duration, 12);
    expect(info.thumbnail, 'https://c.example/cover.jpg');
    expect(info.formats, hasLength(1));
    expect(info.formats.single.formatId, 'https://v.example/kuaishou.mp4');
    expect(info.formats.single.height, 1280);
  });
}
