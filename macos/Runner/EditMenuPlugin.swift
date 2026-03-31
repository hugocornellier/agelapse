import Cocoa
import FlutterMacOS

final class EditMenuPlugin: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "agelapse.macos.edit_menu",
      binaryMessenger: registrar.messenger
    )
    registrar.addMethodCallDelegate(EditMenuPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let ok: Bool
    switch call.method {
    case "cut":
      ok = NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
    case "copy":
      ok = NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
    case "paste":
      ok = NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
    case "selectAll":
      ok = NSApp.sendAction(#selector(NSResponder.selectAll(_:)), to: nil, from: nil)
    default:
      result(FlutterMethodNotImplemented)
      return
    }
    result(ok)
  }
}
