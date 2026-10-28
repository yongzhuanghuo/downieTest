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
///   - 'license': ActivatedLicense 的 Map
/// ===================================================================
class LicenseStorage {
  LicenseStorage._();
  static final instance = LicenseStorage._();

  static const _boxName = 'downlo_license';
  static const _keyLicense = 'license';
  static const _keyTrial = 'trial';
  static const _keyHeartbeat = 'lastHeartbeat';

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

  /// 本地缓存的试用状态；断网时按 trial_end 判断，避免无限期放行。
  TrialInfo? get cachedTrial {
    final raw = _box?.get(_keyTrial);
    if (raw is! Map) return null;
    return trialInfoFromCache(Map<String, dynamic>.from(raw));
  }

  Future<void> saveTrial(TrialInfo info) async {
    await _box?.put(_keyTrial, {
      'status': info.status,
      'trial_end': info.trialEnd,
      'days_remaining': info.daysRemaining,
      'can_download': info.canDownload,
      'checked_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  int? get lastHeartbeatAt =>
      (_box?.get(_keyHeartbeat) as num?)?.toInt();

  Future<void> saveHeartbeat(int value) async {
    await _box?.put(_keyHeartbeat, value);
  }
}

/// 从本地缓存解析试用状态（纯函数，便于单测）。
/// 缺少 trial_end 或已到期时一律按过期处理，防止篡改缓存后无限试用。
TrialInfo trialInfoFromCache(Map<String, dynamic> raw, {DateTime? now}) {
  final end = (raw['trial_end'] as num?)?.toInt() ?? 0;
  final current = (now ?? DateTime.now()).millisecondsSinceEpoch;
  final expired = end <= 0 || current >= end;
  return TrialInfo(
    status: expired ? 'expired' : ((raw['status'] as String?) ?? 'expired'),
    trialEnd: end,
    daysRemaining:
        expired ? 0 : ((raw['days_remaining'] as num?)?.toInt() ?? 0),
    canDownload: !expired && raw['can_download'] == true,
  );
}

/// ===================================================================
/// License Provider：UI 可直接 watch 监听激活状态变化
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


/// Notifier：激活码激活（调用 verify + 绑定设备指纹 + 保存）
class LicenseNotifier extends StateNotifier<AsyncValue<ActivatedLicense?>> {
  final Ref ref;
  LicenseNotifier(this.ref) : super(const AsyncValue.data(null));

  /// 激活激活码
  /// 流程: 本地验签 → 请求后端绑定设备 → 保存到本地
  Future<(bool success, String message)> activate(
    String rawCode, {
    String? email,
  }) async {
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
        email: email,
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
        email: (email?.trim().isNotEmpty ?? false)
            ? email!.trim()
            : (existing?.email ?? ''),
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

  /// 反激活当前设备
  Future<(bool success, String message)> deactivateCurrentDevice() async {
    final fp = await DeviceFingerprint.get();
    final (ok, message) = await unbindDevice(fp);
    if (ok) return (true, '当前设备已反激活');
    return (false, message);
  }

  /// 命令行/URL scheme 反激活：Downie 要求授权码和邮箱匹配当前激活信息。
  Future<(bool success, String message)> deactivateWithCode(
    String code, {
    String email = '',
  }) async {
    final current = LicenseStorage.instance.current;
    if (current == null) return (false, '当前设备未激活');
    if (_normalizeCode(current.code) != _normalizeCode(code)) {
      return (false, '授权码与当前激活信息不匹配');
    }
    if (current.email.isNotEmpty &&
        email.isNotEmpty &&
        current.email.toLowerCase() != email.trim().toLowerCase()) {
      return (false, '邮箱与当前激活信息不匹配');
    }
    return deactivateCurrentDevice();
  }

  /// 启动校验：撤销/远程解绑会清除本地 PRO；网络失败保持离线授权。
  Future<void> verifyCurrentDevice() async {
    final storage = LicenseStorage.instance;
    final current = storage.current;
    if (current == null) return;
    final fp = await DeviceFingerprint.get();
    final result = await LicenseClient.instance.verify(
      code: current.code,
      deviceFp: fp,
    );
    if (result == null) return;
    if (!result.valid) {
      await storage.clear();
      ref.read(activatedLicenseProvider.notifier).state = null;
      state = const AsyncValue.data(null);
      debugPrint('[License] 启动校验失败: ${result.reason ?? 'invalid'}');
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = storage.lastHeartbeatAt ?? 0;
    if (now - last > const Duration(hours: 24).inMilliseconds) {
      final ok = await LicenseClient.instance.heartbeat(
        code: current.code,
        deviceFp: fp,
      );
      if (ok) await storage.saveHeartbeat(now);
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

  /// 拉取设备列表（用于设备管理窗口）
  Future<List<DeviceInfo>?> listDevices() async {
    final current = LicenseStorage.instance.current;
    if (current == null) return null;
    try {
      final fp = await DeviceFingerprint.get();
      final status = await LicenseClient.instance.status(
        code: current.code,
        deviceFp: fp,
      );
      if (status == null || !status.ok) return null;

      final boundFps = status.boundDevices
          .map((d) => d.deviceFp ?? '')
          .where((fp) => fp.isNotEmpty)
          .toList();
      final next = current.copyWith(boundDevices: boundFps);
      await LicenseStorage.instance.save(next);
      ref.read(activatedLicenseProvider.notifier).state = next;
      return status.boundDevices;
    } catch (_) {
      return null;
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

      if (status == null || !status.ok) {
        return (false, '无法连接服务器或授权状态异常');
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

/// ===================================================================
/// 14 天试用（服务端按设备记录，本地只缓存展示状态）
/// ===================================================================
class TrialNotifier extends StateNotifier<AsyncValue<TrialInfo?>> {
  TrialNotifier() : super(const AsyncValue.loading());

  bool _started = false;

  Future<void> ensureStarted() async {
    if (_started) return;
    _started = true;
    // 调用方在 initState 里触发，先让出当前帧，避免构建期修改 provider。
    await Future<void>.delayed(Duration.zero);
    final cached = LicenseStorage.instance.cachedTrial;
    if (cached != null) state = AsyncValue.data(cached);
    try {
      final deviceFp = await DeviceFingerprint.get();
      final info = await LicenseClient.instance.startTrial(
        deviceFp: deviceFp,
        platform: Platform.isMacOS ? 'macos' : 'windows',
      );
      if (info != null) {
        await LicenseStorage.instance.saveTrial(info);
        state = AsyncValue.data(info);
      } else if (cached == null) {
        state = const AsyncValue.data(null);
        _started = false;
      }
    } catch (e, st) {
      // 有本地缓存时继续按缓存判断（到期会被 canDownload 拦截）。
      if (cached == null) state = AsyncValue.error(e, st);
      _started = false;
    }
  }
}

final trialProvider =
    StateNotifierProvider<TrialNotifier, AsyncValue<TrialInfo?>>(
  (ref) => TrialNotifier(),
);

/// 是否允许发起新下载：已授权 PRO，或 14 天试用仍有效。
/// 试用状态加载中/网络失败时先放行，避免误伤已有用户。
final canDownloadProvider = Provider<bool>((ref) {
  if (ref.watch(isProProvider)) return true;
  final trial = ref.watch(trialProvider);
  return trial.maybeWhen(
    data: (info) => info?.isActive ?? true,
    orElse: () => true,
  );
});

final licenseNotifierProvider =
    StateNotifierProvider<LicenseNotifier, AsyncValue<ActivatedLicense?>>(
      (ref) => LicenseNotifier(ref),
    );

String _normalizeCode(String value) =>
    value.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
