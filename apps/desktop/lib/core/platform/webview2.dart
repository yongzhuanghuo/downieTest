import 'dart:io';

/// 检测 Windows 是否安装了 WebView2 runtime。
/// flutter_inappwebview 在 Windows 上依赖它显示网页；没装会导致登录弹窗空白。
bool isWebView2Available() {
  if (!Platform.isWindows) return true; // 其它平台用各自系统 webview，不需要
  try {
    final env = Platform.environment;
    final bases = [
      env['ProgramFiles(x86)'],
      env['ProgramFiles'],
    ].whereType<String>();
    for (final base in bases) {
      final appDir = Directory('$base\\Microsoft\\EdgeWebView\\Application');
      if (!appDir.existsSync()) continue;
      for (final e in appDir.listSync()) {
        if (e is Directory &&
            File('${e.path}\\msedgewebview2.exe').existsSync()) {
          return true;
        }
      }
    }
    return false;
  } catch (_) {
    return false;
  }
}

/// 用系统默认浏览器打开 WebView2 下载页
Future<void> openWebView2DownloadPage() async {
  const url = 'https://developer.microsoft.com/microsoft-edge/webview2/';
  try {
    if (Platform.isWindows) {
      // rundll32 触发 Shell 打开 URL，浏览器会正确置顶（explorer 方式有时压在窗口下面）
      await Process.run('rundll32', ['url.dll,FileProtocolHandler', url]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [url]);
    }
  } catch (_) {}
}
