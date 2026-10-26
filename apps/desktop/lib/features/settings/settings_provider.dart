import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/server/browser_bridge.dart';
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

  Future<void> setProxy(String value) async {
    final next = state.copyWith(proxy: value.trim());
    await SettingsStorage.instance.save(next);
    state = next;
  }

  Future<void> setDefaultPostprocessing(int mode) async {
    final next = state.copyWith(defaultPostprocessing: mode.clamp(0, 2));
    await SettingsStorage.instance.save(next);
    state = next;
  }

  Future<void> setDefaultDownloadSubtitles(bool value) async {
    final next = state.copyWith(defaultDownloadSubtitles: value);
    await SettingsStorage.instance.save(next);
    state = next;
  }

  Future<void> setDefaultDownloadCover(bool value) async {
    final next = state.copyWith(defaultDownloadCover: value);
    await SettingsStorage.instance.save(next);
    state = next;
  }

  Future<void> setNotifyOnComplete(bool value) async {
    final next = state.copyWith(notifyOnComplete: value);
    await SettingsStorage.instance.save(next);
    state = next;
  }

  Future<void> setBrowserBridgeEnabled(bool enabled) async {
    var token = state.browserBridgeToken;
    if (enabled && token.isEmpty) {
      token = BrowserBridge.generateToken();
    }
    final next = state.copyWith(
      browserBridgeEnabled: enabled,
      browserBridgeToken: token,
    );
    await SettingsStorage.instance.save(next);
    state = next;
  }

  Future<void> regenerateBrowserBridgeToken() async {
    final next = state.copyWith(
      browserBridgeToken: BrowserBridge.generateToken(),
    );
    await SettingsStorage.instance.save(next);
    state = next;
  }

  Future<void> setCookiesFromBrowser(String browser) async {
    const allowed = {'', 'chrome', 'safari', 'edge', 'firefox', 'brave'};
    final next = state.copyWith(
      cookiesFromBrowser: allowed.contains(browser) ? browser : '',
    );
    await SettingsStorage.instance.save(next);
    state = next;
  }

  Future<void> setSearchEngine(int id) async {
    final next = state.copyWith(searchEngine: id.clamp(0, 3));
    await SettingsStorage.instance.save(next);
    state = next;
  }

  Future<void> setHistoryDays(int days) async {
    final allowed = {0, 7, 30, 90, 365};
    final next = state.copyWith(
      historyDays: allowed.contains(days) ? days : 0,
    );
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
