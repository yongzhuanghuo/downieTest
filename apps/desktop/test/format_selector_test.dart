import 'package:downie_test/core/sites/format_selector.dart';
import 'package:downie_test/data/models/format_option.dart';
import 'package:downie_test/data/models/video_info.dart';
import 'package:flutter_test/flutter_test.dart';

VideoInfo info(List<FormatOption> formats) => VideoInfo(
      url: 'https://example.com/v',
      title: 'Demo',
      duration: 10,
      uploader: '',
      thumbnail: '',
      extractor: 'Test',
      videoId: '1',
      formats: formats,
    );

const f360 = FormatOption(
  formatId: '360',
  label: '360p',
  height: 360,
  ext: 'mp4',
);
const f720webm = FormatOption(
  formatId: '720w',
  label: '720p WEBM',
  height: 720,
  ext: 'webm',
);
const f720mp4 = FormatOption(
  formatId: '720m',
  label: '720p MP4',
  height: 720,
  ext: 'mp4',
);
const f1080 = FormatOption(
  formatId: '1080',
  label: '1080p',
  height: 1080,
  ext: 'mp4',
);
const f1080webm = FormatOption(
  formatId: '1080w',
  label: '1080p WEBM',
  height: 1080,
  ext: 'webm',
);
const audio = FormatOption(
  formatId: 'audio',
  label: 'MP3',
  height: 0,
  ext: 'mp3',
  audioOnly: true,
);

void main() {
  test('auto picks highest video, never audio-only', () {
    final selected = selectFormatForDownload(
      info([f360, f720webm, f1080, audio]),
    );
    expect(selected!.formatId, '1080');
  });

  test('prefers MP4 at the same resolution', () {
    final selected = selectFormatForDownload(
      info([f720webm, f720mp4, f360]),
      preferMp4: true,
    );
    expect(selected!.formatId, '720m');
  });

  test('force MP4 sacrifices higher resolution in other containers', () {
    final selected = selectFormatForDownload(
      info([f1080webm, f720webm, f720mp4, f360]),
      forceMp4: true,
    );
    expect(selected!.formatId, '720m');
  });

  test('force MP4 falls back to available formats when none is MP4', () {
    final selected = selectFormatForDownload(
      info([f1080webm, f720webm]),
      forceMp4: true,
    );
    expect(selected!.formatId, '1080w');
  });

  test('quality limit selects highest within limit', () {
    final selected = selectFormatForDownload(
      info([f360, f720webm, f720mp4, f1080]),
      qualityPreference: 4, // 720p
    );
    expect(selected!.height, 720);
  });

  test('all formats above limit fall back to the smallest', () {
    final selected = selectFormatForDownload(
      info([f1080, f720mp4]),
      qualityPreference: 3, // 480p
    );
    expect(selected!.height, 720);
  });

  test('audio-only list still returns a format', () {
    final selected = selectFormatForDownload(info([audio]));
    expect(selected!.formatId, 'audio');
  });

  test('empty list returns null', () {
    expect(selectFormatForDownload(info(const [])), isNull);
  });
}
