import 'automation_request.dart';

/// Windows 安装包通过协议启动时，命令行参数会进入 Dart main；
/// 先缓存，等主窗口壳层初始化后统一处理。
class AutomationQueue {
  AutomationQueue._();

  static final List<AutomationRequest> _pending = <AutomationRequest>[];

  static void seed(List<String> args) {
    for (final arg in args) {
      final request = parseAutomationRequest(arg);
      if (request != null) _pending.add(request);
    }
  }

  static List<AutomationRequest> drain() {
    final pending = List<AutomationRequest>.of(_pending);
    _pending.clear();
    return pending;
  }
}
