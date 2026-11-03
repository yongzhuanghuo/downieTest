import 'package:downie_test/core/platform/system_proxy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parse scutil proxy prefers HTTPS', () {
    const output = '''
<dictionary> {
  HTTPEnable : 1
  HTTPPort : 7897
  HTTPProxy : 127.0.0.1
  HTTPSEnable : 1
  HTTPSPort : 7897
  HTTPSProxy : 127.0.0.1
  SOCKSEnable : 1
  SOCKSPort : 7897
  SOCKSProxy : 127.0.0.1
}
''';
    expect(SystemProxy.parseScutilProxy(output), 'http://127.0.0.1:7897');
  });

  test('parse scutil falls back to HTTP when HTTPS is disabled', () {
    const output = '''
<dictionary> {
  HTTPEnable : 1
  HTTPPort : 8080
  HTTPProxy : 10.0.0.2
}
''';
    expect(SystemProxy.parseScutilProxy(output), 'http://10.0.0.2:8080');
  });

  test('parse scutil returns null when no proxy is enabled', () {
    const output = '''
<dictionary> {
  HTTPEnable : 0
  HTTPSEnable : 0
  SOCKSEnable : 0
}
''';
    expect(SystemProxy.parseScutilProxy(output), isNull);
  });

  test('parse Windows proxy uses the HTTPS entry', () {
    const enable = '''
HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings
    ProxyEnable    REG_DWORD    0x1
''';
    const server = '''
HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings
    ProxyServer    REG_SZ    http=127.0.0.1:7890;https=127.0.0.1:7891
''';
    expect(
      SystemProxy.parseWindowsProxy(enable, server),
      'http://127.0.0.1:7891',
    );
  });

  test('normalize adds a scheme', () {
    expect(
      SystemProxy.normalize('127.0.0.1:7897'),
      'http://127.0.0.1:7897',
    );
    expect(
      SystemProxy.normalize('socks5://127.0.0.1:7897'),
      'socks5://127.0.0.1:7897',
    );
  });
}
