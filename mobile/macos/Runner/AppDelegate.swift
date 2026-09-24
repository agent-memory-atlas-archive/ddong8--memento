import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var statusItem: NSStatusItem?

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // Keep app running in menu bar / tray when window is closed
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    setupStatusItem()
    setupMethodChannel()
  }

  private func setupMethodChannel() {
    guard let controller = MainFlutterWindow.shared?.contentViewController as? FlutterViewController else { return }
    let channel = FlutterMethodChannel(name: "com.ihasy.memento/app_window", binaryMessenger: controller.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] (call, result) in
      if call.method == "showMainWindow" {
        self?.showMainWindow()
        result(true)
      } else if call.method == "hideMainWindow" {
        guard let window = MainFlutterWindow.shared else {
          result(false)
          return
        }
        window.orderOut(nil)
        result(true)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      showMainWindow()
    }
    return true
  }

  private func setupStatusItem() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    guard let button = statusItem?.button else { return }

    if let icon = loadTrayIcon() {
      button.image = icon
      button.imagePosition = .imageOnly
    } else {
      button.title = "M"
    }

    button.toolTip = "Memento"
    button.target = self
    button.action = #selector(statusItemClicked(_:))
    button.sendAction(on: [.leftMouseUp, .rightMouseUp])
  }

  private func loadTrayIcon() -> NSImage? {
    if let image = NSImage(named: NSImage.Name("AppIcon"))?.copy() as? NSImage {
      image.size = NSSize(width: 18, height: 18)
      image.isTemplate = false
      return image
    }
    if let appImage = NSApp.applicationIconImage?.copy() as? NSImage {
      appImage.size = NSSize(width: 18, height: 18)
      appImage.isTemplate = false
      return appImage
    }
    return nil
  }

  @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
    guard let event = NSApp.currentEvent else { return }
    if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
      showStatusMenu()
    } else {
      toggleMainWindow()
    }
  }

  @objc private func toggleMainWindow() {
    guard let window = MainFlutterWindow.shared else { return }
    if window.isVisible && NSApp.isActive {
      window.orderOut(nil)
    } else {
      showMainWindow()
    }
  }

  @objc private func showMainWindow() {
    guard let window = MainFlutterWindow.shared else { return }
    if window.isMiniaturized {
      window.deminiaturize(nil)
    }
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  private func showStatusMenu() {
    let menu = NSMenu()
    menu.autoenablesItems = false

    let isVisible = MainFlutterWindow.shared?.isVisible ?? false
    let toggleItem = NSMenuItem(
      title: isVisible ? "隐藏 Memento" : "显示 Memento",
      action: #selector(toggleMainWindow),
      keyEquivalent: ""
    )
    toggleItem.target = self
    menu.addItem(toggleItem)

    menu.addItem(NSMenuItem.separator())

    let quitItem = NSMenuItem(
      title: "退出 Memento",
      action: #selector(quitApp),
      keyEquivalent: "q"
    )
    quitItem.target = self
    menu.addItem(quitItem)

    statusItem?.menu = menu
    statusItem?.button?.performClick(nil)
    statusItem?.menu = nil
  }

  @objc private func quitApp() {
    NSApp.terminate(nil)
  }
}
