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

  test('duration survives map round-trip', () {
    final task = _task().copyWith(duration: 738);
    expect(task.duration, 738);
    expect(DownloadTask.fromMap(task.toMap()).duration, 738);
  });

  test('priority and subtitle flags survive map round-trip', () {
    final task = _task().copyWith(
      priority: DownloadPriority.high,
      downloadSubtitles: true,
      downloadCover: true,
    );
    final map = task.toMap();
    expect(map['priority'], DownloadPriority.high.index);

    final restored = DownloadTask.fromMap(map);
    expect(restored.priority, DownloadPriority.high);
    expect(restored.downloadSubtitles, isTrue);
    expect(restored.downloadCover, isTrue);
  });

  test('custom postprocessing survives map round-trip', () {
    final task = _task().copyWith(postprocessing: PostprocessingMode.custom);
    expect(
      DownloadTask.fromMap(task.toMap()).postprocessing,
      PostprocessingMode.custom,
    );
  });

  test('throttle survives map round-trip', () {
    final task = _task().copyWith(throttleKbps: 1000);
    expect(DownloadTask.fromMap(task.toMap()).throttleKbps, 1000);
  });

  test('connections survive map round-trip', () {
    final task = _task().copyWith(connections: 8);
    expect(DownloadTask.fromMap(task.toMap()).connections, 8);
    expect(DownloadTask.fromMap(task.toMap()).toMap()['connections'], 8);
  });

  test('per-task destination survives map round-trip', () {
    final task = _task().copyWith(destinationDir: '/tmp/videos');
    expect(
      DownloadTask.fromMap(task.toMap()).destinationDir,
      '/tmp/videos',
    );
  });

  test('copyWith can clear nullable fields', () {
    final task = _task().copyWith(
      error: 'boom',
      outputPath: '/tmp/a.mp4',
      startedAt: DateTime.fromMillisecondsSinceEpoch(2),
      completedAt: DateTime.fromMillisecondsSinceEpoch(3),
    );
    final cleared = task.copyWith(
      error: null,
      outputPath: null,
      startedAt: null,
      completedAt: null,
      progress: null,
    );
    expect(cleared.error, isNull);
    expect(cleared.outputPath, isNull);
    expect(cleared.startedAt, isNull);
    expect(cleared.completedAt, isNull);
    expect(cleared.progress, isNull);
  });

  test('paused is neither running nor finished', () {
    final paused = _task().copyWith(status: DownloadStatus.paused);
    expect(paused.isPaused, isTrue);
    expect(paused.isRunning, isFalse);
    expect(paused.isFinished, isFalse);
    expect(paused.statusText, '已暂停');
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
