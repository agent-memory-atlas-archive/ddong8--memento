import Flutter
import UIKit

public class BackgroundTaskPlugin: NSObject, FlutterPlugin {
  private static var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.ihasy.memento/background_task",
      binaryMessenger: registrar.messenger()
    )
    let instance = BackgroundTaskPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "beginBackgroundTask":
      let name = (call.arguments as? [String: Any])?["name"] as? String ?? "memento-task"
      BackgroundTaskPlugin.beginBackground(name: name)
      result(BackgroundTaskPlugin.backgroundTaskId.rawValue)
    case "endBackgroundTask":
      BackgroundTaskPlugin.endBackground()
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public static func beginBackground(name: String) {
    endBackground()
    backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: name) {
      endBackground()
    }
  }

  public static func endBackground() {
    if backgroundTaskId != .invalid {
      let currentId = backgroundTaskId
      backgroundTaskId = .invalid
      UIApplication.shared.endBackgroundTask(currentId)
    }
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    BackgroundTaskPlugin.register(with: self.registrar(forPlugin: "BackgroundTaskPlugin"))
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    BackgroundTaskPlugin.register(with: engineBridge.pluginRegistry.registrar(forPlugin: "BackgroundTaskPlugin"))
  }
}
