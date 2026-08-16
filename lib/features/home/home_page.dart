import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/format_option.dart';
import '../../data/models/video_info.dart';
import '../downloads/download_provider.dart';
import '../license/license_card.dart';
import '../license/license_provider.dart';
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
  bool _downloadSubtitles = false; // 下载时是否导出字幕

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // 监听解析状态，成功后自动选择格式
    ref.listenManual(parseProvider, (prev, next) {
      if (next.isSuccess && next.videoInfo != null && _selectedFormat == null) {
        _autoSelectFormat(next.videoInfo!);
      }
    });
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    if (data?.text != null && mounted) {
      _urlController.text = data!.text!;
    }
  }

  Future<void> _parse() async {
    _selectedFormat = null;
    _downloadSubtitles = false;
    ref.read(parseProvider.notifier).parse(_urlController.text);
  }

  /// 解析成功后自动选择默认格式（免费版降级到 1080P）
  void _autoSelectFormat(VideoInfo info) {
    final isPro = ref.read(isProProvider);
    final maxH = isPro ? 10000000 : 1080;
    final defaultFmt = info.recommendedFormat;
    if (!isPro &&
        defaultFmt != null &&
        !defaultFmt.audioOnly &&
        defaultFmt.height > maxH) {
      final videoFormats = info.formats.where((f) => !f.audioOnly).toList();
      if (videoFormats.isNotEmpty) {
        try {
          _selectedFormat = videoFormats
              .firstWhere((f) => f.height <= maxH, orElse: () => videoFormats.last);
        } catch (_) {
          _selectedFormat = defaultFmt;
        }
      } else {
        _selectedFormat = defaultFmt;
      }
    } else {
      _selectedFormat = defaultFmt;
    }
    if (mounted) setState(() {});
  }

  Future<void> _download() async {
    final info = ref.read(parseProvider).videoInfo;
    if (info == null) return;
    final format = _selectedFormat ?? info.recommendedFormat;
    if (format == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有可用格式')),
      );
      return;
    }

    // ---------- 会员: 清晰度/限额检查 ----------
    final storage = LicenseStorage.instance;

    // 1. 清晰度检查
    final maxH = storage.maxHeight;
    if (!format.audioOnly && format.height > maxH) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          content: Row(
            children: [
              const Icon(Icons.lock, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '免费版最高支持 ${maxH}P，当前选择 ${format.height}P，请升级 PRO 后下载 4K 高清内容',
                ),
              ),
            ],
          ),
          action: SnackBarAction(
            label: '去激活',
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              showProUpgradeDialog(context, ref);
            },
          ),
        ),
      );
      return;
    }

    // 2. 限额检查
    if (!storage.acquireSlot()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          content: Row(
            children: [
              const Icon(Icons.timer_off, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '今日免费下载次数已用完 (${storage.todayUsed}/2)，'
                  '请明日再来或升级 PRO 解锁无限下载',
                ),
              ),
            ],
          ),
          action: SnackBarAction(
            label: '升级 PRO',
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              showProUpgradeDialog(context, ref);
            },
          ),
        ),
      );
      return;
    }

    // 通过 → 添加到队列
    ref.read(downloadListProvider.notifier).startDownload(
          videoInfo: info,
          format: format,
          downloadSubtitles: _downloadSubtitles,
        );
    if (mounted) {
      final rem = storage.todayRemaining;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已添加到下载队列：${info.title}'
              '${rem == null ? '' : '（今日剩余 $rem 次）'}'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parseState = ref.watch(parseProvider);
    final isPro = ref.watch(isProProvider);
    final remaining = ref.watch(todayRemainingProvider);
    final used = ref.watch(todayUsedProvider);

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTopBanner(theme, isPro, used, remaining),
            const SizedBox(height: 20),
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

  // ==================== 顶部会员条 ====================
  Widget _buildTopBanner(
    ThemeData theme,
    bool isPro,
    int used,
    int? remaining,
  ) {
    if (isPro) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.amber.withValues(alpha: 0.2),
              Colors.orange.withValues(alpha: 0.15),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.workspace_premium, color: Colors.amber),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'PRO 永久版已激活 · 4K 无限下载 · 最多 4 台设备',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Chip(
              backgroundColor: Colors.amber.withValues(alpha: 0.15),
              side: BorderSide(color: Colors.amber.withValues(alpha: 0.4)),
              visualDensity: VisualDensity.compact,
              avatar: const Icon(Icons.check_circle, size: 16, color: Colors.amber),
              label: const Text(
                'PRO',
                style: TextStyle(
                    color: Colors.amber, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    }
    // 免费版限额提示
    final limit = 2;
    final pct = (used / limit).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.card_membership_outlined, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '今日免费下载次数：已用 $used / $limit，剩余 $remaining 次',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
              TextButton.icon(
                onPressed: () => showProUpgradeDialog(context, ref),
                icon: const Icon(Icons.workspace_premium, size: 16),
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                label: const Text('升级 PRO（¥30 买断）'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: pct,
              backgroundColor:
                  theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.15),
            ),
          ),
        ],
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
            const SizedBox(height: 12),
            _buildSubtitleCheckbox(theme, info),
            const SizedBox(height: 16),
            _buildDownloadButton(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadButton(ThemeData theme) {
    final quotaReached = ref.watch(isQuotaReachedProvider);
    final maxH = ref.watch(maxAllowedHeightProvider);
    final fmt = _selectedFormat;
    bool locked = false;
    String? lockMsg;
    if (fmt != null && !fmt.audioOnly && fmt.height > maxH) {
      locked = true;
      lockMsg = '${fmt.height}P 需要 PRO';
    } else if (quotaReached) {
      locked = true;
      lockMsg = '今日次数已用完';
    }
    return FilledButton.icon(
      onPressed: locked ? null : _download,
      icon: locked ? const Icon(Icons.lock_outline) : const Icon(Icons.download),
      label: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(locked ? '下载（$lockMsg）' : '下载'),
      ),
    );
  }

  Widget _buildFormatSelector(ThemeData theme, VideoInfo info) {
    final isPro = ref.watch(isProProvider);
    final maxH = isPro ? 10000000 : 1080;
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
        ...videoFormats.map((f) {
          final locked = !isPro && f.height > maxH;
          return DropdownMenuItem<FormatOption>(
            value: f,
            enabled: !locked,
            child: Text(
              _formatLabel(f),
              style: TextStyle(
                color: locked
                    ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
                    : null,
              ),
            ),
          );
        }),
        if (audioFormats.isNotEmpty)
          ...audioFormats.map((f) => DropdownMenuItem<FormatOption>(
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

  Widget _buildSubtitleCheckbox(ThemeData theme, VideoInfo info) {
    if (info.subtitleLangs.isEmpty) return const SizedBox.shrink();
    return CheckboxListTile(
      value: _downloadSubtitles,
      onChanged: (v) => setState(() => _downloadSubtitles = v ?? false),
      title: const Text('同时下载字幕'),
      subtitle: const Text('下载所有可用字幕（.srt/.vtt）'),
      dense: true,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
    );
  }

  Widget _chip(String text) {
    return Chip(
      label: Text(text, style: const TextStyle(fontSize: 12)),
      visualDensity: VisualDensity.compact,
    );
  }
}
