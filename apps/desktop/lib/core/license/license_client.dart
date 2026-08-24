import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// ===================================================================
/// 许可证后端客户端（自建服务器 API）
///
/// 负责与远程服务器通信：激活/解绑/查询状态/心跳/验证
/// 直连后端，不做本地验签（授权由服务端校验）
/// ===================================================================

/// 后端 API 基础地址
///
/// 自建服务器：默认 http://127.0.0.1:3000（本机调试）。
/// 发布时改成你的服务器地址，或构建时覆盖：
///   flutter build macos --dart-define=API_BASE=http://你的服务器IP:3000
/// 后续上 HTTPS 后改成 https://你的域名 即可。
const String _kApiBase = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'http://127.0.0.1:3000',
);

/// 激活结果
class ActivateResult {
  final bool ok;
  final String? error;
  final String? message;
  final LicenseInfo? license;
  final DeviceInfo? device;
  final int? boundCount;
  final int? remainingSlots;
  final List<DeviceInfo>? boundDevices;

  ActivateResult({
    required this.ok,
    this.error,
    this.message,
    this.license,
    this.device,
    this.boundCount,
    this.remainingSlots,
    this.boundDevices,
  });

  factory ActivateResult.fromJson(Map<String, dynamic> j) {
    return ActivateResult(
      ok: j['ok'] as bool,
      error: j['error'] as String?,
      message: j['message'] as String?,
      license: j['license'] != null
          ? LicenseInfo.fromJson(j['license'] as Map<String, dynamic>)
          : null,
      device: j['device'] != null
          ? DeviceInfo.fromJson(j['device'] as Map<String, dynamic>)
          : null,
      boundCount: j['bound_count'] as int?,
      remainingSlots: j['remaining_slots'] as int?,
      boundDevices: (j['bound_devices'] as List?)
          ?.map((d) => DeviceInfo.fromJson(d as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// 解绑结果
class UnbindResult {
  final bool ok;
  final String? error;
  final String? message;
  final int? remainingSlots;

  UnbindResult({
    required this.ok,
    this.error,
    this.message,
    this.remainingSlots,
  });

  factory UnbindResult.fromJson(Map<String, dynamic> j) {
    return UnbindResult(
      ok: j['ok'] as bool,
      error: j['error'] as String?,
      message: j['message'] as String?,
      remainingSlots: j['remaining_slots'] as int?,
    );
  }
}

/// 许可证信息
class LicenseInfo {
  final String type;
  final int maxDevices;
  final int? expireAt;

  LicenseInfo({
    required this.type,
    required this.maxDevices,
    this.expireAt,
  });

  factory LicenseInfo.fromJson(Map<String, dynamic> j) {
    return LicenseInfo(
      type: j['type'] as String,
      maxDevices: j['max_devices'] as int,
      expireAt: j['expire_at'] as int?,
    );
  }
}

/// 设备信息
class DeviceInfo {
  final String? id;
  final String? deviceFp;
  final String? deviceName;
  final String? boundAt;
  final String? lastSeen;
  final bool? isCurrent;

  DeviceInfo({
    this.id,
    this.deviceFp,
    this.deviceName,
    this.boundAt,
    this.lastSeen,
    this.isCurrent,
  });

  factory DeviceInfo.fromJson(Map<String, dynamic> j) {
    return DeviceInfo(
      id: j['id'] as String?,
      deviceFp: j['device_fp'] as String?,
      deviceName: j['device_name'] as String?,
      boundAt: j['bound_at'] as String?,
      lastSeen: j['last_seen'] as String?,
      isCurrent: j['is_current'] as bool?,
    );
  }
}

/// 设备状态查询结果
class StatusResult {
  final bool ok;
  final LicenseInfo? license;
  final List<DeviceInfo> boundDevices;
  final int remainingSlots;

  StatusResult({
    required this.ok,
    this.license,
    required this.boundDevices,
    required this.remainingSlots,
  });

  factory StatusResult.fromJson(Map<String, dynamic> j) {
    return StatusResult(
      ok: j['ok'] as bool,
      license: j['license'] != null
          ? LicenseInfo.fromJson(j['license'] as Map<String, dynamic>)
          : null,
      boundDevices: (j['bound_devices'] as List? ?? [])
          .map((d) => DeviceInfo.fromJson(d as Map<String, dynamic>))
          .toList(),
      remainingSlots: j['remaining_slots'] as int? ?? 0,
    );
  }
}

/// ===================================================================
/// LicenseClient - HTTP 通信层
/// ===================================================================
class LicenseClient {
  LicenseClient._();
  static final instance = LicenseClient._();

  /// POST 请求（直连后端）
  Future<http.Response> _post(String path, Map<String, dynamic> body) async {
    final uri = Uri.parse('$_kApiBase$path');
    final headers = {'Content-Type': 'application/json'};
    return http
        .post(uri, headers: headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));
  }

  /// GET 请求（直连后端）
  Future<http.Response> _get(String path,
      [Map<String, String>? queryParams]) async {
    var uri = Uri.parse('$_kApiBase$path');
    if (queryParams != null) {
      uri = uri.replace(queryParameters: queryParams);
    }
    return http.get(uri).timeout(const Duration(seconds: 15));
  }

  /// 激活（绑定设备）
  Future<ActivateResult> activate({
    required String code,
    required String deviceFp,
    String? deviceName,
  }) async {
    try {
      final resp = await _post('/api/license/activate', {
        'code': code,
        'device_fp': deviceFp,
        'device_name': deviceName ?? Platform.localHostname,
      });
      final bodyStr = resp.body;
      final preview = bodyStr.length > 200 ? bodyStr.substring(0, 200) : bodyStr;
      debugPrint('[LicenseClient] 激活响应: status=${resp.statusCode}, body=$preview');
      final j = jsonDecode(resp.body) as Map<String, dynamic>;
      final result = ActivateResult.fromJson(j);
      debugPrint('[LicenseClient] 激活结果: ok=${result.ok}, error=${result.error}');
      return result;
    } catch (e) {
      debugPrint('[LicenseClient] 激活异常: ${e.runtimeType}: $e');
      return ActivateResult(
        ok: false,
        error: 'NETWORK_ERROR',
        message: '无法连接服务器，请检查网络或代理设置后重试',
      );
    }
  }

  /// 解绑设备
  Future<UnbindResult> unbind({
    required String code,
    required String deviceFp,
  }) async {
    try {
      final resp = await _post('/api/license/unbind', {
        'code': code,
        'device_fp': deviceFp,
      });
      final j = jsonDecode(resp.body) as Map<String, dynamic>;
      return UnbindResult.fromJson(j);
    } catch (e) {
      return UnbindResult(
        ok: false,
        error: 'NETWORK_ERROR',
        message: '无法连接服务器，请检查网络或代理设置后重试',
      );
    }
  }

  /// 查询状态（设备列表 + 剩余名额 + 解绑次数）
  Future<StatusResult?> status({
    required String code,
    String? deviceFp,
  }) async {
    try {
      final params = <String, String>{'code': code};
      if (deviceFp != null) params['device_fp'] = deviceFp;
      final resp = await _get('/api/license/status', params);

      if (resp.statusCode == 200) {
        final j = jsonDecode(resp.body) as Map<String, dynamic>;
        return StatusResult.fromJson(j);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// 心跳保活（每 24 小时一次）
  Future<bool> heartbeat({
    required String code,
    required String deviceFp,
    String? deviceName,
  }) async {
    try {
      final resp = await _post('/api/license/heartbeat', {
        'code': code,
        'device_fp': deviceFp,
        'device_name': deviceName ?? Platform.localHostname,
      });
      final j = jsonDecode(resp.body) as Map<String, dynamic>;
      return j['ok'] as bool;
    } catch (e) {
      return false;
    }
  }
}
