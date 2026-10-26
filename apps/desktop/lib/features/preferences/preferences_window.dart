import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/theme/design_tokens.dart';
import '../../shared/widgets/window_panel.dart';
import '../license/license_card.dart';
import '../settings/settings_provider.dart';

/// Downie 4 风格「All Preferences」：12 个图标网格 + 面板 + 占位。
class PreferencesWindow extends ConsumerStatefulWidget {
  const PreferencesWindow({super.key});

  static Future<void> show(BuildContext context) async {
    await showWindowPanel<void>(
      context: context,
      title: '全部设置',
      width: 660,
      height: 400,
      child: const PreferencesWindow(),
    );
  }

  @override
  ConsumerState<PreferencesWindow> createState() => _PreferencesWindowState();
}

class _PreferencesWindowState extends ConsumerState<PreferencesWindow> {
  int? _selected;

  static const _items = <_PrefItem>[
    _PrefItem('通用', Icons.settings_outlined, 0, true, Colors.blue),
    _PrefItem('外观', Icons.palette_outlined, 1, true, Colors.purple),
    _PrefItem('下载位置', Icons.folder_outlined, 2, true, Colors.orange),
    _PrefItem('历史记录', Icons.history, 3, false, Colors.teal),
    _PrefItem('浏览器扩展', Icons.extension_outlined, 4, false, Colors.indigo),
    _PrefItem('后处理', Icons.tune, 5, false, Colors.grey),
    _PrefItem('字幕与音频', Icons.subtitles_outlined, 6, false, Colors.deepOrange),
    _PrefItem('代理服务器', Icons.vpn_lock_outlined, 7, false, Colors.green),
    _PrefItem('支持站点', Icons.public, 8, false, Colors.lightBlue),
    _PrefItem('搜索引擎', Icons.search, 9, false, Colors.blueAccent),
    _PrefItem('家长控制与隐私', Icons.lock_outline, 10, false, Colors.amber),
    _PrefItem('高级', Icons.build_outlined, 11, false, Colors.blueGrey),
  ];

  static const _titles = {
    0: '通用',
    1: '外观',
    2: '下载位置',
    3: '历史记录',
    4: '浏览器扩展',
    5: '后处理',
    6: '字幕与音频',
    7: '代理服务器',
    8: '支持站点',
    9: '搜索引擎',
    10: '家长控制与隐私',
    11: '高级',
  };

  @override
  Widget build(BuildContext context) {
    return _selected == null ? _buildGrid(context) : _buildPane(context);
  }

  Widget _buildGrid(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.lg,
            ),
            child: Column(
              children: [
                _row(_items.sublist(0, 5)),
                const _GridDivider(),
                _row(_items.sublist(5, 8)),
                const _GridDivider(),
                _row(_items.sublist(8, 12)),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: TextButton.icon(
              onPressed: () => showProUpgradeDialog(context, ref),
              icon: const Icon(Icons.key_outlined, size: 14),
              label: const Text('授权…'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _row(List<_PrefItem> items) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in items)
          SizedBox(
            width: 120,
            child: _PrefTile(
              item: item,
              onTap: () => setState(() => _selected = item.index),
            ),
          ),
      ],
    );
  }

  Widget _buildPane(BuildContext context) {
    final title = _titles[_selected] ?? '设置';
    return Column(
      children: [
        Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Row(
            children: [
              IconButton(
                onPressed: () => setState(() => _selected = null),
                tooltip: '返回',
                icon: const Icon(Icons.chevron_left, size: 18),
                constraints: const BoxConstraints.tightFor(width: 28, height: 30),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _buildPaneContent(context, _selected!)),
      ],
    );
  }

  Widget _buildPaneContent(BuildContext context, int index) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    switch (index) {
      case 0:
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('下载完成后打开文件夹'),
              value: settings.autoOpenFolder,
              onChanged: notifier.setAutoOpenFolder,
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('开机自启动'),
              value: settings.autoStart,
              onChanged: notifier.setAutoStart,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              '并行下载数：${settings.maxConcurrent}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            Slider(
              min: 1,
              max: 10,
              divisions: 9,
              value: settings.maxConcurrent.toDouble(),
              label: '${settings.maxConcurrent}',
              onChanged: (v) => notifier.setMaxConcurrent(v.round()),
            ),
          ],
        );
      case 1:
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            Text(
              '主题模式',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.lg),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('跟随系统')),
                ButtonSegment(value: 1, label: Text('浅色')),
                ButtonSegment(value: 2, label: Text('深色')),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (values) =>
                  notifier.setThemeMode(values.first),
            ),
          ],
        );
      case 2:
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.folder_outlined),
              title: const Text('下载目录'),
              subtitle: Text(settings.downloadDirLabel),
              trailing: const Icon(Icons.chevron_right, size: 16),
              onTap: () => _pickDirectory(notifier),
            ),
          ],
        );
      default:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.construction_outlined,
                size: 32,
                color: Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant
                    .withValues(alpha: 0.5),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                '开发中',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        );
    }
  }

  Future<void> _pickDirectory(SettingsNotifier notifier) async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择下载目录',
    );
    if (result != null) {
      await notifier.setDownloadDir(result);
      if (mounted) setState(() {});
    }
  }
}

class _PrefItem {
  final String title;
  final IconData icon;
  final int index;
  final bool available;
  final Color color;

  const _PrefItem(
    this.title,
    this.icon,
    this.index,
    this.available,
    this.color,
  );
}

class _PrefTile extends StatefulWidget {
  final _PrefItem item;
  final VoidCallback? onTap;

  const _PrefTile({required this.item, this.onTap});

  @override
  State<_PrefTile> createState() => _PrefTileState();
}

class _PrefTileState extends State<_PrefTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final hover = dark ? AppTokens.hover : AppTokens.hoverLight;
    final text = dark ? AppTokens.textPrimary : AppTokens.textPrimaryLight;
    final secondary =
        dark ? AppTokens.textSecondary : AppTokens.textSecondaryLight;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          height: 88,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: _hovering ? hover : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.panel),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.item.icon,
                size: 30,
                color: widget.item.available
                    ? widget.item.color
                    : widget.item.color.withValues(alpha: 0.45),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                widget.item.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: widget.item.available ? text : secondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GridDivider extends StatelessWidget {
  const _GridDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Divider(
        height: 1,
        color: Theme.of(context).dividerColor.withValues(alpha: 0.6),
      ),
    );
  }
}
