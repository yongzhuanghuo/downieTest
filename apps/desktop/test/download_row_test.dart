import 'package:downie_test/data/models/download_task.dart';
import 'package:downie_test/data/models/format_option.dart';
import 'package:downie_test/features/downloads/download_provider.dart';
import 'package:downie_test/features/downloads/widgets/download_row.dart';
import 'package:downie_test/shared/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingNotifier extends DownloadListNotifier {
  _RecordingNotifier(super.ref, super.initial) : super.test();

  FormatOption? format;
  bool? subtitles;
  bool? cover;
  var refreshes = 0;

  @override
  Future<void> setFormat(String id, FormatOption value) async {
    format = value;
  }

  @override
  Future<void> setDownloadSubtitles(String id, bool value) async {
    subtitles = value;
  }

  @override
  Future<void> setDownloadCover(String id, bool value) async {
    cover = value;
  }

  @override
  Future<String?> refreshFormats(String id) async {
    refreshes++;
    return null;
  }
}

const _formats = <FormatOption>[
  FormatOption(formatId: 'v1080', label: '1080p MP4', height: 1080, ext: 'mp4'),
  FormatOption(formatId: 'v720', label: '720p WEBM', height: 720, ext: 'webm'),
];

DownloadTask _task({List<FormatOption> formats = _formats}) {
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
    status: DownloadStatus.failed,
    createdAt: DateTime.fromMillisecondsSinceEpoch(1),
  );
}

Future<_RecordingNotifier> _pumpRow(
  WidgetTester tester,
  DownloadTask task,
) async {
  late _RecordingNotifier notifier;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        downloadListProvider.overrideWith((ref) {
          notifier = _RecordingNotifier(ref, [task]);
          return notifier;
        }),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: SizedBox(width: 900, child: DownloadRow(task: task)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return notifier;
}

void main() {
  testWidgets(
    'card sends resolution, subtitle and cover choices to the queue',
    (tester) async {
      final notifier = await _pumpRow(tester, _task());

      await tester.tap(find.text('1080p MP4'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(CheckedPopupMenuItem<FormatOption>, '720p WEBM'),
      );
      await tester.pumpAndSettle();
      expect(notifier.format?.formatId, 'v720');

      await tester.tap(find.text('字幕'));
      await tester.tap(find.text('封面'));
      expect(notifier.subtitles, isTrue);
      expect(notifier.cover, isTrue);
    },
  );

  testWidgets('card offers re-parse when the restored task has no formats', (
    tester,
  ) async {
    final notifier = await _pumpRow(tester, _task(formats: const []));

    await tester.tap(find.text('1080p MP4'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PopupMenuItem<String>, '重新获取分辨率'));
    await tester.pumpAndSettle();
    expect(notifier.refreshes, 1);
  });
}
