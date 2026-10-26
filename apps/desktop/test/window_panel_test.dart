import 'package:downie_test/shared/widgets/window_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('WindowPanel renders title and child', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WindowPanel(
            title: '测试窗口',
            width: 360,
            height: 240,
            child: const Text('内容'),
          ),
        ),
      ),
    );

    expect(find.text('测试窗口'), findsOneWidget);
    expect(find.text('内容'), findsOneWidget);
  });
}
