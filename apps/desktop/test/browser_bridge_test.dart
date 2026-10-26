import 'package:downie_test/core/server/browser_bridge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  group('BrowserBridge', () {
    late BrowserBridge bridge;
    late List<String> received;

    setUp(() async {
      bridge = BrowserBridge.instance;
      received = [];
      final ok = await bridge.start(
        token: 'test-token',
        port: 0,
        onUrl: (url) async {
          received.add(url);
          return true;
        },
      );
      expect(ok, isTrue);
    });

    tearDown(() async {
      await bridge.stop();
    });

    test('rejects requests without the token', () async {
      final response = await http.get(
        Uri.parse(
          'http://127.0.0.1:${bridge.port}/add?url=https%3A%2F%2Fexample.com%2Fv',
        ),
      );
      expect(response.statusCode, 403);
      expect(received, isEmpty);
    });

    test('accepts a valid URL and calls the handler', () async {
      final response = await http.get(
        Uri.parse(
          'http://127.0.0.1:${bridge.port}/add'
          '?token=test-token&url=https%3A%2F%2Fexample.com%2Fv',
        ),
      );
      expect(response.statusCode, 200);
      expect(received, ['https://example.com/v']);
    });

    test('rejects non-http URLs', () async {
      final response = await http.get(
        Uri.parse(
          'http://127.0.0.1:${bridge.port}/add'
          '?token=test-token&url=file%3A%2F%2F%2Fetc%2Fpasswd',
        ),
      );
      expect(response.statusCode, 400);
      expect(received, isEmpty);
    });

    test('ping does not require a token', () async {
      final response = await http.get(
        Uri.parse('http://127.0.0.1:${bridge.port}/ping'),
      );
      expect(response.statusCode, 200);
      expect(response.body, 'Downie6');
    });
  });

  test('bookmarklet contains the port, token, and current page', () {
    final script = BrowserBridge.bookmarklet(token: 'abc', port: 9999);
    expect(script, startsWith('javascript:'));
    expect(script, contains('127.0.0.1:9999/add'));
    expect(script, contains('token=abc'));
    expect(script, contains('encodeURIComponent(location.href)'));
  });
}
