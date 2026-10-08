import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Without a delegate, iOS drops a notification that arrives while the app
    // is open. FlutterAppDelegate passes it on to flutter_local_notifications,
    // which shows it, as that plugin's iOS setup asks.
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Register custom MethodChannel plugins
    RawDecoderPlugin.register(
      with: engineBridge.pluginRegistry.registrar(forPlugin: "RawDecoderPlugin")!
    )
    VideoDiagnosticsPlugin.register(
      with: engineBridge.pluginRegistry.registrar(forPlugin: "VideoDiagnosticsPlugin")!
    )
  }
}
