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
import 'download_provider.dart';
import 'web_capture_dialog.dart';

/// Downie 风格「添加链接」浮层：粘贴/用户引导提取 → 解析 → 直接入队。
class AddUrlsPanel extends ConsumerStatefulWidget {
  final String? initialText;

  const AddUrlsPanel({super.key, this.initialText});

  static Future<bool?> show(BuildContext context, {String? initialText}) {
    return showWindowPanel<bool>(
      context: context,
      title: '添加链接',
      width: 540,
      height: 340,
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
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText ?? '');
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

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(parseProvider.notifier).parse(text);
      final parse = ref.read(parseProvider);
      final info = parse.videoInfo;
      if (parse.isError || info == null) {
        if (mounted) {
          setState(() {
            _busy = false;
            _error = parse.error ?? '解析失败，请检查链接';
          });
        }
        return;
      }
      await _startInfo(info);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '添加失败：$e';
        });
      }
    }
  }

  Future<void> _capture() async {
    if (_busy) return;
    final text = _controller.text.trim();
    final match = RegExp(r'https?://[^\s一-鿿]+').firstMatch(text);
    final url = match?.group(0) ?? text;
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
            label: '用户引导提取 ${media.kind.toUpperCase()}',
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
          _error = '用户引导提取失败：$e';
        });
      }
    }
  }

  Future<void> _startInfo(VideoInfo info) async {
    final format = info.recommendedFormat;
    if (format == null) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '没有可用格式';
        });
      }
      return;
    }
    await ref.read(downloadListProvider.notifier).startDownload(
          videoInfo: info,
          format: format,
        );
    if (mounted) Navigator.of(context).pop(true);
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
              hintText: 'https://...\n支持抖音、B站、YouTube 等',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              _error!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: error),
            ),
          ],
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
                label: const Text('用户引导提取'),
              ),
              const Spacer(),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(right: AppSpacing.lg),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
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
