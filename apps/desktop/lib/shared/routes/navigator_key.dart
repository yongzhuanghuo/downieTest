import 'package:flutter/material.dart';

/// 全局导航 key，用于从非 UI 层（如下载任务）弹出对话框。
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// 主窗口内容区导航（标题栏下方）。
///
/// 帮助 / 支持 / 用户自定义提取等整窗页面都压在这里，避免盖住主标题栏；
/// 从标题栏菜单或原生菜单打开时也能正确落到内容区。
final GlobalKey<NavigatorState> contentNavigatorKey = GlobalKey<NavigatorState>();

Future<T?> pushContentRoute<T>(BuildContext context, Route<T> route) {
  final navigator = contentNavigatorKey.currentState;
  if (navigator != null) return navigator.push<T>(route);
  return Navigator.of(context, rootNavigator: true).push<T>(route);
}
