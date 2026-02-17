import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    self.appearance = NSAppearance(named: .darkAqua)

    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Register custom MethodChannel plugins
    let registrar = flutterViewController.registrar(forPlugin: "RawDecoderPlugin")
    RawDecoderPlugin.register(with: registrar)

    super.awakeFromNib()
  }
}
