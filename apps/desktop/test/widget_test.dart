import 'package:downie_test/shared/widgets/window_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('WindowPanel 无标题栏模式', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WindowPanel(
            title: '关于',
            width: 480,
            height: 349,
            showTitleBar: false,
            child: const Text('感谢您的注册！'),
          ),
        ),
      ),
    );

    expect(find.text('感谢您的注册！'), findsOneWidget);
    expect(find.byTooltip('关闭'), findsOneWidget);
  });
}
