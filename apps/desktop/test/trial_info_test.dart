import 'package:downie_test/core/license/license_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('active trial', () {
    final info = TrialInfo.fromJson(
      {
        'status': 'active',
        'trial_end': 123456,
        'days_remaining': 14,
      },
      true,
    );
    expect(info.isActive, isTrue);
    expect(info.daysRemaining, 14);
  });

  test('activation errors unwrap FastAPI detail payloads', () {
    final result = ActivateResult.fromJson({
      'detail': {
        'ok': false,
        'error': 'INVALID_CODE',
        'message': '激活码无效',
      },
    });
    expect(result.ok, isFalse);
    expect(result.error, 'INVALID_CODE');
    expect(result.message, '激活码无效');
  });

  test('device-limit activation errors expose bound devices', () {
    final result = ActivateResult.fromJson({
      'detail': {
        'ok': false,
        'error': 'DEVICE_LIMIT_REACHED',
        'message': '已绑定 1/1 台设备',
        'bound_devices': [
          {'device_fp': 'abc', 'device_name': 'Mac'},
        ],
      },
    });
    expect(result.ok, isFalse);
    expect(result.error, 'DEVICE_LIMIT_REACHED');
    expect(result.boundDevices, hasLength(1));
    expect(result.boundDevices!.single.deviceName, 'Mac');
  });

  test('unbind errors unwrap FastAPI detail payloads', () {
    final result = UnbindResult.fromJson({
      'detail': {'ok': false, 'error': 'NOT_FOUND', 'message': '设备不存在'},
    });
    expect(result.ok, isFalse);
    expect(result.error, 'NOT_FOUND');
    expect(result.message, '设备不存在');
  });

  test('expired trial is not active even if server says truthy', () {
    final info = TrialInfo.fromJson(
      {
        'status': 'expired',
        'trial_end': 1,
        'days_remaining': 0,
      },
      false,
    );
    expect(info.isActive, isFalse);
  });
}
