import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  static weak var shared: MainFlutterWindow?

  override func awakeFromNib() {
    MainFlutterWindow.shared = self
    self.delegate = self

    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(NSRect(x: windowFrame.origin.x, y: windowFrame.origin.y, width: 1040, height: 720), display: true)
    self.minSize = NSSize(width: 760, height: 520)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  // Intercept red "X" close button to hide window to menu bar / tray instead of quitting
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    sender.orderOut(nil)
    return false
  }
}
