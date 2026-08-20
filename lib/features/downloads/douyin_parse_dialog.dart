import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../core/engine/douyin_downloader.dart';
import '../../core/storage/settings_storage.dart';
import '../../data/models/format_option.dart';
import '../../data/models/video_info.dart';

/// 抖音解析对话框
///
/// 抖音的 yt-dlp 提取器被反爬打穿，这里绕过它：用内置 WebView 打开视频页，
/// 从页面数据（window._ROUTER_DATA）抓真实播放地址，构造 [VideoInfo]。
///
/// 用户点「解析链接」→ 弹出本对话框 → WebView 加载视频页 → 抓数据 →
/// 自动关闭并返回 [VideoInfo]。
class DouyinParseDialog extends StatefulWidget {
  final String url;
  final WebViewEnvironment? environment;

  const DouyinParseDialog({super.key, required this.url, this.environment});

  /// 弹窗解析抖音视频，返回 [VideoInfo]；失败/取消返回 null。
  static Future<VideoInfo?> show(BuildContext context, String url) async {
    WebViewEnvironment? env;
    if (Platform.isWindows) {
      try {
        final dir = await SettingsStorage.getStorageDir();
        env = await WebViewEnvironment.create(
          settings: WebViewEnvironmentSettings(
            userDataFolder: '${dir.path}\\WebView2',
          ),
        );
      } catch (e) {
        debugPrint('[抖音解析] WebView2 环境创建失败: $e');
      }
    }
    return showDialog<VideoInfo>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DouyinParseDialog(url: url, environment: env),
    );
  }

  @override
  State<DouyinParseDialog> createState() => _DouyinParseDialogState();
}

class _DouyinParseDialogState extends State<DouyinParseDialog> {
  InAppWebViewController? _controller;
  bool _finished = false;
  String _status = '正在加载抖音视频页...';

  @override
  void initState() {
    super.initState();
    // 30 秒超时保护
    Future.delayed(const Duration(seconds: 30), () {
      if (mounted && !_finished) {
        _finish(null, '解析超时');
      }
    });
  }

  void _finish(VideoInfo? info, String? error) {
    if (_finished) return;
    _finished = true;
    if (info != null) {
      debugPrint('[抖音解析] ✅ 成功: ${info.title}，${info.formats.length} 个格式');
      Navigator.of(context).pop(info);
    } else {
      debugPrint('[抖音解析] ❌ 失败: $error');
      Navigator.of(context).pop();
    }
  }

  /// 抓页面数据并构造 VideoInfo
  Future<void> _extractAndFinish() async {
    final c = _controller;
    if (c == null || _finished) return;
    if (mounted) setState(() => _status = '正在提取视频信息...');

    const script = r'''
      (() => {
        const rd = window._ROUTER_DATA;
        if (!rd) return JSON.stringify({ok: false, reason: 'no _ROUTER_DATA'});
        function findVideo(obj, depth) {
          if (!obj || typeof obj !== 'object' || depth > 25) return null;
          if (obj.video && obj.video.play_addr) return obj;
          for (const k in obj) {
            if (k === '__proto__' || k === 'constructor') continue;
            const r = findVideo(obj[k], depth + 1);
            if (r) return r;
          }
          return null;
        }
        const item = findVideo(rd, 0);
        if (!item) return JSON.stringify({ok: false, reason: 'no video item'});
        const v = item.video || {};
        const bitRates = (v.bit_rate || []).map(b => ({
          bitRate: b.bit_rate || 0,
          gearName: b.gear_name || '',
          url: (b.play_addr && b.play_addr.url_list && b.play_addr.url_list[0]) || '',
        }));
        return JSON.stringify({
          ok: true,
          desc: item.desc || '',
          author: (item.author && item.author.nickname) || '',
          duration: item.duration || 0,
          cover: (v.cover && v.cover.url_list && v.cover.url_list[0]) || '',
          playUrl: (v.play_addr && v.play_addr.url_list && v.play_addr.url_list[0]) || '',
          bitRates: bitRates,
        });
      })()
    ''';

    try {
      final raw = (await c.evaluateJavascript(source: script))?.toString() ?? '';
      final jsonStr = raw.startsWith('"') && raw.endsWith('"')
          ? raw.substring(1, raw.length - 1)
          : raw;
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      if (map['ok'] != true) {
        debugPrint('[抖音解析] 页面数据未就绪: ${map['reason']}');
        return; // 不结束，等下一次 onLoadStop 再试
      }
      debugPrint('[抖音解析] 抓到数据: desc=${map['desc']} author=${map['author']} '
          'duration=${map['duration']} bitRates=${(map['bitRates'] as List? ?? []).length}');
      _finish(_buildVideoInfo(map), null);
    } catch (e) {
      debugPrint('[抖音解析] JS 提取失败: $e');
    }
  }

  VideoInfo _buildVideoInfo(Map<String, dynamic> map) {
    final desc = (map['desc'] as String?) ?? '';
    final author = (map['author'] as String?) ?? '';
    final durationMs = (map['duration'] as num?)?.toInt() ?? 0;
    final cover = (map['cover'] as String?) ?? '';
    final playUrl = (map['playUrl'] as String?) ?? '';
    final bitRates = (map['bitRates'] as List? ?? []).cast<Map>();

    final formats = <FormatOption>[];
    for (final b in bitRates) {
      final url = (b['url'] as String?) ?? '';
      if (url.isEmpty) continue;
      final gearName = (b['gearName'] as String?) ?? '';
      final height = _parseHeight(gearName);
      formats.add(FormatOption(
        formatId: url,
        label: height > 0
            ? '${height}P MP4'
            : (gearName.isNotEmpty ? gearName : 'MP4'),
        height: height,
        ext: 'mp4',
        audioOnly: false,
        needsMerge: false,
      ));
    }
    // 没有 bit_rate 时用主播放地址兜底
    if (formats.isEmpty && playUrl.isNotEmpty) {
      formats.add(FormatOption(
        formatId: playUrl,
        label: '原画 MP4',
        height: 0,
        ext: 'mp4',
      ));
    }

    return VideoInfo(
      url: widget.url,
      title: desc.isEmpty ? '抖音视频' : desc,
      duration: durationMs > 1000 ? durationMs ~/ 1000 : durationMs,
      uploader: author,
      thumbnail: cover,
      extractor: 'Douyin',
      videoId: '',
      formats: formats,
    );
  }

  /// 从 gear_name（如 "1080x1920"）解析高度（取第二个数字）
  int _parseHeight(String gearName) {
    final parts = gearName.split('x');
    if (parts.length >= 2) {
      final h = int.tryParse(parts[1].trim());
      if (h != null && h > 0) return h;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      child: SizedBox(
        width: 900,
        height: 650,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: theme.dividerColor)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.video_collection, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '解析抖音视频',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: '取消',
                    onPressed: () => _finish(null, '用户取消'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  InAppWebView(
                    webViewEnvironment: widget.environment,
                    initialUrlRequest:
                        URLRequest(url: WebUri(widget.url)),
                    initialSettings: InAppWebViewSettings(
                      javaScriptEnabled: true,
                      userAgent: DouyinDownloader.ua,
                    ),
                    onWebViewCreated: (controller) {
                      _controller = controller;
                      debugPrint('[抖音解析] webview 已创建');
                    },
                    onLoadStart: (controller, url) {
                      debugPrint('[抖音解析] 开始加载: $url');
                    },
                    onLoadStop: (controller, url) {
                      debugPrint('[抖音解析] 加载完成: $url');
                      // 等页面异步数据就绪后抓取
                      Future.delayed(const Duration(milliseconds: 1500),
                          _extractAndFinish);
                    },
                    onReceivedError: (controller, request, error) {
                      debugPrint('[抖音解析] 加载错误: ${error.description}');
                    },
                  ),
                  if (_status.isNotEmpty)
                    Positioned(
                      top: 12,
                      left: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _status,
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
