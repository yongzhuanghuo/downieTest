import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../branding/app_brand.dart';
import '../theme/design_tokens.dart';
import 'window_menu_button.dart';

/// 统一标题栏。
///
/// macOS 保留系统红黄绿交通灯，中间只放标题；
/// Windows 自绘最小化/最大化/关闭，和 macOS 共用同一套内容布局。
class WindowTitleBar extends StatelessWidget {
  const WindowTitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? AppTokens.titleBar : AppTokens.titleBarLight;
    final foreground = dark ? AppTokens.textPrimary : AppTokens.textPrimaryLight;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => windowManager.startDragging(),
      onDoubleTap: _toggleMaximize,
      child: Container(
        height: 32,
        color: background,
        child: Platform.isMacOS
            ? _macTitle(foreground)
            : _windowsTitle(context, foreground),
      ),
    );
  }

  Widget _macTitle(Color foreground) {
    return Row(
      children: [
        // 给系统交通灯留位置；Downie 的标题在左侧，不在正中
        const SizedBox(width: 92),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              AppBrand.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.windowTitle(foreground),
            ),
          ),
        ),
        const WindowMenuButton(),
        const SizedBox(width: 6),
      ],
    );
  }

  Widget _windowsTitle(BuildContext context, Color foreground) {
    final secondary =
        Theme.of(context).brightness == Brightness.dark
            ? AppTokens.textSecondary
            : AppTokens.textSecondaryLight;
    return Row(
      children: [
        const SizedBox(width: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.control),
          child: Image.asset(
            AppBrand.logoAsset,
            width: 16,
            height: 16,
            filterQuality: FilterQuality.medium,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            AppBrand.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.windowTitle(foreground),
          ),
        ),
        const WindowMenuButton(),
        _CaptionButton(
          icon: Icons.remove,
          tooltip: '最小化',
          color: secondary,
          onTap: () => windowManager.minimize(),
        ),
        _CaptionButton(
          icon: Icons.crop_square,
          tooltip: '最大化',
          color: secondary,
          onTap: _toggleMaximize,
        ),
        _CaptionButton(
          icon: Icons.close,
          tooltip: '关闭',
          color: secondary,
          hoverColor: AppTokens.error,
          onTap: () => windowManager.close(),
        ),
      ],
    );
  }

  Future<void> _toggleMaximize() async {
    try {
      if (await windowManager.isMaximized()) {
        await windowManager.unmaximize();
      } else {
        await windowManager.maximize();
      }
    } catch (e) {
      debugPrint('[窗口] 最大化切换失败: $e');
    }
  }
}

class _CaptionButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;
  final Color? hoverColor;

  const _CaptionButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
    this.hoverColor,
  });

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final hover = widget.hoverColor ??
        (Theme.of(context).brightness == Brightness.dark
            ? AppTokens.hover
            : AppTokens.hoverLight);
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            width: 44,
            height: 32,
            color: _hovering ? hover : Colors.transparent,
            alignment: Alignment.center,
            child: Icon(
              widget.icon,
              size: 12,
              color: _hovering && widget.hoverColor != null
                  ? widget.hoverColor
                  : widget.color,
            ),
          ),
        ),
      ),
    );
  }
}
