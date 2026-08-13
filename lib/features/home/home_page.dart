import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 首页 - URL 粘贴 + 解析（阶段1占位）
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final _urlController = TextEditingController();

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Padding(
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
            // URL 输入框
            _buildUrlInput(theme),
            const SizedBox(height: 16),
            // 下载选项行
            _buildOptionsRow(theme),
            const SizedBox(height: 16),
            // 下载按钮
            _buildDownloadButton(theme),
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
    );
  }

  Widget _buildOptionsRow(ThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            decoration: const InputDecoration(
              labelText: '格式',
              border: OutlineInputBorder(),
            ),
            initialValue: 'mp4',
            items: const [
              DropdownMenuItem(value: 'mp4', child: Text('视频+音频 (MP4)')),
              DropdownMenuItem(value: 'mp3', child: Text('仅音频 (MP3)')),
            ],
            onChanged: (value) {},
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: DropdownButtonFormField<String>(
            decoration: const InputDecoration(
              labelText: '画质',
              border: OutlineInputBorder(),
            ),
            initialValue: '1080p',
            items: const [
              DropdownMenuItem(value: '1080p', child: Text('1080p (HD)')),
              DropdownMenuItem(value: '720p', child: Text('720p (HD)')),
              DropdownMenuItem(value: '480p', child: Text('480p (SD)')),
              DropdownMenuItem(value: '360p', child: Text('360p (SD)')),
            ],
            onChanged: (value) {},
          ),
        ),
      ],
    );
  }

  Widget _buildDownloadButton(ThemeData theme) {
    return FilledButton.icon(
      onPressed: _onDownloadPressed,
      icon: const Icon(Icons.download),
      label: const Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Text('下载'),
      ),
    );
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    if (data?.text != null && mounted) {
      _urlController.text = data!.text!;
    }
  }

  void _onDownloadPressed() {
    // 阶段3实现：调用解析引擎
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('解析功能将在阶段3实现')),
    );
  }
}
