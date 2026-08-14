import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings_provider.dart';

/// 设置页
///
/// 所有设置项均通过 [SettingsNotifier] 实时持久化到 Hive，
/// 修改后立即生效且重启不丢失。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('设置', style: theme.textTheme.headlineSmall),
                      const SizedBox(height: 4),
                      Text(
                        '修改后自动保存，重启后依然生效',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _confirmReset(context, notifier),
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('恢复默认'),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ==================== 下载设置 ====================
            _buildSection(theme, '下载', [
              ListTile(
                leading: const Icon(Icons.folder),
                title: const Text('下载目录'),
                subtitle: Text(settings.downloadDirLabel),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _pickDownloadDir(context, notifier),
              ),
              ListTile(
                leading: const Icon(Icons.speed),
                title: const Text('并行下载数'),
                subtitle: Text('${settings.maxConcurrent} 个同时下载'),
                trailing: SizedBox(
                  width: 180,
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: settings.maxConcurrent > 1
                            ? () => notifier.setMaxConcurrent(
                                settings.maxConcurrent - 1)
                            : null,
                      ),
                      Expanded(
                        child: Slider(
                          min: 1,
                          max: 10,
                          divisions: 9,
                          value: settings.maxConcurrent.toDouble(),
                          label: '${settings.maxConcurrent}',
                          onChanged: (v) =>
                              notifier.setMaxConcurrent(v.round()),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: settings.maxConcurrent < 10
                            ? () => notifier.setMaxConcurrent(
                                settings.maxConcurrent + 1)
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
              SwitchListTile(
                title: const Text('下载字幕'),
                subtitle: const Text('自动下载视频字幕（如有）'),
                value: settings.downloadSubtitles,
                onChanged: notifier.setDownloadSubtitles,
              ),
              SwitchListTile(
                title: const Text('下载完成自动打开文件夹'),
                subtitle: const Text('下载完成后在文件管理器中显示文件'),
                value: settings.autoOpenFolder,
                onChanged: notifier.setAutoOpenFolder,
              ),
            ]),

            const SizedBox(height: 16),

            // ==================== 外观 ====================
            _buildSection(theme, '外观', [
              ListTile(
                leading: const Icon(Icons.brightness_6),
                title: const Text('主题模式'),
                subtitle: Text(_themeModeLabel(settings.themeMode)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showThemePicker(context, settings.themeMode,
                    (mode) => notifier.setThemeMode(mode)),
              ),
            ]),

            const SizedBox(height: 16),

            // ==================== 系统 ====================
            _buildSection(theme, '系统', [
              SwitchListTile(
                title: const Text('开机自启动'),
                subtitle: const Text('系统启动时自动运行'),
                value: settings.autoStart,
                onChanged: notifier.setAutoStart,
              ),
            ]),

            const SizedBox(height: 16),

            // ==================== 关于 ====================
            _buildSection(theme, '关于', [
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('版本'),
                subtitle: const Text('1.0.0'),
              ),
              ListTile(
                leading: const Icon(Icons.workspace_premium),
                title: const Text('许可证'),
                subtitle: const Text('免费版 - 每日 5 次下载'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('会员体系即将上线，敬请期待')),
                  );
                },
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(ThemeData theme, String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 8),
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  // ==================== 交互方法 ====================

  Future<void> _pickDownloadDir(
    BuildContext context,
    SettingsNotifier notifier,
  ) async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择下载目录',
    );
    if (result != null) {
      await notifier.setDownloadDir(result);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载目录已设置为：$result')),
        );
      }
    }
  }

  String _themeModeLabel(int mode) {
    switch (mode) {
      case 1:
        return '浅色模式';
      case 2:
        return '深色模式';
      default:
        return '跟随系统';
    }
  }

  Future<void> _showThemePicker(
    BuildContext context,
    int current,
    ValueChanged<int> onPicked,
  ) async {
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('主题模式'),
        children: [
          _themeOption(ctx, 0, '跟随系统', current, onPicked),
          _themeOption(ctx, 1, '浅色模式', current, onPicked),
          _themeOption(ctx, 2, '深色模式', current, onPicked),
        ],
      ),
    );
    if (picked != null) onPicked(picked);
  }

  SimpleDialogOption _themeOption(
    BuildContext ctx,
    int value,
    String label,
    int current,
    ValueChanged<int> onPicked,
  ) {
    return SimpleDialogOption(
      onPressed: () => Navigator.of(ctx).pop(value),
      child: Row(
        children: [
          Icon(
            current == value ? Icons.radio_button_checked : Icons.radio_button_off,
            color: current == value
                ? Theme.of(ctx).colorScheme.primary
                : Theme.of(ctx).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Text(label),
        ],
      ),
    );
  }

  Future<void> _confirmReset(
    BuildContext context,
    SettingsNotifier notifier,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复默认设置'),
        content: const Text('确认将所有设置恢复为默认值？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await notifier.reset();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已恢复默认设置')),
        );
      }
    }
  }
}
