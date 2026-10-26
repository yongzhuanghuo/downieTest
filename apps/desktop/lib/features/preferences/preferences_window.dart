import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/engine/ytdlp_runner.dart';
import '../../core/sites/plugin_registry.dart';
import '../../shared/theme/design_tokens.dart';
import '../../shared/widgets/window_panel.dart';
import '../license/license_window.dart';
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
    _PrefItem('代理服务器', Icons.vpn_lock_outlined, 7, true, Colors.green),
    _PrefItem('支持站点', Icons.public, 8, true, Colors.lightBlue),
    _PrefItem('搜索引擎', Icons.search, 9, false, Colors.blueAccent),
    _PrefItem('家长控制与隐私', Icons.lock_outline, 10, false, Colors.amber),
    _PrefItem('高级', Icons.build_outlined, 11, true, Colors.blueGrey),
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
              onPressed: () => LicenseWindow.show(context),
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
      case 7:
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            Text(
              '代理服务器',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              initialValue: settings.proxy,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'http://127.0.0.1:7890 或 socks5://127.0.0.1:7891',
              ),
              onChanged: notifier.setProxy,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              '代理会传给 yt-dlp，用于解析和下载。留空表示不使用代理；'
              '修改后对之后新发起的任务生效。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        );
      case 8:
        final plugins = PluginRegistry.instance.all
            .where((plugin) => plugin.id != 'GenericWeb')
            .toList();
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            Text(
              '原生站点插件',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: AppSpacing.md),
            for (final plugin in plugins)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.check_circle,
                  size: 16,
                  color: AppTokens.success,
                ),
                title: Text(plugin.displayName),
                subtitle: Text(plugin.id),
              ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              '其他站点',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              '未命中原生插件时，自动回退 yt-dlp；也可以使用「用户自定义视频提取」'
              '打开页面捕获 m3u8/mpd/mp4。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        );
      case 11:
        return const _AdvancedPane();
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

class _AdvancedPane extends StatefulWidget {
  const _AdvancedPane();

  @override
  State<_AdvancedPane> createState() => _AdvancedPaneState();
}

class _AdvancedPaneState extends State<_AdvancedPane> {
  String? _version;
  bool _updating = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final version = await YtDlpRunner.getVersion();
      if (mounted) setState(() => _version = version);
    } catch (e) {
      if (mounted) setState(() => _message = '读取版本失败：$e');
    }
  }

  Future<void> _update() async {
    if (_updating) return;
    setState(() {
      _updating = true;
      _message = null;
    });
    try {
      final result = await YtDlpRunner.update()
          .timeout(const Duration(seconds: 60));
      if (!mounted) return;
      setState(() {
        _updating = false;
        _version = result.version;
        _message = result.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _updating = false;
        _message = '检查更新失败：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      children: [
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.terminal, size: 18),
          title: const Text('yt-dlp 版本'),
          subtitle: Text(_version ?? '读取中…'),
          trailing: _updating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : TextButton(
                  onPressed: _update,
                  child: const Text('检查更新'),
                ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          '内嵌 yt-dlp 和 ffmpeg 会在首次运行时复制到应用数据目录；'
          '日志按天保存在 logs/ 下。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (_message != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            _message!,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
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
