import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// ===================================================================
/// 许可证后端客户端（Cloudflare Workers API）
///
/// 负责与远程服务器通信：激活/解绑/查询状态/心跳/验证
/// 客户端始终先本地验签，再请求后端绑定设备
/// ===================================================================

/// 后端 API 基础地址
const String _kApiBase = 'https://empty-morning-f9e9.w2865547840.workers.dev';

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

  static const _timeout = Duration(seconds: 15);

  /// 已发现的可用代理（首次成功后缓存，跳过 fallback）
  String? _workingProxy;
  String? _workingProxyType; // 'PROXY' or 'SOCKS'

  /// 尝试多协议代理连接
  Future<http.Response> _post(String path, Map<String, dynamic> body) async {
    final uri = Uri.parse('$_kApiBase$path');
    final headers = {'Content-Type': 'application/json'};
    final jsonBody = jsonEncode(body);

    // 优先级：已缓存的可用代理 → 用户配置的端口 → 常见端口 → 直连
    final attempts = <_ProxyAttempt>[];

    // 缓存的可用代理放最前
    if (_workingProxy != null) {
      attempts.add(_ProxyAttempt(_workingProxy!, _workingProxyType ?? 'PROXY'));
    }

    // 用户/常见端口（每个端口同时尝试 PROXY 和 SOCKS）
    const ports = ['127.0.0.1:7897', '127.0.0.1:7890', '127.0.0.1:1087'];
    for (final port in ports) {
      attempts.add(_ProxyAttempt(port, 'PROXY'));
      attempts.add(_ProxyAttempt(port, 'SOCKS'));
    }

    for (final att in attempts) {
      try {
        final client = _createClient(att.host, att.type);
        final resp = await client
            .post(uri, headers: headers, body: jsonBody)
            .timeout(const Duration(seconds: 6));
        client.close();
        // 成功 → 缓存
        _workingProxy = att.host;
        _workingProxyType = att.type;
        debugPrint('[LicenseClient] ✅ 代理成功: ${att.type} ${att.host}');
        return resp;
      } catch (e) {
        debugPrint('[LicenseClient] ❌ ${att.type} ${att.host} 失败: ${e.runtimeType}');
        continue;
      }
    }

    // 最后兜底：直连
    try {
      final client = _createClient(null, null);
      final resp = await client
          .post(uri, headers: headers, body: jsonBody)
          .timeout(const Duration(seconds: 10));
      client.close();
      _workingProxy = null; // 直连成功说明不需要代理
      debugPrint('[LicenseClient] ✅ 直连成功');
      return resp;
    } catch (e) {
      debugPrint('[LicenseClient] ❌ 直连也失败: ${e.runtimeType}');
    }

    throw Exception('ALL_FAILED');
  }

  /// GET 请求同样逻辑
  Future<http.Response> _get(String path,
      [Map<String, String>? queryParams]) async {
    var uri = Uri.parse('$_kApiBase$path');
    if (queryParams != null) {
      uri = uri.replace(queryParameters: queryParams);
    }

    final attempts = <_ProxyAttempt>[];
    if (_workingProxy != null) {
      attempts.add(_ProxyAttempt(_workingProxy!, _workingProxyType ?? 'PROXY'));
    }
    const ports = ['127.0.0.1:7897', '127.0.0.1:7890', '127.0.0.1:1087'];
    for (final port in ports) {
      attempts.add(_ProxyAttempt(port, 'PROXY'));
      attempts.add(_ProxyAttempt(port, 'SOCKS'));
    }

    for (final att in attempts) {
      try {
        final client = _createClient(att.host, att.type);
        final resp = await client
            .get(uri)
            .timeout(const Duration(seconds: 6));
        client.close();
        _workingProxy = att.host;
        _workingProxyType = att.type;
        debugPrint('[LicenseClient] ✅ 代理成功: ${att.type} ${att.host}');
        return resp;
      } catch (e) {
        debugPrint('[LicenseClient] ❌ ${att.type} ${att.host} 失败: ${e.runtimeType}');
        continue;
      }
    }

    try {
      final client = _createClient(null, null);
      final resp = await client.get(uri).timeout(const Duration(seconds: 10));
      client.close();
      _workingProxy = null;
      debugPrint('[LicenseClient] ✅ 直连成功');
      return resp;
    } catch (e) {
      debugPrint('[LicenseClient] ❌ 直连也失败: ${e.runtimeType}');
    }

    throw Exception('ALL_FAILED');
  }

  /// 创建 HTTP Client
  http.Client _createClient(String? proxyHost, String? proxyType) {
    final httpClient = HttpClient();
    httpClient.badCertificateCallback = (cert, host, port) => true;

    if (proxyHost != null && proxyType != null) {
      httpClient.findProxy = (uri) => '$proxyType $proxyHost';
    }

    return IOClient(httpClient);
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

class _ProxyAttempt {
  final String host;
  final String type; // 'PROXY' or 'SOCKS'
  const _ProxyAttempt(this.host, this.type);
}
