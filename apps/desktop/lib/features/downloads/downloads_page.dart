import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/branding/app_brand.dart';
import '../../shared/theme/design_tokens.dart';
import 'download_provider.dart';
import 'widgets/download_row.dart';

/// 主窗口：下载队列。
///
/// 空状态只显示灰度 logo + 拖放提示；有任务时是全宽缩略图行。
class DownloadsPage extends ConsumerWidget {
  const DownloadsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allTasks = ref.watch(downloadListProvider);
    final query = ref.watch(downloadSearchProvider).trim().toLowerCase();
    final tasks = query.isEmpty
        ? allTasks
        : allTasks
            .where((t) =>
                t.title.toLowerCase().contains(query) ||
                t.extractor.toLowerCase().contains(query))
            .toList();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final divider = dark ? AppTokens.divider : AppTokens.dividerLight;

    if (allTasks.isEmpty) {
      return const _EmptyState();
    }
    if (tasks.isEmpty) {
      return const _NoMatches();
    }

    return ColoredBox(
      color: dark ? AppTokens.window : AppTokens.windowLight,
      child: Scrollbar(
        child: ListView.separated(
          padding: EdgeInsets.zero,
          itemCount: tasks.length,
          separatorBuilder: (_, __) => Divider(
            height: 1,
            thickness: 1,
            color: divider,
          ),
          itemBuilder: (context, index) => DownloadRow(task: tasks[index]),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final secondary =
        dark ? AppTokens.textSecondary : AppTokens.textSecondaryLight;
    return ColoredBox(
      color: dark ? AppTokens.window : AppTokens.windowLight,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ColorFiltered(
              colorFilter: const ColorFilter.matrix(<double>[
                0.2126, 0.7152, 0.0722, 0, 0,
                0.2126, 0.7152, 0.0722, 0, 0,
                0.2126, 0.7152, 0.0722, 0, 0,
                0, 0, 0, 0.55, 0,
              ]),
              child: Image.asset(
                AppBrand.logoAsset,
                width: 240,
                height: 240,
                filterQuality: FilterQuality.high,
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            Text(
              '拖放链接于此以开始',
              style: TextStyle(fontSize: 16, color: secondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoMatches extends StatelessWidget {
  const _NoMatches();

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Text(
        '没有匹配的下载',
        style: TextStyle(fontSize: 13, color: secondary),
      ),
    );
  }
}
