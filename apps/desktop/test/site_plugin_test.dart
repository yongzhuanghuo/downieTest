import 'package:downie_test/core/sites/plugin_registry.dart';
import 'package:downie_test/core/sites/plugins/bilibili_plugin.dart';
import 'package:downie_test/core/sites/plugins/douyin_plugin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DouyinPlugin', () {
    test('matches douyin hosts', () {
      final plugin = DouyinPlugin();
      expect(
        plugin.matches(Uri.parse('https://www.douyin.com/video/123'), ''),
        isTrue,
      );
      expect(
        plugin.matches(Uri.parse('https://v.douyin.com/abc'), ''),
        isTrue,
      );
      expect(
        plugin.matches(Uri.parse('https://www.iesdouyin.com/share/video/1'), ''),
        isTrue,
      );
      expect(
        plugin.matches(Uri.parse('https://www.youtube.com/watch?v=abc'), ''),
        isFalse,
      );
    });
  });

  group('BilibiliPlugin', () {
    test('matches video and short links, not bangumi', () {
      final plugin = BilibiliPlugin();
      expect(
        plugin.matches(
          Uri.parse('https://www.bilibili.com/video/BV1xx411c7mD'),
          '',
        ),
        isTrue,
      );
      expect(plugin.matches(Uri.parse('https://b23.tv/abc'), ''), isTrue);
      expect(
        plugin.matches(
          Uri.parse('https://www.bilibili.com/bangumi/play/ep123'),
          '',
        ),
        isFalse,
      );
      expect(
        plugin.matches(Uri.parse('https://www.youtube.com/watch?v=abc'), ''),
        isFalse,
      );
    });
  });

  group('PluginRegistry', () {
    test('finds douyin plugin', () {
      final plugin = PluginRegistry.instance.find('https://v.douyin.com/abc');
      expect(plugin, isNotNull);
      expect(plugin!.id, 'Douyin');
    });

    test('finds bilibili plugin', () {
      final plugin = PluginRegistry.instance
          .find('https://www.bilibili.com/video/BV1xx411c7mD');
      expect(plugin, isNotNull);
      expect(plugin!.id, 'Bilibili');
    });

    test('finds plugin by id', () {
      final plugin = PluginRegistry.instance.byId('Douyin');
      expect(plugin, isNotNull);
      expect(plugin!.displayName, '抖音');
    });

    test('falls back to yt-dlp for unknown hosts', () {
      expect(
        PluginRegistry.instance.find('https://example.com/video/1'),
        isNull,
      );
    });
  });
}
