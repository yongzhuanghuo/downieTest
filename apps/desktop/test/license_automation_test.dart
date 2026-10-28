import 'package:downie_test/core/platform/automation_queue.dart';
import 'package:downie_test/core/platform/license_automation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses Downie license activate URL', () {
    final request = parseLicenseAutomation(
      'downie-license://activate?email=me%40example.com'
      '&license=ABCDE-FGHJK-MNPQR-STUVW-XYZ23&hide=true',
    );
    expect(request, isNotNull);
    expect(request!.activate, isTrue);
    expect(request.email, 'me@example.com');
    expect(request.code, 'ABCDE-FGHJK-MNPQR-STUVW-XYZ23');
    expect(request.hide, isTrue);
  });

  test('parses downie6-license deactivate alias', () {
    final request = parseLicenseAutomation(
      'downie6-license://deactivate?email=me@example.com&license=ABCDE',
    );
    expect(request, isNotNull);
    expect(request!.activate, isFalse);
    expect(request.hide, isFalse);
  });

  test('command-line queue separates license and download links', () {
    AutomationQueue.seed([
      'downie6-license://activate?email=a%40b.com&license=ABCDE',
      'https://example.com/video',
    ]);
    final licenses = AutomationQueue.drainLicenses();
    final downloads = AutomationQueue.drain();
    expect(licenses, hasLength(1));
    expect(licenses.single.code, 'ABCDE');
    expect(downloads, hasLength(1));
    expect(downloads.single.url, 'https://example.com/video');
  });

  test('rejects missing fields and unrelated URLs', () {
    expect(
      parseLicenseAutomation('downie-license://activate?email=a@b.com'),
      isNull,
    );
    expect(
      parseLicenseAutomation('downie-license://deactivate?license=ABCDE'),
      isNull,
    );
    expect(
      parseLicenseAutomation('downie6://XUOpenURL?url=https%3A%2F%2Fa.com'),
      isNull,
    );
    expect(parseLicenseAutomation('https://example.com'), isNull);
  });
}
