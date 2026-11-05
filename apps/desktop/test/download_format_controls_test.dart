import 'package:downie_test/data/models/download_task.dart';
import 'package:downie_test/data/models/format_option.dart';
import 'package:downie_test/features/downloads/widgets/download_format_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _formats = <FormatOption>[
  FormatOption(formatId: 'v1080', label: '1080p MP4', height: 1080, ext: 'mp4'),
  FormatOption(
    formatId: 'v1080-dup',
    label: '1080p MP4',
    height: 1080,
    ext: 'mp4',
  ),
  FormatOption(formatId: 'v720', label: '720p WEBM', height: 720, ext: 'webm'),
  FormatOption(formatId: 'v360', label: '360p MP4', height: 360, ext: 'mp4'),
  FormatOption(
    formatId: 'audio',
    label: 'MP3 纯音频',
    height: 0,
    ext: 'mp3',
    audioOnly: true,
  ),
];

DownloadTask _task({
  DownloadStatus status = DownloadStatus.failed,
  bool subtitles = false,
  bool cover = false,
  List<FormatOption> formats = _formats,
}) {
  return DownloadTask(
    id: 'task',
    url: 'https://example.com/v',
    title: 'Demo',
    thumbnail: '',
    extractor: 'YouTube',
    formatId: 'v1080',
    formatLabel: '1080p MP4',
    availableFormats: formats,
    height: 1080,
    ext: 'mp4',
    audioOnly: false,
    downloadSubtitles: subtitles,
    downloadCover: cover,
    status: status,
    createdAt: DateTime.fromMillisecondsSinceEpoch(1),
  );
}

Widget _app(
  DownloadTask task, {
  ValueChanged<FormatOption>? onFormatSelected,
  ValueChanged<bool>? onSubtitlesChanged,
  ValueChanged<bool>? onCoverChanged,
  VoidCallback? onRefreshFormats,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: DownloadFormatControls(
          task: task,
          onFormatSelected: onFormatSelected ?? (_) {},
          onSubtitlesChanged: onSubtitlesChanged ?? (_) {},
          onCoverChanged: onCoverChanged ?? (_) {},
          onRefreshFormats: onRefreshFormats ?? () {},
        ),
      ),
    ),
  );
}

void main() {
  group('downloadFormatOptions', () {
    test('lists video resolutions once, high to low, without audio', () {
      final options = downloadFormatOptions(_task());
      expect(options.map((f) => f.label), [
        '1080p MP4',
        '720p WEBM',
        '360p MP4',
      ]);
    });

    test('keeps audio formats when the task has no video', () {
      final options = downloadFormatOptions(
        _task(
          formats: const [
            FormatOption(
              formatId: 'audio',
              label: 'MP3 纯音频',
              height: 0,
              ext: 'mp3',
              audioOnly: true,
            ),
          ],
        ),
      );
      expect(options, hasLength(1));
      expect(options.single.audioOnly, isTrue);
    });

    test('empty available formats yields an empty menu', () {
      expect(downloadFormatOptions(_task(formats: const [])), isEmpty);
    });
  });

  group('DownloadFormatControls', () {
    testWidgets('renders an unchecked subtitle and cover box by default', (
      tester,
    ) async {
      await tester.pumpWidget(_app(_task()));
      expect(find.byIcon(Icons.check_box_outline_blank), findsNWidgets(2));
      expect(find.byIcon(Icons.check_box), findsNothing);
      expect(find.byTooltip('下载字幕'), findsOneWidget);
      expect(find.byTooltip('保存封面'), findsOneWidget);
    });

    testWidgets('shows checked boxes when the task already enabled them', (
      tester,
    ) async {
      await tester.pumpWidget(_app(_task(subtitles: true, cover: true)));
      expect(find.byIcon(Icons.check_box), findsNWidgets(2));
      expect(find.byTooltip('不下载字幕'), findsOneWidget);
      expect(find.byTooltip('不保存封面'), findsOneWidget);
    });

    testWidgets('failed task opens every resolution and reports the choice', (
      tester,
    ) async {
      FormatOption? selected;
      await tester.pumpWidget(
        _app(_task(), onFormatSelected: (format) => selected = format),
      );

      await tester.tap(find.text('1080p MP4'));
      await tester.pumpAndSettle();
      expect(find.text('720p WEBM'), findsOneWidget);
      expect(find.text('360p MP4'), findsOneWidget);
      expect(find.text('MP3 纯音频'), findsNothing);

      await tester.tap(
        find.widgetWithText(CheckedPopupMenuItem<FormatOption>, '720p WEBM'),
      );
      await tester.pumpAndSettle();
      expect(selected?.formatId, 'v720');
    });

    testWidgets('pending task can also change resolution', (tester) async {
      await tester.pumpWidget(_app(_task(status: DownloadStatus.pending)));
      await tester.tap(find.text('1080p MP4'));
      await tester.pumpAndSettle();
      expect(find.text('720p WEBM'), findsOneWidget);
    });

    testWidgets('failed task toggles subtitle and cover', (tester) async {
      bool? subtitles;
      bool? cover;
      await tester.pumpWidget(
        _app(
          _task(),
          onSubtitlesChanged: (value) => subtitles = value,
          onCoverChanged: (value) => cover = value,
        ),
      );

      await tester.tap(find.text('字幕'));
      await tester.tap(find.text('封面'));
      expect(subtitles, isTrue);
      expect(cover, isTrue);
    });

    testWidgets('downloading task can change resolution and extras', (
      tester,
    ) async {
      FormatOption? selected;
      bool? subtitles;
      bool? cover;
      await tester.pumpWidget(
        _app(
          _task(status: DownloadStatus.downloading),
          onFormatSelected: (value) => selected = value,
          onSubtitlesChanged: (value) => subtitles = value,
          onCoverChanged: (value) => cover = value,
        ),
      );

      await tester.tap(find.text('1080p MP4'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(CheckedPopupMenuItem<FormatOption>, '720p WEBM'),
      );
      await tester.pumpAndSettle();
      expect(selected?.formatId, 'v720');

      await tester.tap(find.text('字幕'));
      await tester.tap(find.text('封面'));
      expect(subtitles, isTrue);
      expect(cover, isTrue);
    });

    testWidgets('completed task can also change resolution and extras', (
      tester,
    ) async {
      var changed = false;
      await tester.pumpWidget(
        _app(
          _task(status: DownloadStatus.completed),
          onFormatSelected: (_) => changed = true,
          onSubtitlesChanged: (_) => changed = true,
          onCoverChanged: (_) => changed = true,
        ),
      );

      await tester.tap(find.text('1080p MP4'));
      await tester.pumpAndSettle();
      expect(find.text('720p WEBM'), findsOneWidget);

      await tester.tap(find.text('字幕'));
      await tester.tap(find.text('封面'));
      expect(changed, isTrue);
    });

    testWidgets('task without formats still allows subtitle/cover changes', (
      tester,
    ) async {
      var subtitles = false;
      await tester.pumpWidget(
        _app(
          _task(status: DownloadStatus.pending, formats: const []),
          onSubtitlesChanged: (value) => subtitles = value,
        ),
      );

      expect(find.text('1080p MP4'), findsOneWidget);
      await tester.tap(find.text('字幕'));
      expect(subtitles, isTrue);
    });

    testWidgets('empty format list offers a re-parse action', (tester) async {
      var refreshed = false;
      await tester.pumpWidget(
        _app(
          _task(formats: const []),
          onRefreshFormats: () => refreshed = true,
        ),
      );

      await tester.tap(find.text('1080p MP4'));
      await tester.pumpAndSettle();
      expect(find.text('重新获取分辨率'), findsOneWidget);

      await tester.tap(find.widgetWithText(PopupMenuItem<String>, '重新获取分辨率'));
      await tester.pumpAndSettle();
      expect(refreshed, isTrue);
    });
  });
}
