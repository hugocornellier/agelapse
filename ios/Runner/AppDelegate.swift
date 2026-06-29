import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Register custom MethodChannel plugins
    RawDecoderPlugin.register(
      with: engineBridge.pluginRegistry.registrar(forPlugin: "RawDecoderPlugin")!
    )
  }
}
