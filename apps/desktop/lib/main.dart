import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/engine/ytdlp_runner.dart';
import 'core/ffmpeg/ffmpeg_runner.dart';
import 'core/platform/binary_initializer.dart';
import 'core/platform/binary_locator.dart';
import 'core/storage/settings_storage.dart';
import 'core/version/version_check.dart';
import 'features/license/license_provider.dart';

/// 窗口配置常量
const Size _defaultWindowSize = Size(1100, 750);
const Size _minWindowSize = Size(800, 600);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化窗口管理器（桌面端）
  await _initWindowManager();

  // 初始化本地存储（Hive KV）—— 设置 + 许可证
  await SettingsStorage.instance.init();
  await LicenseStorage.instance.init();

  // 文件日志：把 debugPrint 同时写到日志文件，打包版双击启动也能排查
  await _setupFileLogging();

  // 初始化 yt-dlp / FFmpeg 二进制（后台执行，不阻塞 UI）
  _initBinaries();

  // 启动后延迟检查应用新版本（后台，有新版弹窗，无则静默）
  _checkAppUpdate();

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
    title: '4KDownle',
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

  // 4. 后台自动更新 yt-dlp（fire-and-forget，不阻塞启动）
  _autoUpdateYtDlp();
}

/// 后台自动更新 yt-dlp 到最新版。
///
/// `yt-dlp -U` 内部会对比版本，发现新版才下载替换自己（已最新不会重复下载）。
/// 打包版的内嵌 standalone 二进制支持自更新；开发态走 PATH 的 brew/pip 版
/// 会被禁用，失败静默降级继续用旧版，不影响下载。
/// 套 60s 超时，防止国内 GitHub 慢导致后台进程一直挂着。
void _autoUpdateYtDlp() {
  unawaited(() async {
    try {
      final r = await YtDlpRunner.update().timeout(const Duration(seconds: 60));
      debugPrint('[更新] yt-dlp: ${r.message}');
    } catch (e) {
      debugPrint('[更新] yt-dlp 自动更新失败（降级继续用旧版）: $e');
    }
  }());
}

/// 启动后延迟检查应用新版本。
///
/// 延迟 3s 等 UI 就绪 + navigator context 可用；失败静默（连不上服务器也不打扰用户）。
void _checkAppUpdate() {
  unawaited(() async {
    try {
      await Future.delayed(const Duration(seconds: 3));
      final info = await checkForUpdate();
      if (info != null) {
        await showUpdateDialog(info);
      }
    } catch (e) {
      debugPrint('[更新] 版本检查失败（静默）: $e');
    }
  }());
}

/// 把 debugPrint 同时写到日志文件（应用支持目录 logs/ 下，按天命名）。
/// 打包版双击启动时 stdout 没有控制台，日志会丢失，写文件后可随时排查。
Future<void> _setupFileLogging() async {
  try {
    final dir = await SettingsStorage.getStorageDir();
    final logDir = Directory('${dir.path}/logs');
    await logDir.create(recursive: true);
    final now = DateTime.now();
    final name = 'app_${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}.log';
    final file = File('${logDir.path}/$name');

    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) {
        try {
          file.writeAsStringSync(
            '${DateTime.now().toIso8601String()} $message\n',
            mode: FileMode.append,
          );
        } catch (_) {}
      }
      original(message, wrapWidth: wrapWidth);
    };
  } catch (e) {
    debugPrint('日志文件初始化失败: $e');
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
