import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private static var linkChannel: FlutterMethodChannel?
  private static var pendingLinks: [String] = []

  /// MainFlutterWindow 在引擎创建后注册；启动早期收到的链接先缓存。
  static func attachLinkChannel(_ channel: FlutterMethodChannel) {
    linkChannel = channel
    channel.setMethodCallHandler { call, result in
      if call.method == "ready" {
        flushPending()
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func flushPending() {
    guard let channel = linkChannel else { return }
    let pending = pendingLinks
    pendingLinks.removeAll()
    for value in pending {
      channel.invokeMethod("openUrl", arguments: value)
    }
  }

  override func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
      forward(url.absoluteString)
    }
  }

  private func forward(_ value: String) {
    if let channel = AppDelegate.linkChannel {
      channel.invokeMethod("openUrl", arguments: value)
    } else {
      AppDelegate.pendingLinks.append(value)
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
