import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/platform/window_close_coordinator.dart';
import '../../shared/branding/app_brand.dart';
import '../../shared/widgets/restore_glyph.dart';
import 'help_content.dart';
import 'support_dialog.dart';

/// 帮助窗口：左侧主题列表 + 右侧内容，整窗铺开，不使用浮层卡片。
class HelpWindow extends StatefulWidget {
  const HelpWindow({super.key});

  static Future<void> show(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, __, ___) => const HelpWindow(),
      ),
    );
  }

  @override
  State<HelpWindow> createState() => _HelpWindowState();
}

class _HelpWindowState extends State<HelpWindow> with WindowListener {
  HelpTopic? _selected;
  String _query = '';
  bool _closing = false;
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    WindowCloseCoordinator.instance.push(this, _close);
    _syncMaximized();
  }

  Future<void> _syncMaximized() async {
    try {
      final maximized = await windowManager.isMaximized();
      final fullscreen = await windowManager.isFullScreen();
      if (mounted) setState(() => _maximized = maximized || fullscreen);
    } catch (_) {}
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _maximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _maximized = false);
  }

  @override
  void onWindowEnterFullScreen() {
    if (mounted) setState(() => _maximized = true);
  }

  @override
  void onWindowLeaveFullScreen() {
    if (mounted) setState(() => _maximized = false);
  }

  Future<void> _toggleMaximize() async {
    try {
      if (await windowManager.isFullScreen()) {
        await windowManager.setFullScreen(false);
      } else if (await windowManager.isMaximized()) {
        await windowManager.unmaximize();
      } else {
        await windowManager.maximize();
      }
      await _syncMaximized();
    } catch (_) {}
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    WindowCloseCoordinator.instance.pop(this);
    super.dispose();
  }

  void _close() {
    if (_closing || !mounted) return;
    _closing = true;
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = _query.trim().toLowerCase();
    final topics = q.isEmpty
        ? kHelpTopics
        : kHelpTopics
            .where((t) =>
                t.title.toLowerCase().contains(q) ||
                t.summary.toLowerCase().contains(q))
            .toList();

    final isMac = Platform.isMacOS;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): _close,
        SingleActivator(
          LogicalKeyboardKey.keyW,
          meta: isMac,
          control: !isMac,
        ): _close,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: theme.colorScheme.surface,
          body: Column(
            children: [
              _buildHeader(theme),
              Divider(
                height: 1,
                color: theme.dividerColor.withValues(alpha: 0.4),
              ),
              Expanded(
                child: Row(
                  children: [
                    _buildSidebar(theme, topics),
                    VerticalDivider(
                      width: 1,
                      color: theme.dividerColor.withValues(alpha: 0.4),
                    ),
                    Expanded(child: _buildContent(theme)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => windowManager.startDragging(),
      onDoubleTap: _toggleMaximize,
      child: Container(
        height: 52,
        padding: EdgeInsets.fromLTRB(Platform.isMacOS ? 92 : 16, 0, 8, 0),
        child: Row(
          children: [
            Icon(Icons.help_outline,
                size: 18, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Text(
              '帮助',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            if (Platform.isWindows) ...[
              IconButton(
                tooltip: '最小化',
                icon: const Icon(Icons.remove, size: 15),
                onPressed: () => windowManager.minimize(),
              ),
              IconButton(
                tooltip: _maximized ? '还原' : '最大化',
                icon: _maximized
                    ? RestoreGlyph(
                        color: theme.colorScheme.onSurfaceVariant,
                        size: 12,
                      )
                    : const Icon(Icons.crop_square, size: 13),
                onPressed: _toggleMaximize,
              ),
            ],
            IconButton(
              tooltip: '关闭',
              icon: const Icon(Icons.close, size: 20),
              onPressed: _close,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar(ThemeData theme, List<HelpTopic> topics) {
    return Container(
      width: 260,
      color: theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.55),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: '搜索帮助',
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                filled: true,
                fillColor: theme.colorScheme.surface,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
              itemCount: topics.length,
              itemBuilder: (context, index) {
                final topic = topics[index];
                final selected = identical(_selected, topic);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Material(
                    color: selected
                        ? theme.colorScheme.primary.withValues(alpha: 0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => setState(() => _selected = topic),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        child: Text(
                          topic.title,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: selected
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurface,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(ThemeData theme) {
    final topic = _selected;
    return Scrollbar(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(44, 36, 44, 48),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: topic == null ? _buildHome(theme) : _buildTopic(theme, topic),
          ),
        ),
      ),
    );
  }

  Widget _buildHome(ThemeData theme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 40),
        ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Image.asset(AppBrand.logoAsset, width: 96, height: 96),
        ),
        const SizedBox(height: 24),
        Text(
          '${AppBrand.name} 帮助',
          style: theme.textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.w600),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          '选择左侧主题查看使用说明，或从「快速开始」开始。',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: () => setState(() => _selected = kHelpTopics.first),
          icon: const Icon(Icons.play_arrow),
          label: const Text('快速开始'),
        ),
      ],
    );
  }

  Widget _buildTopic(ThemeData theme, HelpTopic topic) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          topic.title,
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          topic.summary,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        for (final paragraph in topic.paragraphs) ...[
          Text(
            paragraph,
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.65),
          ),
          const SizedBox(height: 16),
        ],
        const SizedBox(height: 8),
        _buildSupportCard(theme),
      ],
    );
  }

  Widget _buildSupportCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.support_agent, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '需要更多帮助？',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  '发邮件到 ${AppBrand.supportEmail}，或打开报告窗口。',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => SupportDialog.show(context),
            child: const Text('联系支持'),
          ),
        ],
      ),
    );
  }
}
