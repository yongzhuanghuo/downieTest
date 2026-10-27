import 'package:downie_test/core/platform/automation_queue.dart';
import 'package:downie_test/core/platform/automation_request.dart';
import 'package:downie_test/data/models/download_task.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts direct HTTP(S) links', () {
    final http = parseAutomationRequest('https://example.com/video/1');
    expect(http, isNotNull);
    expect(http!.url, 'https://example.com/video/1');
    expect(http.openInUge, isFalse);

    expect(parseAutomationRequest('ftp://example.com/v'), isNull);
    expect(parseAutomationRequest(''), isNull);
  });

  test('parses downie6 automation options', () {
    final req = parseAutomationRequest(
      'downie6://XUOpenURL?url=https%3A%2F%2Fexample.com%2Fv%3Fx%3D1%26y%3D2'
      '&postprocessing=audio&destination=%2Ftmp%2Fvideos&title=Demo',
    );
    expect(req, isNotNull);
    expect(req!.url, 'https://example.com/v?x=1&y=2');
    expect(req.postprocessing, PostprocessingMode.audio);
    expect(req.destination, '/tmp/videos');
    expect(req.title, 'Demo');
  });

  test('accepts Downie-style downie:// scheme when explicitly delivered', () {
    final req = parseAutomationRequest(
      'downie://XUOpenURL?url=https%3A%2F%2Fexample.com%2Fv',
    );
    expect(req, isNotNull);
    expect(req!.url, 'https://example.com/v');
  });

  test('parses open_in_uge and mp4', () {
    final req = parseAutomationRequest(
      'downie6://XUOpenURL?url=https://example.com/v&postprocessing=mp4&action=open_in_uge',
    );
    expect(req!.postprocessing, PostprocessingMode.mp4);
    expect(req.openInUge, isTrue);
  });

  test('command-line queue keeps only valid links and drains', () {
    AutomationQueue.seed([
      '--some-flag',
      'https://example.com/a',
      'downie6://XUOpenURL?url=https%3A%2F%2Fexample.com%2Fb',
    ]);
    final pending = AutomationQueue.drain();
    expect(pending, hasLength(2));
    expect(pending.first.url, 'https://example.com/a');
    expect(pending.last.url, 'https://example.com/b');
    expect(AutomationQueue.drain(), isEmpty);
  });

  test('rejects malformed or non-http payloads', () {
    expect(parseAutomationRequest('downie6://XUOpenURL?title=NoUrl'), isNull);
    expect(
      parseAutomationRequest('downie6://XUOpenURL?url=file:///etc/passwd'),
      isNull,
    );
    expect(parseAutomationRequest('downie6://Unknown?url=https://a.com'), isNull);
  });
}
