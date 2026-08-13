import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';

/// 窗口配置常量
const Size _defaultWindowSize = Size(1100, 750);
const Size _minWindowSize = Size(800, 600);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化窗口管理器（桌面端）
  await _initWindowManager();

  runApp(
    const ProviderScope(
      child: DownloApp(),
    ),
  );
}

/// 初始化桌面窗口
Future<void> _initWindowManager() async {
  await windowManager.ensureInitialized();

  final windowOptions = WindowOptions(
    size: _defaultWindowSize,
    minimumSize: _minWindowSize,
    center: true,
    title: 'Downlo PRO',
    titleBarStyle: TitleBarStyle.normal,
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}
