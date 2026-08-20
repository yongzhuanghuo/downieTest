import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../core/storage/settings_storage.dart';
import '../../data/models/format_option.dart';
import '../../data/models/video_info.dart';

/// 抖音解析对话框（WebView 拦截 aweme/detail API）
///
/// 2026 年抖音分享页 SSR 不再内嵌播放地址，视频数据由前端 JS 异步调
/// `aweme/detail` API 拉取（该 API 需要 a_bogus 签名）。这里用真实浏览器
/// 环境（WebView）打开视频页，提前注入 JS hook 拦截 `aweme/detail` 的响应，
/// 从响应 JSON 提取播放地址，绕过签名。
class DouyinWebDialog extends StatefulWidget {
  final String url;
  final WebViewEnvironment? environment;

  const DouyinWebDialog({super.key, required this.url, this.environment});

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
        debugPrint('[抖音] WebView2 环境已创建');
      } catch (e) {
        debugPrint('[抖音] WebView2 环境创建失败: $e');
      }
    }
    return showDialog<VideoInfo>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DouyinWebDialog(url: url, environment: env),
    );
  }

  @override
  State<DouyinWebDialog> createState() => _DouyinWebDialogState();
}

class _DouyinWebDialogState extends State<DouyinWebDialog> {
  InAppWebViewController? _controller;
  bool _finished = false;
  int _probe = 0;
  String _status = '正在加载抖音视频页，请稍后...';

  /// 桌面 Chrome UA：只有桌面 UA 才会从分享页跳转到视频页，
  /// 视频页才请求 aweme/detail；移动 UA 会停在「打开 App」引导页。
  static const String _desktopUA =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

  /// 注入到页面最前端的 hook 脚本：拦截 aweme/detail 的 fetch/XHR 响应
  static const String _hookScript = r'''
    (function () {
      var put = function (url, text) {
        if (url && (url.indexOf('aweme/detail') >= 0 || url.indexOf('aweme_detail') >= 0)) {
          try { window.__douyin_data__ = text; window.__douyin_data_url__ = url; } catch (e) {}
        }
      };
      var of = window.fetch;
      if (of) {
        window.fetch = function () {
          var args = arguments;
          return of.apply(this, args).then(function (resp) {
            var u = (typeof args[0] === 'string') ? args[0] : (args[0] && args[0].url);
            try { var c = resp.clone(); c.text().then(function (t) { put(u, t); }); } catch (e) {}
            return resp;
          });
        };
      }
      var oo = XMLHttpRequest.prototype.open, os = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.open = function (m, u) {
        this.__du = u;
        return oo.apply(this, arguments);
      };
      XMLHttpRequest.prototype.send = function () {
        var self = this;
        this.addEventListener('load', function () { put(self.__du, self.responseText); });
        return os.apply(this, arguments);
      };
    })();
  ''';

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 20), () {
      if (mounted && !_finished) _finish(null, '解析超时（20s 未截获数据）');
    });
  }

  void _finish(VideoInfo? info, String? error) {
    if (_finished) return;
    _finished = true;
    if (info != null) {
      debugPrint('[抖音] ✅ 成功: ${info.title}，${info.formats.length} 个格式');
      Navigator.of(context).pop(info);
    } else {
      debugPrint('[抖音] ❌ 失败: $error');
      Navigator.of(context).pop();
    }
  }

  /// 轮询读 window.__douyin_data__，读到就解析
  Future<void> _tryReadData() async {
    final c = _controller;
    if (c == null || _finished) return;
    try {
      final raw = await c.evaluateJavascript(
        source: 'JSON.stringify({url: window.__douyin_data_url__ || "", '
            'data: window.__douyin_data__ || ""})',
      );
      final map = jsonDecode(_unwrap(raw?.toString() ?? '')) as Map<String, dynamic>;
      final url = (map['url'] as String?) ?? '';
      final data = (map['data'] as String?) ?? '';
      debugPrint('[抖音] 探测 #$_probe: 截获URL=$url 数据长度=${data.length}');
      if (data.isNotEmpty) {
        final info = _parseAwemeDetail(data);
        if (info != null) {
          _finish(info, null);
          return;
        }
      }
      if (_probe < 12 && !_finished) {
        _probe++;
        setState(() => _status = '等待视频数据... ($_probe/12)');
        Future.delayed(const Duration(milliseconds: 1200), _tryReadData);
      } else if (!_finished) {
        _finish(null, '未截获 aweme/detail 响应');
      }
    } catch (e) {
      debugPrint('[抖音] 读数据异常: $e');
      if (!_finished) {
        _probe++;
        Future.delayed(const Duration(milliseconds: 1200), _tryReadData);
      }
    }
  }

  VideoInfo? _parseAwemeDetail(String data) {
    try {
      final json = jsonDecode(data) as Map<String, dynamic>;
      final aweme = json['aweme_detail'] as Map<String, dynamic>?;
      if (aweme == null) {
        debugPrint('[抖音] ⚠️ 响应里无 aweme_detail，顶层 keys=${json.keys.toList()}');
        return null;
      }
      final desc = (aweme['desc'] as String?) ?? '';
      final author =
          (aweme['author'] as Map?)?['nickname'] as String? ?? '';
      final durationMs = (aweme['duration'] as num?)?.toInt() ?? 0;
      final video = (aweme['video'] as Map<String, dynamic>?) ?? const {};

      String firstUrl(dynamic addr) {
        if (addr is Map) {
          final urlList = addr['url_list'];
          if (urlList is List && urlList.isNotEmpty) {
            return urlList.first.toString();
          }
          final uri = addr['uri'];
          if (uri is String && uri.isNotEmpty) return uri;
        }
        return '';
      }

      final cover = firstUrl(video['cover']);
      final playAddr = firstUrl(video['play_addr']);

      final formats = <FormatOption>[];
      final bitRates = video['bit_rate'];
      if (bitRates is List) {
        for (final b in bitRates) {
          if (b is! Map) continue;
          final url = firstUrl(b['play_addr']);
          if (url.isEmpty) continue;
          final gearName = (b['gear_name'] as String?) ?? '';
          debugPrint('[抖音]   格式: gear=$gearName');
          formats.add(FormatOption(
            formatId: _noWatermark(url),
            label: gearName.isNotEmpty ? gearName : 'MP4',
            height: 0,
            ext: 'mp4',
            needsMerge: false,
          ));
        }
      }
      if (formats.isEmpty && playAddr.isNotEmpty) {
        formats.add(FormatOption(
          formatId: _noWatermark(playAddr),
          label: '原画 MP4',
          height: 0,
          ext: 'mp4',
        ));
      }

      debugPrint('[抖音] 解析到: desc=$desc author=$author durationMs=$durationMs '
          'formats=${formats.length} cover=$cover');

      return VideoInfo(
        url: widget.url,
        title: desc.isEmpty ? '抖音视频' : desc,
        duration: durationMs > 1000 ? durationMs ~/ 1000 : durationMs,
        uploader: author,
        thumbnail: cover,
        extractor: 'Douyin',
        videoId: aweme['aweme_id']?.toString() ?? '',
        formats: formats,
      );
    } catch (e) {
      debugPrint('[抖音] 解析 aweme_detail 失败: $e');
      return null;
    }
  }

  String _unwrap(String raw) {
    if (raw.startsWith('"') && raw.endsWith('"') && raw.length >= 2) {
      return raw.substring(1, raw.length - 1);
    }
    return raw;
  }

  String _noWatermark(String url) => url.replaceAll('/playwm/', '/play/');

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
                    child: Text('解析抖音视频', style: theme.textTheme.titleMedium),
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
                    initialUrlRequest: URLRequest(url: WebUri(widget.url)),
                    initialSettings: InAppWebViewSettings(
                      javaScriptEnabled: true,
                      userAgent: _desktopUA,
                    ),
                    initialUserScripts: UnmodifiableListView<UserScript>([
                      UserScript(
                        source: _hookScript,
                        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                      ),
                    ]),
                    onWebViewCreated: (controller) {
                      _controller = controller;
                      debugPrint('[抖音] webview 已创建');
                    },
                    onLoadStart: (controller, url) {
                      debugPrint('[抖音] 开始加载: $url');
                    },
                    onLoadStop: (controller, url) {
                      debugPrint('[抖音] 加载完成: $url');
                      Future.delayed(const Duration(milliseconds: 1500),
                          _tryReadData);
                    },
                    onReceivedError: (controller, request, error) {
                      debugPrint('[抖音] 加载错误: ${error.description}');
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
                              child: Text(_status,
                                  style: theme.textTheme.bodySmall),
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
