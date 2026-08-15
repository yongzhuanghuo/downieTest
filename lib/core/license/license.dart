import 'dart:io';
import 'package:meta/meta.dart';

/// ===================================================================
/// 许可证类型（可扩展更多等级，如月费年卡）
/// ===================================================================
enum LicenseType {
  /// 免费版
  free,

  /// 永久版（30元买断）
  perpetual;

  factory LicenseType.fromCode(String code) {
    switch (code.toUpperCase()) {
      case 'P':
      case 'PERPETUAL':
        return LicenseType.perpetual;
      default:
        return LicenseType.free;
    }
  }

  String toCode() => this == LicenseType.perpetual ? 'P' : 'F';

  /// 中文描述
  String get label => this == LicenseType.perpetual ? 'PRO 永久版' : '免费版';
}

/// ===================================================================
/// 许可证负载（由服务端验签后下发，客户端不再本地解码/验签）
/// ===================================================================
@immutable
class LicensePayload {
  /// 许可证类型
  final LicenseType type;

  /// 最大绑定设备数（免费=1，PRO=4）
  final int maxDevices;

  /// 过期时间毫秒，null=永不过期（买断版）
  final int? expireAt;

  const LicensePayload({
    required this.type,
    required this.maxDevices,
    this.expireAt,
  });

  /// 是否过期（永不过期=永远 false）
  bool get isExpired {
    if (expireAt == null) return false;
    return DateTime.now().millisecondsSinceEpoch > expireAt!;
  }
}

/// ===================================================================
/// 已激活的许可证（包含负载 + 绑定设备列表 + 激活时间）
/// 持久化到 Hive
/// ===================================================================
@immutable
class ActivatedLicense {
  final String code; // 激活码原文（用户可查）
  final LicensePayload payload;
  final List<String> boundDevices; // 设备指纹列表
  final int activatedAt; // 激活时间

  const ActivatedLicense({
    required this.code,
    required this.payload,
    required this.boundDevices,
    required this.activatedAt,
  });

  LicenseType get type => payload.type;
  int get maxDevices => payload.maxDevices;
  bool get isPro => type == LicenseType.perpetual && !payload.isExpired;

  /// 剩余可绑名额
  int get remainingSlots => (maxDevices - boundDevices.length).clamp(0, 999);

  /// 设备是否已绑定
  bool isDeviceBound(String fp) => boundDevices.contains(fp);

  /// 是否可以再绑一台
  bool get canBindMore => boundDevices.length < maxDevices;

  ActivatedLicense copyWith({
    List<String>? boundDevices,
  }) {
    return ActivatedLicense(
      code: code,
      payload: payload,
      boundDevices: boundDevices ?? this.boundDevices,
      activatedAt: activatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'code': code,
      'type': payload.type.toCode(),
      'maxDevices': payload.maxDevices,
      'expireAt': payload.expireAt,
      'boundDevices': boundDevices,
      'activatedAt': activatedAt,
    };
  }

  factory ActivatedLicense.fromMap(Map<String, dynamic> m) {
    return ActivatedLicense(
      code: m['code'] as String,
      payload: LicensePayload(
        type: LicenseType.fromCode((m['type'] as String?) ?? 'F'),
        maxDevices: (m['maxDevices'] as num?)?.toInt() ?? 1,
        expireAt: m['expireAt'] as int?,
      ),
      boundDevices: List<String>.from(m['boundDevices'] as List? ?? const []),
      activatedAt: (m['activatedAt'] as num?)?.toInt() ?? 0,
    );
  }
}

/// ===================================================================
/// 设备指纹：基于平台稳定硬件 ID
/// ===================================================================
class DeviceFingerprint {
  DeviceFingerprint._();

  /// 获取当前设备指纹（失败=回退到MAC地址+主机名组合）
  static Future<String> get() async {
    try {
      if (Platform.isMacOS) {
        return await _ioreg();
      } else if (Platform.isWindows) {
        return await _windowsMachineGuid();
      } else {
        return await _hostnameFallback();
      }
    } catch (e) {
      stderr.writeln('[DeviceFingerprint] 失败: $e，回退到 hostname');
      return _hostnameFallback();
    }
  }

  /// macOS: IOPlatformUUID（每台 Mac 唯一且长期稳定）
  static Future<String> _ioreg() async {
    final r = await Process.run('ioreg', ['-rd1', '-c', 'IOPlatformExpertDevice']);
    final out = r.stdout.toString();
    final match = RegExp(r'"IOPlatformUUID" = "([^"]+)"').firstMatch(out);
    if (match != null) return match.group(1)!.replaceAll('-', '').toLowerCase();
    throw StateError('无法解析 ioreg 结果');
  }

  /// Windows: HKLM\SOFTWARE\Microsoft\Cryptography\MachineGuid
  static Future<String> _windowsMachineGuid() async {
    final r = await Process.run('reg', [
      'query',
      r'HKLM\SOFTWARE\Microsoft\Cryptography',
      '/v',
      'MachineGuid',
    ]);
    final out = r.stdout.toString();
    final match = RegExp(r'MachineGuid\s+REG_SZ\s+([^\r\n]+)').firstMatch(out);
    if (match != null) return match.group(1)!.replaceAll('-', '').toLowerCase();
    throw StateError('无法读取 MachineGuid');
  }

  /// 通用 fallback: hostname + 本地化主机 ID
  static Future<String> _hostnameFallback() async {
    final h = Platform.localHostname;
    final sep = Platform.pathSeparator;
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        sep;
    return ('$h-$home').hashCode.toRadixString(16).padLeft(16, '0');
  }
}

/// ===================================================================
/// 许可证异常
/// ===================================================================
class LicenseException implements Exception {
  final String message;
  LicenseException(this.message);
  @override
  String toString() => 'LicenseException: $message';
}
