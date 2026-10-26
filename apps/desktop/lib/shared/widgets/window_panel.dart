import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';

/// 单 OS 窗口内的「窗样式」浮层。
///
/// Downie 的设置/历史/帮助是独立窗口；Flutter 第一版用无遮罩浮层模拟，
/// 保留标题栏、关闭按钮和窗口阴影。
Future<T?> showWindowPanel<T>({
  required BuildContext context,
  required String title,
  required double width,
  required double height,
  required Widget child,
  Color barrierColor = Colors.transparent,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: false,
    barrierLabel: title,
    barrierColor: barrierColor,
    transitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (context, animation, secondaryAnimation) {
      return Center(
        child: WindowPanel(
          title: title,
          width: width,
          height: height,
          child: child,
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      );
    },
  );
}

class WindowPanel extends StatelessWidget {
  final String title;
  final double width;
  final double height;
  final Widget child;

  const WindowPanel({
    super.key,
    required this.title,
    required this.width,
    required this.height,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final panel = dark ? AppTokens.panel : AppTokens.panelLight;
    final titleBar = dark ? AppTokens.titleBar : AppTokens.titleBarLight;
    final divider = dark ? AppTokens.divider : AppTokens.dividerLight;
    final text = dark ? AppTokens.textPrimary : AppTokens.textPrimaryLight;
    final secondary =
        dark ? AppTokens.textSecondary : AppTokens.textSecondaryLight;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(AppRadius.window),
          border: Border.all(color: divider),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 28,
              offset: Offset(0, 12),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Container(
              height: 36,
              color: titleBar,
              padding: const EdgeInsets.only(left: 14, right: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.windowTitle(text),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    tooltip: '关闭',
                    icon: Icon(Icons.close, size: 14, color: secondary),
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints.tightFor(width: 30, height: 30),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: divider),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
