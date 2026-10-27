import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../home/home_provider.dart';
import '../license/license_provider.dart';
import '../license/license_window.dart';
import '../settings/settings_provider.dart';
import 'add_urls_panel.dart';
import 'download_provider.dart';

enum QuickAddResult { added, needsInput, failed, trialEnded }

/// 当前正在后台解析的快速添加任务数（用于右上角「加载中…」胶囊）。
final quickAddLoadingProvider = StateProvider<int>((ref) => 0);

/// 点击底部 +：优先直接解析剪贴板里的链接，不弹添加窗口。
Future<QuickAddResult> quickAddFromClipboard(
  BuildContext context,
  WidgetRef ref,
) async {
  final data = await Clipboard.getData('text/plain');
  final text = data?.text?.trim() ?? '';
  if (text.isEmpty) {
    if (context.mounted) await AddUrlsPanel.show(context);
    return QuickAddResult.needsInput;
  }
  return quickAddText(context, ref, text);
}

/// 解析一段文本里的第一个视频链接并直接入队。
Future<QuickAddResult> quickAddText(
  BuildContext context,
  WidgetRef ref,
  String text,
) async {
  final target = wholeHttpUrl(text) ?? firstVideoUrl(text);
  if (target == null) {
    if (context.mounted) {
      await AddUrlsPanel.show(context, initialText: text);
    }
    return QuickAddResult.needsInput;
  }

  final loading = ref.read(quickAddLoadingProvider.notifier);
  loading.state++;
  var loadingActive = true;
  void finishLoading() {
    if (!loadingActive) return;
    loadingActive = false;
    loading.state = (loading.state - 1).clamp(0, 999).toInt();
  }

  try {
    await ref.read(parseProvider.notifier).parse(target);
    // 解析（含登录窗口）结束后收起「加载中…」，再处理结果
    finishLoading();
    if (context.mounted) {
      final parse = ref.read(parseProvider);
      final info = parse.videoInfo;
      if (parse.isError || info == null) {
        await AddUrlsPanel.show(context, initialText: target);
        return QuickAddResult.failed;
      }

      if (!ref.read(canDownloadProvider)) {
        await LicenseWindow.show(context);
        return QuickAddResult.trialEnded;
      }

      final format = info.recommendedFormat;
      if (format == null) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('没有可用格式')),
        );
        return QuickAddResult.failed;
      }

      final settings = ref.read(settingsProvider);
      await ref.read(downloadListProvider.notifier).startDownload(
            videoInfo: info,
            format: format,
            downloadSubtitles: settings.defaultDownloadSubtitles,
            downloadCover: settings.defaultDownloadCover,
          );
      return QuickAddResult.added;
    }
    return QuickAddResult.failed;
  } catch (e) {
    finishLoading();
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('添加失败：$e')),
      );
    }
    return QuickAddResult.failed;
  } finally {
    finishLoading();
  }
}
