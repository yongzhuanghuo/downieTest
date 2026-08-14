import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/settings_storage.dart';

/// 设置状态 Notifier
///
/// 包装 [SettingsStorage]，提供响应式更新。
/// UI 修改设置时调用对应方法，自动持久化并通知监听者。
class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier() : super(SettingsStorage.instance.current);

  Future<void> setDownloadDir(String dir) async {
    final next = state.copyWith(downloadDir: dir);
    await SettingsStorage.instance.save(next);
    state = next;
  }

  Future<void> setMaxConcurrent(int value) async {
    final clamped = value.clamp(1, 10);
    final next = state.copyWith(maxConcurrent: clamped);
    await SettingsStorage.instance.save(next);
    state = next;
  }

  Future<void> setDownloadSubtitles(bool v) async {
    final next = state.copyWith(downloadSubtitles: v);
    await SettingsStorage.instance.save(next);
    state = next;
  }

  Future<void> setThemeMode(int mode) async {
    final next = state.copyWith(themeMode: mode);
    await SettingsStorage.instance.save(next);
    state = next;
  }

  Future<void> setAutoStart(bool v) async {
    final next = state.copyWith(autoStart: v);
    await SettingsStorage.instance.save(next);
    state = next;
  }

  Future<void> setAutoOpenFolder(bool v) async {
    final next = state.copyWith(autoOpenFolder: v);
    await SettingsStorage.instance.save(next);
    state = next;
  }

  /// 重置为默认
  Future<void> reset() async {
    await SettingsStorage.instance.save(AppSettings.defaults);
    state = AppSettings.defaults;
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettings>(
        (ref) => SettingsNotifier());

/// 主题模式（响应式）
final themeModeProvider = Provider<ThemeMode>((ref) {
  final mode = ref.watch(settingsProvider.select((s) => s.themeMode));
  switch (mode) {
    case 1:
      return ThemeMode.light;
    case 2:
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
});
