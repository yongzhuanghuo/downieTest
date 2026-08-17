import 'package:flutter/widgets.dart';

/// 全局导航 key，用于从非 UI 层（如下载任务）弹出对话框。
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
