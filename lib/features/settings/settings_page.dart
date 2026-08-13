import 'package:flutter/material.dart';

/// 设置页（阶段1占位）
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _darkMode = false;
  bool _autoStart = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('设置', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 24),
            // 通用设置
            _buildSection(theme, '通用', [
              SwitchListTile(
                title: const Text('深色模式'),
                subtitle: const Text('跟随系统或手动切换'),
                value: _darkMode,
                onChanged: (value) => setState(() => _darkMode = value),
              ),
              SwitchListTile(
                title: const Text('开机自启动'),
                subtitle: const Text('系统启动时自动运行'),
                value: _autoStart,
                onChanged: (value) => setState(() => _autoStart = value),
              ),
            ]),
            const SizedBox(height: 16),
            // 下载设置
            _buildSection(theme, '下载', [
              ListTile(
                leading: const Icon(Icons.folder),
                title: const Text('下载目录'),
                subtitle: const Text('~/Downloads'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {},
              ),
              ListTile(
                leading: const Icon(Icons.speed),
                title: const Text('并行下载数'),
                subtitle: const Text('3 个'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {},
              ),
              SwitchListTile(
                title: const Text('下载字幕'),
                subtitle: const Text('自动下载视频字幕'),
                value: false,
                onChanged: (value) {},
              ),
            ]),
            const SizedBox(height: 16),
            // 关于
            _buildSection(theme, '关于', [
              ListTile(
                leading: const Icon(Icons.info),
                title: const Text('版本'),
                subtitle: const Text('1.0.0'),
              ),
              ListTile(
                leading: const Icon(Icons.workspace_premium),
                title: const Text('许可证'),
                subtitle: const Text('免费版 - 每日 5 次下载'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {},
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
}
