import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private let customTitleBarHeight: CGFloat = 42.0
  private let trafficLightLeftPadding: CGFloat = 7.0
  // Native traffic lights are a fixed 14pt; macOS has no API to resize them, so
  // we visually scale them with a layer transform. 1.0 = native size. The
  // horizontal spacing between buttons is compressed by the same factor so the
  // smaller circles keep proportional gaps.
  private let trafficLightScale: CGFloat = 0.9
  private var defaultButtonPositions: [NSWindow.ButtonType: CGFloat] = [:]
  private var isRepositioning = false
  private weak var observedCloseButton: NSButton?
  // While true (fullscreen transition + fullscreen), we leave the buttons alone
  // so macOS's native auto-hiding overlay can size/position them itself.
  private var suppressForFullScreen = false

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

    // Re-center on every window signal that can follow an AppKit titlebar
    // layout. didUpdate is the important one: it fires after the window
    // finishes updating (including AppKit's final post-show layout pass that
    // otherwise leaves the buttons high until the window is manually focused).
    let nc = NotificationCenter.default
    for name in [
      NSWindow.didResizeNotification,
      NSWindow.didBecomeKeyNotification,
      NSWindow.didBecomeMainNotification,
      NSWindow.didUpdateNotification,
    ] {
      nc.addObserver(self, selector: #selector(onWindowLayoutChange), name: name, object: self)
    }
    // Fullscreen needs special handling: restore native buttons on the way in,
    // re-apply our centering/scaling on the way out.
    nc.addObserver(
      self,
      selector: #selector(onWillEnterFullScreen),
      name: NSWindow.willEnterFullScreenNotification,
      object: self
    )
    nc.addObserver(
      self,
      selector: #selector(onDidExitFullScreen),
      name: NSWindow.didExitFullScreenNotification,
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

  // AppKit re-centers the traffic lights by moving the BUTTONS themselves on
  // many layout passes. Observing the close button's own frame lets us
  // re-assert our position the moment AppKit nudges it. If AppKit ever replaces
  // the button instance (e.g. titlebar reconstruction), we rebind to the new
  // one and recapture native x positions.
  private func ensureButtonObserver(_ closeButton: NSButton) {
    guard observedCloseButton !== closeButton else { return }
    if let old = observedCloseButton {
      NotificationCenter.default.removeObserver(
        self, name: NSView.frameDidChangeNotification, object: old
      )
    }
    observedCloseButton = closeButton
    closeButton.postsFrameChangedNotifications = true
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(onWindowLayoutChange),
      name: NSView.frameDidChangeNotification,
      object: closeButton
    )
    // The button hierarchy changed; recapture native x positions next pass.
    defaultButtonPositions.removeAll()
  }

  @objc private func onWindowLayoutChange(_ notification: Notification) {
    repositionTrafficLights()
  }

  // Entering fullscreen: stop customizing and hand the buttons back to AppKit
  // by clearing our scale transform. AppKit positions them in its own overlay.
  @objc private func onWillEnterFullScreen(_ notification: Notification) {
    suppressForFullScreen = true
    for type: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
      if let layer = standardWindowButton(type)?.layer,
         !CATransform3DEqualToTransform(layer.transform, CATransform3DIdentity) {
        layer.transform = CATransform3DIdentity
      }
    }
  }

  // Back to windowed: re-apply our centering/scaling once AppKit has restored
  // the normal titlebar (deferred so we run after its layout settles).
  @objc private func onDidExitFullScreen(_ notification: Notification) {
    suppressForFullScreen = false
    DispatchQueue.main.async { [weak self] in
      self?.repositionTrafficLights()
    }
  }

  private func repositionTrafficLights() {
    // Moving the close button fires frameDidChange / triggers another window
    // update synchronously; this guard prevents the observer from re-entering.
    guard !isRepositioning else { return }
    // In native fullscreen, macOS shows the traffic lights in its own
    // auto-hiding overlay and positions them itself. Leave them alone; the
    // flag also covers the transition, before styleMask reports .fullScreen.
    guard !suppressForFullScreen, !styleMask.contains(.fullScreen) else { return }
    guard let closeButton = standardWindowButton(.closeButton),
          let titlebarView = closeButton.superview else { return }
    ensureButtonObserver(closeButton)
    isRepositioning = true
    defer { isRepositioning = false }

    // We deliberately do NOT resize the titlebar container/view. A taller
    // container makes AppKit draw the *large* traffic lights. The native
    // container (~32px, flush to the window top) is tall enough to hold the
    // buttons at the centered position, so they stay normal-sized and clickable.
    let containerHeight = titlebarView.bounds.height
    let buttonHeight = closeButton.frame.height

    // Center within `customTitleBarHeight`, measured from the window top.
    let yOffset: CGFloat
    if titlebarView.isFlipped {
      yOffset = (customTitleBarHeight / 2.0 - buttonHeight / 2.0).rounded()
    } else {
      yOffset = (containerHeight - customTitleBarHeight / 2.0 - buttonHeight / 2.0)
        .rounded()
    }

    // Capture native x positions on the first pass so spacing compression and
    // re-asserts are measured against AppKit's defaults, not our own output.
    for type: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
      guard let button = standardWindowButton(type) else { continue }
      if defaultButtonPositions[type] == nil {
        defaultButtonPositions[type] = button.frame.origin.x
      }
    }
    let closeDefaultX = defaultButtonPositions[.closeButton] ?? closeButton.frame.origin.x
    let baseX = closeDefaultX + trafficLightLeftPadding

    for type: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
      guard let button = standardWindowButton(type) else { continue }

      // Compress inter-button spacing by the scale factor, anchored on close.
      let offsetFromClose = (defaultButtonPositions[type] ?? closeDefaultX) - closeDefaultX
      let xOffset = baseX + offsetFromClose * trafficLightScale
      let target = NSPoint(x: xOffset, y: yOffset)
      if button.frame.origin != target {
        button.setFrameOrigin(target)
      }

      // Scale the button about its own center via a layer transform. We keep
      // the frame at native size (so hit-testing is unaffected) and only scale
      // what's drawn. Re-asserted here because AppKit can clear the transform.
      button.wantsLayer = true
      if let layer = button.layer {
        let w = button.bounds.width
        let h = button.bounds.height
        let scaleTransform = CATransform3DConcat(
          CATransform3DMakeScale(trafficLightScale, trafficLightScale, 1.0),
          CATransform3DMakeTranslation(
            w * (1.0 - trafficLightScale) / 2.0,
            h * (1.0 - trafficLightScale) / 2.0,
            0.0
          )
        )
        if !CATransform3DEqualToTransform(layer.transform, scaleTransform) {
          layer.transform = scaleTransform
        }
      }
    }
  }
}
