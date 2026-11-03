import 'package:downie_test/core/license/license_client.dart';
import 'package:downie_test/features/license/license_provider.dart';
import 'package:downie_test/features/license/trial_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTrialNotifier extends TrialNotifier {
  _FakeTrialNotifier(TrialInfo? info) {
    state = AsyncValue.data(info);
  }

  @override
  Future<void> refresh() async {}

  @override
  Future<void> ensureStarted() async {}
}

Widget _host(TrialInfo? info, {bool activation = false}) {
  return ProviderScope(
    overrides: [
      trialProvider.overrideWith((ref) => _FakeTrialNotifier(info)),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 758,
          height: 466,
          child: TrialWindow(initialActivation: activation),
        ),
      ),
    ),
  );
}

TrialInfo _active() {
  return TrialInfo(
    status: 'active',
    trialEnd: DateTime.now()
        .add(const Duration(days: 12))
        .millisecondsSinceEpoch,
    daysRemaining: 12,
    canDownload: true,
  );
}

void main() {
  testWidgets('trial window shows countdown and activation entry', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_active()));
    await tester.pump();

    expect(find.textContaining('感谢您试用'), findsOneWidget);
    expect(find.text('剩余 12 天'), findsOneWidget);
    expect(find.text('继续试用'), findsOneWidget);
    expect(find.text('输入许可证代码'), findsOneWidget);
  });

  testWidgets('activation form makes the email purpose clear', (tester) async {
    await tester.pumpWidget(_host(_active(), activation: true));
    await tester.pump();

    expect(find.text('电子邮箱'), findsOneWidget);
    expect(find.text('许可证代码'), findsOneWidget);
    expect(find.textContaining('您自己的邮箱'), findsWidgets);
    expect(find.text('激活许可证'), findsOneWidget);
  });

  testWidgets('expired trial hides continue trial', (tester) async {
    await tester.pumpWidget(
      _host(
        TrialInfo(
          status: 'expired',
          trialEnd: DateTime.now()
              .subtract(const Duration(days: 1))
              .millisecondsSinceEpoch,
          daysRemaining: 0,
          canDownload: false,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('试用结束'), findsOneWidget);
    expect(find.text('继续试用'), findsNothing);
    expect(find.text('输入许可证代码'), findsOneWidget);
  });
}
