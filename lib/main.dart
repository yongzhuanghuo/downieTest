import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/engine/ytdlp_runner.dart';
import 'core/ffmpeg/ffmpeg_runner.dart';
import 'core/platform/binary_initializer.dart';
import 'core/platform/binary_locator.dart';

/// 窗口配置常量
const Size _defaultWindowSize = Size(1100, 750);
const Size _minWindowSize = Size(800, 600);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化窗口管理器（桌面端）
  await _initWindowManager();

  // 初始化 yt-dlp / FFmpeg 二进制（后台执行，不阻塞 UI）
  _initBinaries();

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

/// 后台初始化二进制引擎
///
/// 查找顺序：
/// 1. 工作目录已有（打包态，首次从 assets 提取过）
/// 2. assets 提取（打包态首次运行）
/// 3. 系统 PATH（开发态，复用 brew 安装）
Future<void> _initBinaries() async {
  try {
    // 1. 尝试从 assets 提取（打包态首次运行）
    final result = await BinaryInitializer.initialize();
    debugPrint('[Engine] Binary init: $result');
  } catch (e) {
    debugPrint('[Engine] assets 提取失败（开发态正常）: $e');
  }

  // 2. 验证 BinaryLocator 能否找到可用二进制（含 PATH fallback）
  final debugInfo = await BinaryLocator.getDebugInfo();
  debugPrint('[Engine] === 引擎路径调试 ===\n$debugInfo');

  // 3. 验证版本
  final ytDlpVersion = await _safeRun(() => YtDlpRunner.getVersion());
  final ffmpegVersion = await _safeRun(() => FFmpegRunner.getVersion());
  debugPrint('[Engine] yt-dlp: $ytDlpVersion');
  debugPrint('[Engine] ffmpeg: $ffmpegVersion');

  if (ytDlpVersion == null || ffmpegVersion == null) {
    debugPrint('[Engine] ⚠️ 引擎未就绪，请确认 yt-dlp / ffmpeg 已安装');
  } else {
    debugPrint('[Engine] ✅ 引擎就绪');
  }
}

/// 安全执行（错误吞掉，返回 null）
Future<String?> _safeRun(Future<String> Function() fn) async {
  try {
    return await fn();
  } catch (_) {
    return null;
  }
}
