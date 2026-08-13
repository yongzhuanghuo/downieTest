import 'dart:io';

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
/// 首次运行会从 assets 提取 yt-dlp / FFmpeg 到应用数据目录。
/// 此操作不阻塞 UI，用户在阶段3点击解析时会等待此初始化完成。
Future<void> _initBinaries() async {
  try {
    // 先把 assets 里的二进制复制到工作目录
    final result = await BinaryInitializer.initialize();
    debugPrint('[Engine] Binary init: $result');

    // 验证版本（开发期从 assets/bin/macos 直接复制后调用）
    if (result.success) {
      final ytDlpVersion = await _safeRun(() => YtDlpRunner.getVersion());
      final ffmpegVersion = await _safeRun(() => FFmpegRunner.getVersion());
      debugPrint('[Engine] yt-dlp: $ytDlpVersion');
      debugPrint('[Engine] ffmpeg: $ffmpegVersion');
    } else {
      // 开发态 fallback：直接从 assets 目录复制
      await _copyBinariesFromAssetsDirect();
    }
  } catch (e) {
    debugPrint('[Engine] 初始化失败: $e');
    // 尝试开发态 fallback
    await _copyBinariesFromAssetsDirect();
  }
}

/// 开发态直接从 `assets/bin/<platform>/` 复制二进制到工作目录
Future<void> _copyBinariesFromAssetsDirect() async {
  try {
    final binDir = await BinaryLocator.getBinDirectory();
    final platformDir = Platform.isMacOS ? 'macos' : 'windows';

    for (final fileName in [
      BinaryLocator.ytDlpFileName,
      BinaryLocator.ffmpegFileName,
    ]) {
      final srcPath = 'assets/bin/$platformDir/$fileName';
      final srcFile = File(srcPath);
      if (srcFile.existsSync()) {
        final destPath = '${binDir.path}/$fileName';
        await srcFile.copy(destPath);
        if (!Platform.isWindows) {
          await Process.run('chmod', ['+x', destPath]);
        }
        debugPrint('[Engine] 已复制 $fileName -> $destPath');
      } else {
        debugPrint('[Engine] 警告: $srcPath 不存在');
      }
    }
  } catch (e) {
    debugPrint('[Engine] 开发态复制失败: $e');
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
