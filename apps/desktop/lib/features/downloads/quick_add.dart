import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/platform/automation_request.dart';
import '../../core/sites/format_selector.dart';
import '../../core/storage/adult_filter.dart';
import '../../data/models/download_task.dart';
import '../../data/models/format_option.dart';
import '../../data/models/video_info.dart';
import '../../shared/branding/app_brand.dart';
import '../home/home_provider.dart';
import '../license/license_provider.dart';
import '../license/license_window.dart';
import '../settings/settings_provider.dart';
import 'add_urls_panel.dart';
import 'download_provider.dart';
import 'duplicate_prompt.dart';
import 'quality_picker_dialog.dart';
import 'unsupported_link_dialog.dart';
import 'web_capture_dialog.dart';

enum QuickAddResult { added, needsInput, failed, trialEnded }

/// 自动化请求带来的覆盖项（标题/目录/后处理）。
class QuickAddOptions {
  final String? title;
  final String? destinationDir;
  final PostprocessingMode? postprocessing;

  const QuickAddOptions({
    this.title,
    this.destinationDir,
    this.postprocessing,
  });
}

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

/// 处理 URL scheme / `open -a` 转发来的自动化请求。
Future<QuickAddResult> quickAddAutomation(
  BuildContext context,
  WidgetRef ref,
  AutomationRequest request,
) async {
  final options = QuickAddOptions(
    title: request.title.isEmpty ? null : request.title,
    // 空串表示「显式不询问保存位置」，用全局下载目录。
    destinationDir: request.destination,
    postprocessing: request.openInUge ? null : request.postprocessing,
  );
  if (request.openInUge) {
    var added = false;
    await WebCaptureDialog.show(
      context,
      request.url,
      onAdd: (media) async {
        final error = await enqueueCapturedMediaFromUge(
          context,
          ref,
          media,
          options: options,
        );
        if (error == null) added = true;
        return error;
      },
      onQueuePage: (url) async {
        await quickAddText(context, ref, url, options: options);
      },
    );
    return added ? QuickAddResult.added : QuickAddResult.failed;
  }
  return quickAddText(context, ref, request.url, options: options);
}

/// 解析一段文本里的第一个视频链接并直接入队。
Future<QuickAddResult> quickAddText(
  BuildContext context,
  WidgetRef ref,
  String text, {
  QuickAddOptions? options,
}) async {
  final target = wholeHttpUrl(text) ?? firstVideoUrl(text);
  if (target == null) {
    if (context.mounted) {
      await AddUrlsPanel.show(context, initialText: text);
    }
    return QuickAddResult.needsInput;
  }
  if (ref.read(settingsProvider).blockAdultSites && isAdultUrl(target)) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('已按家长控制设置阻止该站点')),
    );
    return QuickAddResult.failed;
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
    if (!context.mounted) return QuickAddResult.failed;

    final parse = ref.read(parseProvider);
    final info = parse.videoInfo;
    if (parse.isError || info == null) {
      // 与 Downie 一样：不打开「添加链接」，直接给不支持的链接提示
      return _handleUnsupported(context, ref, target);
    }
    return _enqueueInfo(context, ref, info, options: options);
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

Future<QuickAddResult> _handleUnsupported(
  BuildContext context,
  WidgetRef ref,
  String target,
) async {
  final settings = ref.read(settingsProvider);
  UnsupportedResult? result;
  if (settings.autoUgeUnsupported) {
    result = const UnsupportedResult(UnsupportedAction.extract, true);
  } else {
    result = await UnsupportedLinkDialog.show(context);
  }
  if (result == null || !context.mounted) return QuickAddResult.failed;

  if (result.autoUge != settings.autoUgeUnsupported) {
    await ref
        .read(settingsProvider.notifier)
        .setAutoUgeUnsupported(result.autoUge);
  }

  switch (result.action) {
    case UnsupportedAction.extract:
      var added = false;
      await WebCaptureDialog.show(
        context,
        target,
        auto: settings.autoUgeUnsupported,
        onAdd: (media) async {
          final error = await enqueueCapturedMediaFromUge(
            context,
            ref,
            media,
          );
          if (error == null) added = true;
          return error;
        },
        onQueuePage: (url) async {
          await quickAddText(context, ref, url);
        },
      );
      return added ? QuickAddResult.added : QuickAddResult.failed;
    case UnsupportedAction.support:
      final uri = Uri(
        scheme: 'mailto',
        path: AppBrand.supportEmail,
        queryParameters: {
          'subject': '请求添加 ${AppBrand.name} 站点支持',
          'body': '链接：$target',
        },
      );
      try {
        await launchUrl(uri);
      } catch (_) {}
      return QuickAddResult.failed;
    case UnsupportedAction.ignore:
      return QuickAddResult.failed;
  }
  return QuickAddResult.failed;
}

/// UGE 行内「+」入队：成功返回 null，失败返回给用户看的错误。
Future<String?> enqueueCapturedMediaFromUge(
  BuildContext context,
  WidgetRef ref,
  CapturedMedia media, {
  QuickAddOptions? options,
}) async {
  final result = await enqueueCapturedMedia(
    context,
    ref,
    media,
    options: options,
  );
  switch (result) {
    case QuickAddResult.added:
      return null;
    case QuickAddResult.trialEnded:
      return '14 天试用已结束';
    case QuickAddResult.needsInput:
      return '需要先输入链接';
    case QuickAddResult.failed:
      return '未能加入下载队列';
  }
  return '未能加入下载队列';
}

Future<QuickAddResult> enqueueCapturedMedia(
  BuildContext context,
  WidgetRef ref,
  CapturedMedia media, {
  QuickAddOptions? options,
}) async {
  final host = Uri.tryParse(media.pageUrl)?.host ?? '';
  final info = VideoInfo(
    url: media.pageUrl,
    title: media.title.isEmpty ? host : media.title,
    duration: 0,
    uploader: host,
    thumbnail: '',
    extractor: 'GenericWeb',
    videoId: media.url.hashCode.abs().toString(),
    formats: [
      FormatOption(
        formatId: jsonEncode({
          'url': media.url,
          'kind': media.kind,
          'referer': media.referer,
          'cookie': media.cookie,
        }),
        label: '用户自定义提取 ${media.kind.toUpperCase()}',
        height: 0,
        ext: 'mp4',
      ),
    ],
  );
  return _enqueueInfo(context, ref, info, options: options);
}

Future<QuickAddResult> _enqueueInfo(
  BuildContext context,
  WidgetRef ref,
  VideoInfo info, {
  QuickAddOptions? options,
}) async {
  if (!ref.read(canDownloadProvider)) {
    await LicenseWindow.show(context);
    return QuickAddResult.trialEnded;
  }
  final settings = ref.read(settingsProvider);
  if (!await confirmDuplicateDownload(context, ref, info)) {
    return QuickAddResult.failed;
  }
  if (!context.mounted) return QuickAddResult.failed;

  FormatOption? format;
  final videoFormats =
      info.formats.where((f) => !f.audioOnly).toList(growable: false);
  if (!settings.automatedMode &&
      settings.qualityPreference == 1 &&
      videoFormats.length > 1) {
    format = await QualityPickerDialog.show(context, info);
  } else {
    format = selectFormatForDownload(
      info,
      qualityPreference: settings.qualityPreference,
      preferMp4: settings.preferMp4,
      forceMp4: settings.forceMp4,
    );
  }
  if (format == null) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('没有可用格式')),
    );
    return QuickAddResult.failed;
  }
  final added = await ref.read(downloadListProvider.notifier).startDownload(
        videoInfo: info,
        format: format,
        downloadSubtitles: settings.defaultDownloadSubtitles,
        downloadCover: settings.defaultDownloadCover,
        titleOverride: options?.title,
        destinationDir: options?.destinationDir,
        postprocessing: options?.postprocessing,
      );
  if (!added) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('已取消选择保存位置')),
    );
    return QuickAddResult.failed;
  }
  return QuickAddResult.added;
}
