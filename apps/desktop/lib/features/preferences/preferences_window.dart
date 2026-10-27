import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/engine/ytdlp_runner.dart';
import '../../core/ffmpeg/ffmpeg_runner.dart';
import '../../core/platform/binary_locator.dart';
import '../../core/server/browser_bridge.dart';
import '../../core/storage/settings_storage.dart';
import '../../core/storage/site_cookies.dart';
import '../../core/sites/search_engines.dart';
import '../../core/sites/site_coverage.dart';
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
            const SizedBox(height: AppSpacing.lg),
            Text(
              '有多种画质时',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<int>(
              initialValue: settings.qualityPreference,
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
              ),
              items: const [
                DropdownMenuItem(value: 0, child: Text('自动选择最佳画质')),
                DropdownMenuItem(value: 1, child: Text('每次询问我')),
                DropdownMenuItem(value: 2, child: Text('限制到 360p')),
                DropdownMenuItem(value: 3, child: Text('限制到 480p')),
                DropdownMenuItem(value: 4, child: Text('限制到 720p')),
                DropdownMenuItem(value: 5, child: Text('限制到 1080p')),
                DropdownMenuItem(value: 6, child: Text('限制到 4K')),
              ],
              onChanged: (value) =>
                  notifier.setQualityPreference(value ?? 0),
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('同分辨率优先 MP4'),
              subtitle: const Text('即使其他格式帧率/码率略高，也优先兼容性更好的 MP4'),
              value: settings.preferMp4,
              onChanged: notifier.setPreferMp4,
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('重复链接时询问'),
              subtitle: const Text('链接已在队列或下载过时，先确认再添加'),
              value: settings.duplicatePrompt,
              onChanged: notifier.setDuplicatePrompt,
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('添加后自动开始下载'),
              subtitle: const Text('关闭后新任务停在等待中，可从菜单「队列 → 开始全部」启动'),
              value: settings.autoStartDownloads,
              onChanged: notifier.setAutoStartDownloads,
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('在菜单栏 / 系统托盘显示'),
              subtitle: const Text('可从菜单栏快速显示窗口、开始/暂停全部下载'),
              value: settings.showInMenuBar,
              onChanged: notifier.setShowInMenuBar,
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('全部下载完成后退出应用'),
              value: settings.quitWhenDone,
              onChanged: notifier.setQuitWhenDone,
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
            const SizedBox(height: AppSpacing.xl),
            Text(
              '队列排序',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<int>(
              initialValue: settings.queueSort,
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
              ),
              items: const [
                DropdownMenuItem(value: 0, child: Text('添加时间')),
                DropdownMenuItem(value: 1, child: Text('名称')),
                DropdownMenuItem(value: 2, child: Text('站点')),
                DropdownMenuItem(value: 3, child: Text('优先级')),
              ],
              onChanged: (value) => notifier.setQueueSort(value ?? 0),
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('降序排列'),
              value: settings.queueSortDesc,
              onChanged: notifier.setQueueSortDesc,
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('显示下载缩略图'),
              subtitle: const Text('关闭后用深色渐变代替封面'),
              value: settings.showThumbnails,
              onChanged: notifier.setShowThumbnails,
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
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('按站点分文件夹'),
              subtitle: const Text('例如 YouTube/视频标题.mp4'),
              value: settings.subfolderBySite,
              onChanged: notifier.setSubfolderBySite,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              '文件名模板',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              initialValue: settings.filenameTemplate,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                hintText: '{title}',
                helperText: '可用占位符：{title} {extractor} {id} {date}',
              ),
              onChanged: notifier.setFilenameTemplate,
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
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('自动清理已删除的文件'),
              subtitle: const Text('启动时移除文件已不存在的完成记录'),
              value: settings.clearMissingHistory,
              onChanged: notifier.setClearMissingHistory,
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
              '浏览器扩展',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Downie6 为常用浏览器提供扩展：在视频页点击工具栏按钮，'
              '把当前链接发送到本机下载队列。点击浏览器图标导出/安装扩展：',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                _BrowserBadge(
                  label: 'Chrome',
                  color: const Color(0xFF4285F4),
                  icon: Icons.public,
                  onTap: () => _exportExtension(context),
                ),
                const SizedBox(width: AppSpacing.xl),
                _BrowserBadge(
                  label: 'Edge',
                  color: const Color(0xFF0AA1DD),
                  icon: Icons.waves,
                  onTap: () => _exportExtension(context),
                ),
                const SizedBox(width: AppSpacing.xl),
                _BrowserBadge(
                  label: 'Safari',
                  color: const Color(0xFF2F7CF6),
                  icon: Icons.explore_outlined,
                  onTap: () => _unsupportedBrowser(context, 'Safari'),
                ),
                const SizedBox(width: AppSpacing.xl),
                _BrowserBadge(
                  label: 'Firefox',
                  color: const Color(0xFFFF7139),
                  icon: Icons.local_fire_department_outlined,
                  onTap: () => _unsupportedBrowser(context, 'Firefox'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Chrome/Edge 会导出扩展文件夹，在浏览器扩展页选择「加载已解压的扩展程序」；'
              '安装后在扩展弹窗填入下方 token。Safari/Firefox 暂未提供，可先用书签脚本。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.xl),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.lg),
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
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('转换后删除原始文件'),
              subtitle: const Text('默认保留原始下载文件，便于手动重转'),
              value: settings.deleteOriginalAfterConversion,
              onChanged: notifier.setDeleteOriginalAfterConversion,
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
              title: const Text('下载字幕（如果可用）'),
              subtitle: const Text('新任务默认下载站点提供的字幕文件'),
              value: settings.defaultDownloadSubtitles,
              onChanged: notifier.setDefaultDownloadSubtitles,
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('包含自动生成的字幕'),
              subtitle: const Text('站点用语音识别生成的字幕（yt-dlp 任务）'),
              value: settings.includeAutoSubtitles,
              onChanged: notifier.setIncludeAutoSubtitles,
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('保存缩略图为 JPEG'),
              subtitle: const Text('新任务默认保存最高清的一张缩略图'),
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
              '字幕下载模式',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<int>(
              initialValue: settings.subtitleMode,
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
              ),
              items: const [
                DropdownMenuItem(value: 0, child: Text('全部匹配的语言')),
                DropdownMenuItem(value: 1, child: Text('只取第一个匹配的语言')),
              ],
              onChanged: (value) => notifier.setSubtitleMode(value ?? 0),
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
        return const _SupportedSitesPane();
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

  void _unsupportedBrowser(BuildContext context, String name) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text('$name 扩展暂未提供，可以先用下方书签脚本')),
    );
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

/// 支持站点：Downie 786 个下载器/变体的状态表。
///
/// 数据由 `tools/generate_site_coverage.py` 生成，随安装包内置；
/// 这里只做搜索/筛选，不发起网络请求。
class _SupportedSitesPane extends ConsumerStatefulWidget {
  const _SupportedSitesPane();

  @override
  ConsumerState<_SupportedSitesPane> createState() =>
      _SupportedSitesPaneState();
}

class _SupportedSitesPaneState extends ConsumerState<_SupportedSitesPane> {
  final TextEditingController _search = TextEditingController();
  SiteCoverageStatus? _filter;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(siteCoverageProvider);
    return async.when(
      loading: () => const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (e, _) => Center(
        child: Text(
          '站点列表加载失败：$e',
          style: theme.textTheme.bodySmall,
        ),
      ),
      data: (data) {
        final query = _search.text.trim();
        final rows = data.sites.where((row) {
          if (_filter != null && row.status != _filter) return false;
          return row.matches(query);
        }).toList(growable: false);
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '共 ${data.total} 个 Downie 下载器 · '
                      '原生 ${data.counts[SiteCoverageStatus.native] ?? 0}'
                      '（部分 ${data.counts[SiteCoverageStatus.nativePartial] ?? 0}）· '
                      'yt-dlp ${data.counts[SiteCoverageStatus.ytdlp] ?? 0} · '
                      '未复刻 ${data.counts[SiteCoverageStatus.generic] ?? 0}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  Text(
                    '显示 ${rows.length}',
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '搜索站点、域名或 yt-dlp 提取器',
                  prefixIcon: const Icon(Icons.search, size: 16),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.button),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _filterChip(null, '全部', data.sites.length),
                  for (final status in SiteCoverageStatus.values)
                    _filterChip(
                      status,
                      status.label,
                      data.counts[status] ?? 0,
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: rows.isEmpty
                  ? Center(
                      child: Text(
                        '没有匹配的站点',
                        style: theme.textTheme.bodySmall,
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const Divider(
                        height: 1,
                        indent: 16,
                        endIndent: 16,
                      ),
                      itemBuilder: (context, index) =>
                          _siteRow(context, rows[index]),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: Text(
                'yt-dlp 覆盖不等于原生复刻；通用资源检测是兜底，需逐站验证。'
                '完整表格见仓库 docs/site-coverage.md。',
                style: theme.textTheme.labelSmall,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _filterChip(SiteCoverageStatus? status, String label, int count) {
    final selected = _filter == status;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
      child: FilterChip(
        selected: selected,
        label: Text('$label $count', style: const TextStyle(fontSize: 11)),
        visualDensity: VisualDensity.compact,
        onSelected: (_) => setState(() => _filter = status),
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 2),
      ),
    );
  }

  Widget _siteRow(BuildContext context, SiteCoverageEntry row) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final color = switch (row.status) {
      SiteCoverageStatus.native => AppTokens.success,
      SiteCoverageStatus.nativePartial => AppTokens.warning,
      SiteCoverageStatus.ytdlp => AppTokens.accent,
      SiteCoverageStatus.generic =>
        dark ? AppTokens.textSecondary : AppTokens.textSecondaryLight,
      SiteCoverageStatus.drm => AppTokens.error,
    };
    final domain = row.domains.isEmpty ? row.className : row.domains.first;
    final extractorHint = row.ytdlpExtractors.isEmpty
        ? ''
        : ' · yt-dlp: ${row.ytdlpExtractors.take(2).join(', ')}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 7, 16, 7),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        row.site,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      row.priority,
                      style: TextStyle(
                        fontSize: 10,
                        color: dark
                            ? AppTokens.textTertiary
                            : AppTokens.textTertiaryLight,
                      ),
                    ),
                    if (row.verified) ...[
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.verified,
                        size: 12,
                        color: AppTokens.success,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '$domain$extractorHint',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: dark
                        ? AppTokens.textTertiary
                        : AppTokens.textTertiaryLight,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              row.status.label,
              style: TextStyle(fontSize: 10, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdvancedPane extends ConsumerStatefulWidget {
  const _AdvancedPane();

  @override
  ConsumerState<_AdvancedPane> createState() => _AdvancedPaneState();
}

class _AdvancedPaneState extends ConsumerState<_AdvancedPane> {
  String? _version;
  bool _updating = false;
  bool _selfTesting = false;
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

  Future<void> _selfTest() async {
    if (_selfTesting) return;
    setState(() => _selfTesting = true);
    final lines = <String>[];
    Future<void> check(String name, Future<String> Function() fn) async {
      try {
        final value = await fn().timeout(const Duration(seconds: 20));
        lines.add('✅ $name：$value');
      } catch (e) {
        lines.add('❌ $name：$e');
      }
    }

    await check('yt-dlp', () async {
      final path = await BinaryLocator.getYtDlpPath();
      final v = await YtDlpRunner.getVersion();
      return '$v  ($path)';
    });
    await check('ffmpeg', () async {
      final path = await BinaryLocator.getFFmpegPath();
      final v = await FFmpegRunner.getVersion();
      return '$v  ($path)';
    });
    await check('node（抖音签名）', () async {
      final path = await BinaryLocator.getNodePath();
      final r = await Process.run(path, ['--version']);
      if (r.exitCode != 0) throw Exception('exit ${r.exitCode}');
      return '${(r.stdout as String).trim()}  ($path)';
    });
    await check('应用数据目录', () async {
      final dir = await SettingsStorage.getStorageDir();
      return dir.path;
    });
    try {
      final dir = await SettingsStorage.getStorageDir();
      final logDir = Directory('${dir.path}/logs');
      lines.add(logDir.existsSync()
          ? '✅ 日志目录：${logDir.path}'
          : '⚠️ 日志目录尚未创建：${logDir.path}');
    } catch (e) {
      lines.add('❌ 日志目录：$e');
    }
    if (!mounted) return;
    setState(() => _selfTesting = false);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('环境自检'),
        content: SizedBox(
          width: 520,
          child: SelectableText(
            lines.join('\n'),
            style: const TextStyle(fontSize: 11, height: 1.5),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: lines.join('\n')));
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('复制并关闭'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
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
          '每个下载的连接数：${settings.connectionsPerDownload}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        Slider(
          min: 1,
          max: 16,
          divisions: 15,
          value: settings.connectionsPerDownload.toDouble(),
          label: '${settings.connectionsPerDownload}',
          onChanged: (v) => notifier.setConnectionsPerDownload(v.round()),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '全局限速（kB/s，0 表示不限）',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        TextFormField(
          initialValue: settings.throttleKbps == 0
              ? ''
              : '${settings.throttleKbps}',
          keyboardType: TextInputType.number,
          style: const TextStyle(fontSize: 13),
          decoration: const InputDecoration(
            hintText: '0',
            helperText: '传给 yt-dlp；对内置插件下载器暂不生效',
          ),
          onFieldSubmitted: (value) =>
              notifier.setThrottleKbps(int.tryParse(value.trim()) ?? 0),
          onChanged: (value) {
            final text = value.trim();
            if (text.isEmpty) {
              notifier.setThrottleKbps(0);
            } else {
              final parsed = int.tryParse(text);
              if (parsed != null) notifier.setThrottleKbps(parsed);
            }
          },
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('保存元数据 JSON'),
          subtitle: const Text('yt-dlp 任务写入 info.json；内置插件任务写入基础字段'),
          value: settings.saveMetadataJson,
          onChanged: notifier.setSaveMetadataJson,
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('下载完成/失败播放提示音'),
          value: settings.playSounds,
          onChanged: notifier.setPlaySounds,
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('强制重新编码 HLS/DASH'),
          subtitle: const Text('传递 --recode-video mp4；会增加处理时间'),
          value: settings.forceReencode,
          onChanged: notifier.setForceReencode,
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('使用原生 HLS 下载器'),
          subtitle: const Text('传递 --hls-prefer-native；部分站点更快，但兼容性可能不同'),
          value: settings.nativeHlsEngine,
          onChanged: notifier.setNativeHlsEngine,
        ),
        const Divider(height: 24),
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.health_and_safety_outlined, size: 18),
          title: const Text('运行环境自检'),
          subtitle: const Text('检查 yt-dlp / ffmpeg / node / 数据目录 / 日志目录'),
          trailing: _selfTesting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : TextButton(
                  onPressed: _selfTest,
                  child: const Text('开始'),
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

class _BrowserBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  const _BrowserBadge({
    required this.label,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final text = dark ? AppTokens.textPrimary : AppTokens.textPrimaryLight;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.panel),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(AppRadius.panel),
              ),
              child: Icon(icon, size: 20, color: Colors.white),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(label, style: TextStyle(fontSize: 11, color: text)),
          ],
        ),
      ),
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
