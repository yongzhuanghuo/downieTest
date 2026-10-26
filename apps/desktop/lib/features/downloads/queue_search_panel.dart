import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/theme/design_tokens.dart';
import '../../shared/widgets/window_panel.dart';
import 'download_provider.dart';

/// 主队列搜索：输入关键词过滤下载列表。
class QueueSearchPanel extends ConsumerStatefulWidget {
  const QueueSearchPanel({super.key});

  static Future<void> show(BuildContext context) async {
    await showWindowPanel<void>(
      context: context,
      title: '搜索下载',
      width: 420,
      height: 220,
      child: const QueueSearchPanel(),
    );
  }

  @override
  ConsumerState<QueueSearchPanel> createState() => _QueueSearchPanelState();
}

class _QueueSearchPanelState extends ConsumerState<QueueSearchPanel> {
  late final TextEditingController _controller;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: ref.read(downloadSearchProvider));
    _focus = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(downloadSearchProvider);
    final tasks = ref.watch(downloadListProvider);
    final q = query.trim().toLowerCase();
    final count = q.isEmpty
        ? tasks.length
        : tasks
            .where((t) =>
                t.title.toLowerCase().contains(q) ||
                t.extractor.toLowerCase().contains(q))
            .length;
    final secondary = Theme.of(context).brightness == Brightness.dark
        ? AppTokens.textSecondary
        : AppTokens.textSecondaryLight;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            focusNode: _focus,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              hintText: '按标题或站点搜索下载',
              prefixIcon: Icon(Icons.search, size: 16),
            ),
            onChanged: (value) =>
                ref.read(downloadSearchProvider.notifier).state = value,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            q.isEmpty ? '共 ${tasks.length} 个下载' : '匹配 $count 个下载',
            style: TextStyle(fontSize: 11, color: secondary),
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  _controller.clear();
                  ref.read(downloadSearchProvider.notifier).state = '';
                },
                child: const Text('清除'),
              ),
              const SizedBox(width: AppSpacing.xs),
              FilledButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('完成'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
