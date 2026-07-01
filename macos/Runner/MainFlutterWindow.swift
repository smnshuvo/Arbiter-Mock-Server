import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  // Retained for the lifetime of the window: owns the menu bar Live Activity.
  private var menuBarController: MenuBarController?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    menuBarController = MenuBarController(
      messenger: flutterViewController.engine.binaryMessenger
    )

    super.awakeFromNib()
  }
}
