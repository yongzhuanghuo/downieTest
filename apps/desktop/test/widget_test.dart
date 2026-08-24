import 'package:flutter_test/flutter_test.dart';

import 'package:downie_test/app.dart';

void main() {
  testWidgets('App 启动测试', (WidgetTester tester) async {
    await tester.pumpWidget(const DownloApp());

    expect(find.text('添加链接'), findsOneWidget);
  });
}
