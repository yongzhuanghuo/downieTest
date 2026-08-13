import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/format_option.dart';
import '../../data/models/video_info.dart';
import '../downloads/download_provider.dart';
import 'home_provider.dart';

/// 首页 - URL 粘贴 + 解析 + 下载
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final _urlController = TextEditingController();
  FormatOption? _selectedFormat;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    if (data?.text != null && mounted) {
      _urlController.text = data!.text!;
    }
  }

  Future<void> _parse() async {
    _selectedFormat = null;
    ref.read(parseProvider.notifier).parse(_urlController.text);
  }

  void _download() {
    final info = ref.read(parseProvider).videoInfo;
    if (info == null) return;
    final format = _selectedFormat ?? info.recommendedFormat;
    if (format == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有可用格式')),
      );
      return;
    }
    ref.read(downloadListProvider.notifier).startDownload(
          videoInfo: info,
          format: format,
        );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已添加到下载队列：${info.title}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parseState = ref.watch(parseProvider);

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('添加链接', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              '粘贴视频链接，支持 YouTube、B站、抖音等 1000+ 网站',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            _buildUrlInput(theme),
            const SizedBox(height: 16),
            _buildParseButton(theme, parseState.isLoading),
            const SizedBox(height: 24),
            _buildResultArea(theme, parseState),
          ],
        ),
      ),
    );
  }

  Widget _buildUrlInput(ThemeData theme) {
    return TextField(
      controller: _urlController,
      maxLines: 2,
      decoration: InputDecoration(
        hintText: '在这里粘贴视频链接... (支持拖入)',
        hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          icon: const Icon(Icons.content_paste),
          tooltip: '从剪贴板粘贴',
          onPressed: _pasteFromClipboard,
        ),
      ),
      onSubmitted: (_) => _parse(),
    );
  }

  Widget _buildParseButton(ThemeData theme, bool isLoading) {
    return FilledButton.icon(
      onPressed: isLoading ? null : _parse,
      icon: isLoading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.search),
      label: const Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Text('解析链接'),
      ),
    );
  }

  Widget _buildResultArea(ThemeData theme, ParseState parseState) {
    if (parseState.isLoading) return _buildLoading(theme);
    if (parseState.isError) {
      return _buildError(theme, parseState.error ?? '解析失败');
    }
    if (parseState.isSuccess && parseState.videoInfo != null) {
      return _buildVideoCard(theme, parseState.videoInfo!);
    }
    return _buildIdle(theme);
  }

  Widget _buildIdle(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(
            Icons.link,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 12),
          Text(
            '粘贴链接后点击「解析链接」',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoading(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            '正在解析，请稍候...',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(ThemeData theme, String error) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              error,
              style: TextStyle(color: theme.colorScheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoCard(ThemeData theme, VideoInfo info) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    info.thumbnail,
                    width: 160,
                    height: 90,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      width: 160,
                      height: 90,
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.broken_image),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        info.title,
                        style: theme.textTheme.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        info.uploader,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _chip(info.extractor),
                          _chip(info.durationText),
                          _chip('${info.formats.length} 个格式'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildFormatSelector(theme, info),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _download,
              icon: const Icon(Icons.download),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text('下载'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormatSelector(ThemeData theme, VideoInfo info) {
    final videoFormats = info.formats.where((f) => !f.audioOnly).toList();
    final audioFormats = info.formats.where((f) => f.audioOnly).toList();
    final currentValue = _selectedFormat ?? info.recommendedFormat;

    return DropdownButtonFormField<FormatOption>(
      key: ValueKey(info.videoId),
      decoration: const InputDecoration(
        labelText: '选择画质/格式',
        border: OutlineInputBorder(),
      ),
      initialValue: currentValue,
      items: [
        ...videoFormats.map((f) => DropdownMenuItem(
              value: f,
              child: Text(_formatLabel(f)),
            )),
        if (audioFormats.isNotEmpty)
          ...audioFormats.map((f) => DropdownMenuItem(
                value: f,
                child: Text(_formatLabel(f)),
              )),
      ],
      onChanged: (v) => setState(() => _selectedFormat = v),
    );
  }

  String _formatLabel(FormatOption f) {
    final size = f.fileSizeText == '未知' ? '' : ' · ${f.fileSizeText}';
    return '${f.label}$size';
  }

  Widget _chip(String text) {
    return Chip(
      label: Text(text, style: const TextStyle(fontSize: 12)),
      visualDensity: VisualDensity.compact,
    );
  }
}
