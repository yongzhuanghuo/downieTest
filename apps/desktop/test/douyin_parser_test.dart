import 'dart:convert';

import 'package:downie_test/core/engine/douyin_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cacheCaptured parses aweme_detail and caches by id', () {
    const id = '7701030749851389219';
    final body = jsonEncode({
      'aweme_detail': {
        'aweme_id': id,
        'desc': '测试视频',
        'duration': 89305,
        'author': {'nickname': '作者'},
        'video': {
          'cover': {
            'url_list': ['https://p3.douyinpic.com/cover.jpeg'],
          },
          'bit_rate': [
            {
              'gear_name': 'normal_1080_0',
              'is_h265': 0,
              'play_addr': {
                'height': 1080,
                'url_list': ['https://v26.douyinvod.com/video.mp4'],
              },
            },
          ],
        },
      },
    });

    expect(
      DouyinParser.cacheCaptured('https://www.douyin.com/video/$id', body),
      isTrue,
    );

    final info = DouyinParser.cachedVideo('https://www.douyin.com/video/$id');
    expect(info, isNotNull);
    expect(info!.title, '测试视频');
    expect(info.uploader, '作者');
    expect(info.duration, 89);
    expect(info.formats, hasLength(1));
    expect(info.formats.single.height, 1080);
    expect(info.formats.single.label, '1080p');
    expect(info.formats.single.formatId, 'https://v26.douyinvod.com/video.mp4');
    // 缓存也按 id 命中
    expect(DouyinParser.cachedVideo(id), isNotNull);
    expect(DouyinParser.cachedVideo('https://v.douyin.com/abc/'), isNull);
  });

  test('pageVideoId only matches explicit video params', () {
    expect(
      DouyinParser.pageVideoId(
        'https://www.douyin.com/video/7701030749851389219?previous_page=web',
      ),
      '7701030749851389219',
    );
    expect(
      DouyinParser.pageVideoId(
        'https://www.douyin.com/user/x?modal_id=7701030749851389219',
      ),
      '7701030749851389219',
    );
    // 短链里的数字不能被误当成 aweme_id
    expect(
      DouyinParser.pageVideoId('https://v.douyin.com/abc123456789012345/'),
      isNull,
    );
  });

  test('cacheMedia creates a merge format and caches under short link', () {
    const short = 'https://v.douyin.com/media-fallback-test/';
    expect(
      DouyinParser.cacheMedia(
        short,
        videoUrl: 'https://v26.douyinvod.com/media-video-avc1',
        audioUrl: 'https://v26.douyinvod.com/media-audio-und-mp4a',
        title: '标题 - 抖音',
        height: 720,
      ),
      isTrue,
    );

    final info = DouyinParser.cachedVideo(short);
    expect(info, isNotNull);
    expect(info!.title, '标题');
    expect(info.formats.single.height, 720);
    expect(info.formats.single.label, '720p MP4（合并）');
    expect(
      info.formats.single.formatId,
      'https://v26.douyinvod.com/media-video-avc1\n'
      'https://v26.douyinvod.com/media-audio-und-mp4a',
    );
  });
}
