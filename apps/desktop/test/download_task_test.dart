import 'package:downie_test/data/models/download_task.dart';
import 'package:downie_test/data/models/format_option.dart';
import 'package:flutter_test/flutter_test.dart';

DownloadTask _task() => DownloadTask(
      id: '1',
      url: 'https://example.com/v',
      title: 'Demo',
      thumbnail: '',
      extractor: 'GenericWeb',
      formatId: 'hls',
      formatLabel: 'HLS',
      height: 1080,
      ext: 'mp4',
      audioOnly: false,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1),
    );

void main() {
  test('postprocessing survives map round-trip', () {
    final task = _task().copyWith(
      postprocessing: PostprocessingMode.audio,
      availableFormats: const [
        FormatOption(formatId: 'a', label: '720p', height: 720, ext: 'mp4'),
      ],
    );
    final map = task.toMap();
    expect(map['postprocessing'], 'audio');

    final restored = DownloadTask.fromMap(map);
    expect(restored.postprocessing, PostprocessingMode.audio);
    expect(restored.availableFormats, isEmpty); // 格式列表不持久化
  });

  test('rename title', () {
    final task = _task().copyWith(title: 'New title');
    expect(task.title, 'New title');
    expect(task.toMap()['title'], 'New title');
  });

  test('format fields can be replaced', () {
    final task = _task().copyWith(
      formatId: 'b',
      formatLabel: '4K',
      height: 2160,
      ext: 'mp4',
      audioOnly: false,
    );
    expect(task.formatId, 'b');
    expect(task.formatLabel, '4K');
    expect(task.height, 2160);
  });
}
