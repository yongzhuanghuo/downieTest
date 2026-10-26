import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/engine/ytdlp_runner.dart';
import '../../core/server/browser_bridge.dart';
import '../../core/storage/site_cookies.dart';
import '../../core/sites/plugin_registry.dart';
import '../../core/sites/search_engines.dart';
import '../../shared/theme/design_tokens.dart';
import '../../shared/widgets/window_panel.dart';
import '../downloads/download_provider.dart';
import '../history/history_page.dart';
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
    _PrefItem('历史记录', Icons.history, 3, true, Colors.teal),
    _PrefItem('浏览器扩展', Icons.extension_outlined, 4, true, Colors.indigo),
    _PrefItem('后处理', Icons.tune, 5, true, Colors.grey),
    _PrefItem('字幕与音频', Icons.subtitles_outlined, 6, true, Colors.deepOrange),
    _PrefItem('代理服务器', Icons.vpn_lock_outlined, 7, true, Colors.green),
    _PrefItem('支持站点', Icons.public, 8, true, Colors.lightBlue),
    _PrefItem('搜索引擎', Icons.search, 9, true, Colors.blueAccent),
    _PrefItem('家长控制与隐私', Icons.lock_outline, 10, true, Colors.amber),
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
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('下载完成后发送系统通知'),
              value: settings.notifyOnComplete,
              onChanged: notifier.setNotifyOnComplete,
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
      case 3:
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            Text(
              '历史记录保留时间',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<int>(
              initialValue: settings.historyDays,
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
              ),
              items: const [
                DropdownMenuItem(value: 0, child: Text('永久保留')),
                DropdownMenuItem(value: 7, child: Text('7 天')),
                DropdownMenuItem(value: 30, child: Text('30 天')),
                DropdownMenuItem(value: 90, child: Text('90 天')),
                DropdownMenuItem(value: 365, child: Text('1 年')),
              ],
              onChanged: (value) => notifier.setHistoryDays(value ?? 0),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              '过期记录会在下次启动时自动清理，已下载的文件不会被删除。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.xxl),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('清空已结束任务'),
              subtitle: const Text('移除已完成、失败和已取消的队列记录'),
              trailing: TextButton(
                onPressed: () => _clearFinished(context),
                child: const Text('清空'),
              ),
            ),
          ],
        );
      case 4:
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            Text(
              '读取浏览器登录状态',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '让 yt-dlp 直接复用本机浏览器里已登录的 cookie，适合 YouTube、'
              'Instagram、X 等站点。默认关闭。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.lg),
            DropdownButtonFormField<String>(
              initialValue: settings.cookiesFromBrowser,
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
              ),
              items: const [
                DropdownMenuItem(value: '', child: Text('不使用浏览器 cookie')),
                DropdownMenuItem(value: 'chrome', child: Text('Google Chrome')),
                DropdownMenuItem(value: 'safari', child: Text('Safari')),
                DropdownMenuItem(value: 'edge', child: Text('Microsoft Edge')),
                DropdownMenuItem(value: 'firefox', child: Text('Firefox')),
                DropdownMenuItem(value: 'brave', child: Text('Brave')),
              ],
              onChanged: (value) =>
                  notifier.setCookiesFromBrowser(value ?? ''),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              '读取 Chrome/Edge 时可能需要关闭浏览器，macOS 可能弹出钥匙串授权。'
              '读取失败不会影响普通下载；也可以继续用应用内登录。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.xxxl),
            Text(
              '浏览器书签',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('接收本机浏览器发来的页面'),
              subtitle: Text(
                '监听 127.0.0.1:${BrowserBridge.defaultPort}，在浏览器里点书签即可加入下载',
              ),
              value: settings.browserBridgeEnabled,
              onChanged: notifier.setBrowserBridgeEnabled,
            ),
            if (settings.browserBridgeEnabled) ...[
              if (settings.browserBridgeToken.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  '扩展 token（浏览器扩展弹窗里填写）',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        settings.browserBridgeToken,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                    IconButton(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(
                          text: settings.browserBridgeToken,
                        ));
                        if (context.mounted) {
                          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                            const SnackBar(content: Text('token 已复制')),
                          );
                        }
                      },
                      tooltip: '复制 token',
                      icon: const Icon(Icons.copy, size: 14),
                      constraints: const BoxConstraints.tightFor(
                        width: 30,
                        height: 30,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(AppRadius.button),
                  ),
                  child: SelectableText(
                    BrowserBridge.bookmarklet(
                      token: settings.browserBridgeToken,
                    ),
                    maxLines: 4,
                    style: const TextStyle(fontSize: 10),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(
                          text: BrowserBridge.bookmarklet(
                            token: settings.browserBridgeToken,
                          ),
                        ));
                        if (context.mounted) {
                          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                            const SnackBar(content: Text('书签脚本已复制')),
                          );
                        }
                      },
                      icon: const Icon(Icons.copy, size: 14),
                      label: const Text('复制书签脚本'),
                    ),
                    TextButton(
                      onPressed: notifier.regenerateBrowserBridgeToken,
                      child: const Text('重置 token'),
                    ),
                    TextButton.icon(
                      onPressed: () => _exportExtension(context),
                      icon: const Icon(Icons.extension_outlined, size: 14),
                      label: const Text('导出浏览器扩展'),
                    ),
                  ],
                ),
                Text(
                  '可以复制书签脚本作为浏览器书签，或导出 Chrome/Edge 扩展后'
                  '在扩展管理页「加载已解压的扩展程序」。'
                  'token 只保存在本机，重置后旧书签/扩展需要重新填写。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ],
        );
      case 5:
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            Text(
              '新任务默认后处理',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('无')),
                ButtonSegment(value: 1, label: Text('转换为 MP4')),
                ButtonSegment(value: 2, label: Text('仅音频 MP3')),
              ],
              selected: {settings.defaultPostprocessing},
              onSelectionChanged: (values) =>
                  notifier.setDefaultPostprocessing(values.first),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              '下载完成后用 ffmpeg 转换。可以在下载行里随时改成其他方式；'
              '已经是目标格式时不会重复转换。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        );
      case 6:
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('默认下载字幕'),
              subtitle: const Text('交给 yt-dlp 写入字幕文件'),
              value: settings.defaultDownloadSubtitles,
              onChanged: notifier.setDefaultDownloadSubtitles,
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('默认下载封面'),
              subtitle: const Text('保存最高清的一张封面'),
              value: settings.defaultDownloadCover,
              onChanged: notifier.setDefaultDownloadCover,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              '字幕语言（逗号分隔，留空表示全部）',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              initialValue: settings.subtitleLangs,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'zh,en',
              ),
              onChanged: notifier.setSubtitleLangs,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              '这些选项只是新任务的默认值，添加链接时仍可临时勾选/取消。',
              style: Theme.of(context).textTheme.bodySmall,
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
      case 9:
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            Text(
              '用户自定义视频提取地址栏',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '在提取窗口输入关键词而不是网址时，用这个搜索引擎打开。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.lg),
            for (final engine in kSearchEngines)
              RadioListTile<int>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(engine.name),
                value: engine.id,
                groupValue: settings.searchEngine,
                onChanged: (value) {
                  if (value != null) notifier.setSearchEngine(value);
                },
              ),
          ],
        );
      case 10:
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            Text(
              '本地数据',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '解析、下载和站点 cookie 都在本机处理；应用只会在授权校验、'
              '版本检查和主动反馈时联网。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.lg),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('清除站点登录数据'),
              subtitle: const Text('删除内置浏览器保存的所有站点 cookie'),
              trailing: TextButton(
                onPressed: () => _clearCookies(context),
                child: const Text('清除'),
              ),
            ),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('清空下载历史'),
              subtitle: const Text('移除已完成/失败/取消的记录，不删除文件'),
              trailing: TextButton(
                onPressed: () => _clearFinished(context),
                child: const Text('清空'),
              ),
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

  Future<void> _exportExtension(BuildContext context) async {
    try {
      final path = await BrowserBridge.exportExtension();
      await Process.run(
        Platform.isMacOS ? 'open' : 'explorer',
        [path],
      );
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text('扩展已导出到 $path')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text('导出扩展失败：$e')),
        );
      }
    }
  }

  Future<void> _clearCookies(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除站点登录数据'),
        content: const Text('清除后需要重新登录各站点，下载历史不受影响。确定继续吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final removed = await SiteCookies.clearAllSites();
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('已清除 $removed 个站点的登录数据')),
      );
    }
  }

  Future<void> _clearFinished(BuildContext context) async {
    await ref.read(downloadListProvider.notifier).clearFinished();
    ref.invalidate(historyProvider);
    if (mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('已清空结束的任务')),
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
