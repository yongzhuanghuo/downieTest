import 'package:downie_test/core/sites/plugin_registry.dart';
import 'package:downie_test/core/sites/plugins/generic_web_plugin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('detect media kinds', () {
    expect(detectMediaKind('https://x/a.m3u8?token=1'), 'hls');
    expect(detectMediaKind('https://x/a.mpd'), 'dash');
    expect(detectMediaKind('https://x/a.mp4?x=1'), 'direct');
    expect(detectMediaKind('https://x/a.flv'), 'direct');
    expect(detectMediaKind('https://x/a.ts'), isNull);
    expect(detectMediaKind('https://x/a.m4s'), isNull);
    expect(detectMediaKind('https://x/a.jpg'), isNull);
  });

  test('generic plugin is registered but does not match URLs', () {
    final plugin = PluginRegistry.instance.byId('GenericWeb');
    expect(plugin, isNotNull);
    expect(
      plugin!.matches(Uri.parse('https://example.com/a.mp4'), ''),
      isFalse,
    );
    expect(
      PluginRegistry.instance.find('https://example.com/a.mp4'),
      isNull,
    );
  });
}
