import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../core/license/license.dart';
import '../../core/license/license_client.dart';
import '../../core/storage/settings_storage.dart';

/// ===================================================================
/// 许可证本地持久化（Hive KV）
/// 存储内容:
///   - 'activated': ActivatedLicense 的 Map
///   - 'quota_YYYYMMDD': 当天已下载次数
/// ===================================================================
class LicenseStorage {
  LicenseStorage._();
  static final instance = LicenseStorage._();

  static const _boxName = 'downlo_license';
  static const _keyLicense = 'license';

  Box? _box;
  ActivatedLicense? _cached;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final dir = await SettingsStorage.getStorageDir();
      Hive.init('${dir.path}/hive');
      _box = await Hive.openBox(_boxName);
    } catch (e) {
      debugPrint('[LicenseStorage] 存储初始化失败: $e');
    }
    final raw = _box?.get(_keyLicense);
    if (raw is Map) {
      try {
        _cached = ActivatedLicense.fromMap(Map<String, dynamic>.from(raw));
      } catch (e) {
        stderr.writeln('[LicenseStorage] 反序列化失败: $e');
        _cached = null;
      }
    }
  }

  ActivatedLicense? get current => _cached;

  /// 是否已激活 PRO
  bool get isPro => _cached?.isPro ?? false;

  /// 当前最大清晰度（免费 1080，PRO 4000+）
  int get maxHeight => isPro ? 10000 : 1080;

  /// 每日限额（免费 2 个，PRO 不限）
  int? get dailyQuota => isPro ? null : 2;

  /// 保存（覆盖）激活信息
  Future<void> save(ActivatedLicense license) async {
    _cached = license;
    await _box?.put(_keyLicense, license.toMap());
  }

  /// 清除激活（比如换绑，MVP 暂保留接口）
  Future<void> clear() async {
    _cached = null;
    await _box?.delete(_keyLicense);
  }

  // ================= 每日限额 =================

  static String _todayKey() {
    final now = DateTime.now();
    return 'quota_${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
  }

  /// 今日已下载次数
  int get todayUsed {
    return (_box?.get(_todayKey()) as int?) ?? 0;
  }

  /// 今日剩余可下载（null=不限）
  int? get todayRemaining {
    final limit = dailyQuota;
    if (limit == null) return null;
    return (limit - todayUsed).clamp(0, 99999);
  }

  /// 记录一次下载成功（调用点在任务 completed）
  Future<void> recordSuccess() async {
    final key = _todayKey();
    final cur = (_box?.get(key) as int?) ?? 0;
    await _box?.put(key, cur + 1);
  }

  /// 是否达到限额（PRO 永远 false）
  bool get isQuotaReached {
    final rem = todayRemaining;
    if (rem == null) return false;
    return rem <= 0;
  }

  /// 尝试占坑（先判断限额），true=可以下载
  bool acquireSlot() {
    final rem = todayRemaining;
    if (rem == null) return true;
    return rem > 0;
  }
}

/// ===================================================================
/// License Provider：UI 可直接 watch 监听激活状态/限额变化
/// 使用 StateProvider 直接更新 .state，避免 ref.invalidate 导致的依赖冲突
/// ===================================================================

/// 激活状态（可能为 null=免费版）
final activatedLicenseProvider = StateProvider<ActivatedLicense?>((ref) {
  return LicenseStorage.instance.current;
});

/// 是否 PRO（派生自 activatedLicenseProvider）
final isProProvider = Provider<bool>((ref) {
  return ref.watch(activatedLicenseProvider)?.isPro ?? false;
});

/// 最大允许高度（派生自 activatedLicenseProvider）
final maxAllowedHeightProvider = Provider<int>((ref) {
  final license = ref.watch(activatedLicenseProvider);
  if (license == null) return 1080;
  return license.isPro ? 10000 : 1080;
});

/// 今日已用次数
final todayUsedProvider = StateProvider<int>((ref) {
  return LicenseStorage.instance.todayUsed;
});

/// 今日剩余次数（null=不限）
final todayRemainingProvider = StateProvider<int?>((ref) {
  return LicenseStorage.instance.todayRemaining;
});

/// 是否达到限额
final isQuotaReachedProvider = StateProvider<bool>((ref) {
  return LicenseStorage.instance.isQuotaReached;
});

/// Notifier：激活码激活（调用 verify + 绑定设备指纹 + 保存）
class LicenseNotifier extends StateNotifier<AsyncValue<ActivatedLicense?>> {
  final Ref ref;
  LicenseNotifier(this.ref) : super(const AsyncValue.data(null));

  /// 激活激活码
  /// 流程: 本地验签 → 请求后端绑定设备 → 保存到本地
  Future<(bool success, String message)> activate(String rawCode) async {
    final code = rawCode.trim();
    if (code.isEmpty) {
      return (false, '请输入激活码');
    }
    // 注意：不设置 state = loading，避免触发 watch 重建导致依赖冲突
    try {
      // 1. 当前设备指纹
      final fp = await DeviceFingerprint.get();

      // 2. 请求后端绑定设备（服务端验签，返回已验证的许可证负载）
      final result = await LicenseClient.instance.activate(
        code: code,
        deviceFp: fp,
        deviceName: Platform.localHostname,
      );

      if (!result.ok) {
        // 设备数已满 → 返回已绑设备列表信息
        final maxDevices = result.license?.maxDevices ?? 1;
        if (result.error == 'DEVICE_LIMIT_REACHED' &&
            result.boundDevices != null) {
          final devices = result.boundDevices!
              .map(
                (d) =>
                    '${d.deviceName ?? '未知设备'} (${_fpShort(d.deviceFp ?? '')})',
              )
              .join('、');
          return (
            false,
            '设备数已达上限（${result.boundDevices!.length}/$maxDevices）\n'
                '已绑设备: $devices\n请先在设置中解绑旧设备',
          );
        }
        return (false, result.message ?? result.error ?? '激活失败');
      }

      // 3. 服务端已验签 → 用返回的负载构造本地许可证
      final licenseInfo = result.license;
      if (licenseInfo == null) {
        return (false, '服务器未返回许可证信息，请稍后重试');
      }
      final payload = LicensePayload(
        type: LicenseType.fromCode(licenseInfo.type),
        maxDevices: licenseInfo.maxDevices,
        expireAt: licenseInfo.expireAt,
      );

      // 4. 保存到本地
      final storage = LicenseStorage.instance;
      final existing = storage.current;
      List<String> boundDevices;

      if (existing != null && existing.code == code) {
        // 同一码重激活：确保当前设备在列表中
        if (!existing.boundDevices.contains(fp)) {
          boundDevices = [...existing.boundDevices, fp];
        } else {
          boundDevices = existing.boundDevices;
        }
      } else {
        // 首次激活或换码
        boundDevices = [fp];
      }

      final next = ActivatedLicense(
        code: code,
        payload: payload,
        boundDevices: boundDevices,
        activatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await storage.save(next);
      // 使用 StateProvider.state = 直接更新，避免 invalidate 导致的依赖冲突
      ref.read(activatedLicenseProvider.notifier).state = next;
      state = AsyncValue.data(next);

      final slotInfo = result.remainingSlots != null
          ? '（剩余 ${result.remainingSlots} 个名额）'
          : '';
      return (
        true,
        '激活成功：${next.payload.type.label} · ${boundDevices.length}/${next.maxDevices} 设备$slotInfo',
      );
    } on LicenseException catch (e) {
      state = AsyncValue.data(LicenseStorage.instance.current);
      return (false, e.message);
    } catch (e) {
      state = AsyncValue.data(LicenseStorage.instance.current);
      return (false, '激活失败：$e');
    }
  }

  /// 解绑设备（远程解绑 + 本地更新）
  Future<(bool success, String message)> unbindDevice(String deviceFp) async {
    final storage = LicenseStorage.instance;
    final current = storage.current;
    if (current == null) {
      return (false, '未找到激活信息');
    }

    try {
      // 请求后端解绑
      final result = await LicenseClient.instance.unbind(
        code: current.code,
        deviceFp: deviceFp,
      );

      if (!result.ok) {
        state = AsyncValue.data(current);
        return (false, result.message ?? result.error ?? '解绑失败');
      }

      // 后端解绑成功 → 更新本地
      final updated = current.boundDevices.where((d) => d != deviceFp).toList();
      final next = current.copyWith(boundDevices: updated);

      // 如果当前设备被解绑了，清除本地激活状态
      final fp = await DeviceFingerprint.get();
      if (deviceFp == fp) {
        await storage.clear();
        ref.read(activatedLicenseProvider.notifier).state = null;
        state = const AsyncValue.data(null);
        return (true, '当前设备已解绑，降级为免费版');
      }

      await storage.save(next);
      ref.read(activatedLicenseProvider.notifier).state = next;
      state = AsyncValue.data(next);
      return (true, '设备已解绑（剩余 ${result.remainingSlots ?? 0} 个名额）');
    } catch (e) {
      state = AsyncValue.data(storage.current);
      return (false, '解绑失败：$e');
    }
  }

  /// 查询后端设备列表（刷新本地绑定状态）
  Future<(bool success, String message)> refreshDeviceList() async {
    final storage = LicenseStorage.instance;
    final current = storage.current;
    if (current == null) {
      return (false, '未找到激活信息');
    }

    try {
      final fp = await DeviceFingerprint.get();
      final status = await LicenseClient.instance.status(
        code: current.code,
        deviceFp: fp,
      );

      if (status == null) {
        return (false, '无法连接服务器');
      }

      // 更新本地绑定设备列表
      final boundFps = status.boundDevices
          .map((d) => d.deviceFp ?? '')
          .where((fp) => fp.isNotEmpty)
          .toList();
      final next = current.copyWith(boundDevices: boundFps);
      await storage.save(next);
      ref.read(activatedLicenseProvider.notifier).state = next;

      return (
        true,
        '已同步：${status.boundDevices.length}/${status.license?.maxDevices ?? 4} 设备',
      );
    } catch (e) {
      return (false, '同步失败：$e');
    }
  }

  String _fpShort(String fp) {
    if (fp.length <= 12) return fp;
    return '${fp.substring(0, 6)}***${fp.substring(fp.length - 6)}';
  }
}

final licenseNotifierProvider =
    StateNotifierProvider<LicenseNotifier, AsyncValue<ActivatedLicense?>>(
      (ref) => LicenseNotifier(ref),
    );
