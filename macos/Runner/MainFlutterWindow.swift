import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private let customTitleBarHeight: CGFloat = 42.0
  private let trafficLightLeftPadding: CGFloat = 7.0
  private var defaultButtonPositions: [NSWindow.ButtonType: CGFloat] = [:]

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

    let editMenuRegistrar = flutterViewController.registrar(forPlugin: "EditMenuPlugin")
    EditMenuPlugin.register(with: editMenuRegistrar)

    super.awakeFromNib()

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(onWindowLayoutChange),
      name: NSWindow.didResizeNotification,
      object: self
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(onWindowLayoutChange),
      name: NSWindow.didExitFullScreenNotification,
      object: self
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(onWindowLayoutChange),
      name: NSWindow.didBecomeKeyNotification,
      object: self
    )
  }

  // Catch when window_manager changes titlebar style after awakeFromNib
  override var titlebarAppearsTransparent: Bool {
    didSet {
      DispatchQueue.main.async { [weak self] in
        self?.repositionTrafficLights()
      }
    }
  }

  @objc private func onWindowLayoutChange(_ notification: Notification) {
    repositionTrafficLights()
  }

  private func repositionTrafficLights() {
    guard let closeButton = standardWindowButton(.closeButton),
          let titlebarView = closeButton.superview,
          let titlebarContainer = titlebarView.superview else { return }

    // Expand the native titlebar container to match the Flutter title bar height
    var containerFrame = titlebarContainer.frame
    containerFrame.size.height = customTitleBarHeight
    containerFrame.origin.y = frame.height - customTitleBarHeight
    titlebarContainer.frame = containerFrame

    // Match the inner titlebar view
    var innerFrame = titlebarView.frame
    innerFrame.size.height = customTitleBarHeight
    titlebarView.frame = innerFrame

    // Center each traffic light button vertically
    let buttonHeight = closeButton.frame.height
    let yOffset = (customTitleBarHeight - buttonHeight) / 2.0

    for type: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
      guard let button = standardWindowButton(type) else { continue }
      if defaultButtonPositions[type] == nil {
        defaultButtonPositions[type] = button.frame.origin.x
      }
      let xOffset = defaultButtonPositions[type]! + trafficLightLeftPadding
      button.setFrameOrigin(NSPoint(x: xOffset, y: yOffset))
    }
  }
}
