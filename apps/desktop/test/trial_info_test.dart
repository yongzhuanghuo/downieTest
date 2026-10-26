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
