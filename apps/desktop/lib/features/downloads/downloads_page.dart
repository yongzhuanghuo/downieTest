import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/branding/app_brand.dart';
import '../../shared/theme/design_tokens.dart';
import 'download_provider.dart';
import 'widgets/download_row.dart';

/// 主窗口：下载队列。
///
/// 空状态只显示灰度 logo；有任务时是全宽缩略图行，没有侧边栏/顶栏/卡片列表。
class DownloadsPage extends ConsumerWidget {
  const DownloadsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(downloadListProvider);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final divider = dark ? AppTokens.divider : AppTokens.dividerLight;

    if (tasks.isEmpty) {
      return const _EmptyState();
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
    return ColoredBox(
      color: dark ? AppTokens.window : AppTokens.windowLight,
      child: Center(
        child: ColorFiltered(
          colorFilter: const ColorFilter.matrix(<double>[
            0.2126, 0.7152, 0.0722, 0, 0,
            0.2126, 0.7152, 0.0722, 0, 0,
            0.2126, 0.7152, 0.0722, 0, 0,
            0, 0, 0, 0.28, 0,
          ]),
          child: Image.asset(
            AppBrand.logoAsset,
            width: 120,
            height: 120,
            filterQuality: FilterQuality.medium,
          ),
        ),
      ),
    );
  }
}
