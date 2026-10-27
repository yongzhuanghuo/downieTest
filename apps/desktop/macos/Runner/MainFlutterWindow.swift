import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let linkChannel = FlutterMethodChannel(
      name: "downie6/links",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    AppDelegate.attachLinkChannel(linkChannel)

    super.awakeFromNib()
  }
}
