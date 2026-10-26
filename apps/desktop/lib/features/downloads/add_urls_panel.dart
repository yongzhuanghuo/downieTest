import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sites/plugins/generic_web_plugin.dart';
import '../../data/models/format_option.dart';
import '../../data/models/video_info.dart';
import '../../shared/theme/design_tokens.dart';
import '../../shared/widgets/window_panel.dart';
import '../home/home_provider.dart';
import '../license/license_provider.dart';
import '../license/license_window.dart';
import '../settings/settings_provider.dart';
import 'download_provider.dart';
import 'web_capture_dialog.dart';

/// Downie 风格「添加链接」浮层：粘贴/用户自定义视频提取 → 解析 → 直接入队。
class AddUrlsPanel extends ConsumerStatefulWidget {
  final String? initialText;

  const AddUrlsPanel({super.key, this.initialText});

  static Future<bool?> show(BuildContext context, {String? initialText}) {
    return showWindowPanel<bool>(
      context: context,
      title: '添加链接',
      width: 540,
      height: 380,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      child: AddUrlsPanel(initialText: initialText),
    );
  }

  @override
  ConsumerState<AddUrlsPanel> createState() => _AddUrlsPanelState();
}

class _AddUrlsPanelState extends ConsumerState<AddUrlsPanel> {
  late final TextEditingController _controller;
  bool _busy = false;
  bool _downloadSubtitles = false;
  bool _downloadCover = false;
  String? _error;
  String? _progress;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText ?? '');
    final settings = ref.read(settingsProvider);
    _downloadSubtitles = settings.defaultDownloadSubtitles;
    _downloadCover = settings.defaultDownloadCover;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData('text/plain');
    if (data?.text != null && mounted) {
      setState(() {
        _controller.text = data!.text!;
        _error = null;
      });
    }
  }

  Future<void> _submit() async {
    if (_busy) return;
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _error = '请先粘贴视频链接');
      return;
    }

    // 一次粘贴多条链接时逐条解析入队；没有 URL 的纯文本仍交给解析器判断。
    final urls = extractUrls(text);
    final targets = urls.isEmpty ? [text] : urls;

    setState(() {
      _busy = true;
      _error = null;
      _progress = targets.length > 1 ? '准备解析 ${targets.length} 条链接…' : null;
    });

    var added = 0;
    var trialBlocked = false;
    final failures = <String>[];

    for (var i = 0; i < targets.length; i++) {
      if (!mounted) return;
      if (targets.length > 1) {
        setState(() => _progress = '正在解析 ${i + 1}/${targets.length}…');
      }

      final target = targets[i];
      try {
        await ref.read(parseProvider.notifier).parse(target);
        final parse = ref.read(parseProvider);
        final info = parse.videoInfo;
        if (parse.isError || info == null) {
          failures.add('${_shortUrl(target)}：${parse.error ?? '解析失败'}');
          continue;
        }

        final error = await _enqueueInfo(info);
        if (error == _trialEnded) {
          trialBlocked = true;
          break;
        }
        if (error != null) {
          failures.add('${_shortUrl(target)}：$error');
          continue;
        }
        added++;
      } catch (e) {
        failures.add('${_shortUrl(target)}：$e');
      }
    }

    if (!mounted) return;

    if (added > 0) {
      if (failures.isNotEmpty) {
        debugPrint('[添加链接] ${failures.length} 条失败：${failures.join('；')}');
      }
      Navigator.of(context).pop(true);
      return;
    }

    setState(() {
      _busy = false;
      _progress = null;
      _error = trialBlocked
          ? '14 天试用已结束，请输入授权码'
          : failures.isEmpty
              ? '解析失败，请检查链接'
              : failures.length == 1
                  ? failures.first
                  : '全部 ${failures.length} 条链接都解析失败：${failures.first}';
    });
    if (trialBlocked) {
      await LicenseWindow.show(context);
    }
  }

  static const _trialEnded = '__trial_ended__';

  /// 把解析结果加入下载队列；成功返回 null，失败返回错误文案。
  Future<String?> _enqueueInfo(VideoInfo info) async {
    if (!ref.read(canDownloadProvider)) return _trialEnded;
    final format = info.recommendedFormat;
    if (format == null) return '没有可用格式';
    await ref.read(downloadListProvider.notifier).startDownload(
          videoInfo: info,
          format: format,
          downloadSubtitles: _downloadSubtitles,
          downloadCover: _downloadCover,
        );
    return null;
  }

  String _shortUrl(String url) {
    final uri = Uri.tryParse(url);
    final host = uri?.host ?? '';
    return host.isEmpty ? url : host;
  }

  Future<void> _capture() async {
    if (_busy) return;
    final text = _controller.text.trim();
    final url = extractFirstUrl(text) ?? text;
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      setState(() => _error = '请先输入一个网页链接');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final directKind = detectMediaKind(url);
      CapturedMedia? media;
      if (directKind != null) {
        media = CapturedMedia(
          url: url,
          kind: directKind,
          pageUrl: url,
          title: uri.host,
          referer: url,
          cookie: '',
        );
      } else {
        media = await WebCaptureDialog.show(context, url);
      }
      if (media == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
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
            label: '用户自定义视频提取 ${media.kind.toUpperCase()}',
            height: 0,
            ext: 'mp4',
          ),
        ],
      );
      await _startInfo(info);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '用户自定义视频提取失败：$e';
        });
      }
    }
  }

  Future<void> _startInfo(VideoInfo info) async {
    final error = await _enqueueInfo(info);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _error = error == _trialEnded ? '14 天试用已结束，请输入授权码' : error;
    });
    if (error == _trialEnded) {
      await LicenseWindow.show(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final text = dark ? AppTokens.textPrimary : AppTokens.textPrimaryLight;
    final secondary =
        dark ? AppTokens.textSecondary : AppTokens.textSecondaryLight;
    final error = dark ? AppTokens.error : AppTokens.errorLight;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '粘贴视频链接，自动解析并加入下载队列。',
            style: TextStyle(fontSize: 12, color: secondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 3,
            maxLines: 4,
            style: TextStyle(fontSize: 13, color: text),
            decoration: const InputDecoration(
              hintText: 'https://...\n支持一次粘贴多条链接；抖音、B站、YouTube 等',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              _error!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: error),
            ),
          ],
          Row(
            children: [
              Checkbox(
                value: _downloadSubtitles,
                onChanged: _busy
                    ? null
                    : (value) =>
                        setState(() => _downloadSubtitles = value ?? false),
              ),
              const Text('下载字幕', style: TextStyle(fontSize: 12)),
              const SizedBox(width: AppSpacing.lg),
              Checkbox(
                value: _downloadCover,
                onChanged: _busy
                    ? null
                    : (value) =>
                        setState(() => _downloadCover = value ?? false),
              ),
              const Text('下载封面', style: TextStyle(fontSize: 12)),
            ],
          ),
          const Spacer(),
          Row(
            children: [
              TextButton.icon(
                onPressed: _busy ? null : _paste,
                icon: const Icon(Icons.content_paste, size: 14),
                label: const Text('粘贴'),
              ),
              const SizedBox(width: AppSpacing.xs),
              TextButton.icon(
                onPressed: _busy ? null : _capture,
                icon: const Icon(Icons.travel_explore, size: 14),
                label: const Text('用户自定义视频提取'),
              ),
              const Spacer(),
              if (_busy) ...[
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                if (_progress != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    _progress!,
                    style: TextStyle(fontSize: 11, color: secondary),
                  ),
                ],
                const SizedBox(width: AppSpacing.lg),
              ],
              TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              const SizedBox(width: AppSpacing.xs),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: const Text('添加下载'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
