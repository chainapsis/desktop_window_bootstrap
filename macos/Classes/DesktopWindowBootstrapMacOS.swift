import Cocoa
import FlutterMacOS

public enum DesktopWindowVisualStyle: String {
  case system
  case opaque
}

public enum DesktopWindowBootstrapMacOS {
  private static weak var mainWindow: NSWindow?
  private static var fullscreenObservers: [NSObjectProtocol] = []
  private static var cachedWindowedTitlebarInset: Double = 0
  private static var visualStyle: DesktopWindowVisualStyle = .system
  private static var opaqueBackgroundColor: NSColor?

  @discardableResult
  public static func start(
    mainFlutterWindow: NSWindow,
    visualStyle: DesktopWindowVisualStyle = .system,
    backgroundColor: NSColor? = nil
  ) -> DesktopWindowBootstrapViewController {
    self.visualStyle = visualStyle
    self.opaqueBackgroundColor = backgroundColor
    configureWindowShell(
      mainFlutterWindow,
      visualStyle: visualStyle,
      backgroundColor: backgroundColor
    )

    let controller = DesktopWindowBootstrapViewController(
      visualStyle: visualStyle,
      backgroundColor: backgroundColor
    )
    let windowFrame = mainFlutterWindow.frame
    mainFlutterWindow.contentViewController = controller
    mainFlutterWindow.setFrame(windowFrame, display: true)

    mainWindow = mainFlutterWindow
    applyWindowedAppearance()
    installFullscreenObservers()

    return controller
  }

  public static func titlebarInset() -> Double {
    guard let window = mainWindow else {
      return 0
    }

    let windowFrameHeight = window.contentView?.frame.height ?? 0
    let contentLayoutRectHeight = window.contentLayoutRect.height
    let inset = max(0, windowFrameHeight - contentLayoutRectHeight)

    if window.styleMask.contains(.fullScreen) {
      return 0
    }
    if inset > 0 {
      cachedWindowedTitlebarInset = inset
      return inset
    }
    return cachedWindowedTitlebarInset
  }

  public static func setOpaqueBackgroundColor(_ backgroundColor: NSColor?) {
    if colorsMatch(opaqueBackgroundColor, backgroundColor) {
      return
    }
    opaqueBackgroundColor = backgroundColor
    applyBackgroundSurfacesOnly()
  }

  private static func configureWindowShell(
    _ window: NSWindow,
    visualStyle: DesktopWindowVisualStyle,
    backgroundColor: NSColor?
  ) {
    switch visualStyle {
    case .system:
      window.isOpaque = false
    case .opaque:
      window.isOpaque = true
    }
    configureWindowBackground(
      window,
      visualStyle: visualStyle,
      backgroundColor: backgroundColor
    )
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.styleMask.insert(.fullSizeContentView)
  }

  private static func configureVisualEffect(
    _ visualEffectView: NSVisualEffectView,
    visualStyle: DesktopWindowVisualStyle,
    backgroundColor: NSColor?
  ) {
    visualEffectView.state = .active
    switch visualStyle {
    case .system:
      visualEffectView.blendingMode = .behindWindow
      if #available(macOS 10.14, *) {
        visualEffectView.material = .fullScreenUI
      }
    case .opaque:
      visualEffectView.blendingMode = .withinWindow
      if #available(macOS 10.14, *) {
        visualEffectView.material = .windowBackground
      }
    }
    configureVisualEffectBackground(
      visualEffectView,
      visualStyle: visualStyle,
      backgroundColor: backgroundColor
    )
  }

  private static func configureFlutterBackground(
    _ controller: DesktopWindowBootstrapViewController,
    visualStyle: DesktopWindowVisualStyle,
    backgroundColor: NSColor?
  ) {
    switch visualStyle {
    case .system:
      controller.flutterViewController.backgroundColor = .clear
    case .opaque:
      controller.flutterViewController.backgroundColor = backgroundColor ?? .clear
    }
  }

  private static func applyBackgroundSurfacesOnly() {
    guard let window = mainWindow,
          let controller = window.contentViewController as? DesktopWindowBootstrapViewController
    else {
      return
    }

    let effectiveVisualStyle: DesktopWindowVisualStyle = window.styleMask
      .contains(.fullScreen)
      ? .opaque
      : visualStyle
    configureWindowBackground(
      window,
      visualStyle: effectiveVisualStyle,
      backgroundColor: opaqueBackgroundColor
    )
    configureVisualEffectBackground(
      controller.visualEffectView,
      visualStyle: effectiveVisualStyle,
      backgroundColor: opaqueBackgroundColor
    )
    configureFlutterBackground(
      controller,
      visualStyle: effectiveVisualStyle,
      backgroundColor: opaqueBackgroundColor
    )
    window.invalidateShadow()
  }

  private static func configureWindowBackground(
    _ window: NSWindow,
    visualStyle: DesktopWindowVisualStyle,
    backgroundColor: NSColor?
  ) {
    switch visualStyle {
    case .system:
      window.backgroundColor = .clear
    case .opaque:
      window.backgroundColor = backgroundColor ?? .windowBackgroundColor
    }
  }

  private static func configureVisualEffectBackground(
    _ visualEffectView: NSVisualEffectView,
    visualStyle: DesktopWindowVisualStyle,
    backgroundColor: NSColor?
  ) {
    switch visualStyle {
    case .system:
      visualEffectView.layer?.backgroundColor = nil
    case .opaque:
      if let backgroundColor {
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.backgroundColor = backgroundColor.cgColor
      } else {
        visualEffectView.layer?.backgroundColor = nil
      }
    }
  }

  private static func colorsMatch(_ lhs: NSColor?, _ rhs: NSColor?) -> Bool {
    switch (lhs, rhs) {
    case (nil, nil):
      return true
    case let (lhs?, rhs?):
      return lhs.isEqual(rhs)
    default:
      return false
    }
  }

  private static func installFullscreenObservers() {
    guard fullscreenObservers.isEmpty, let window = mainWindow else {
      return
    }

    let center = NotificationCenter.default
    fullscreenObservers.append(
      center.addObserver(
        forName: NSWindow.willEnterFullScreenNotification,
        object: window,
        queue: .main
      ) { _ in
        applyFullscreenAppearance()
      }
    )
    fullscreenObservers.append(
      center.addObserver(
        forName: NSWindow.willExitFullScreenNotification,
        object: window,
        queue: .main
      ) { _ in
        applyWindowedAppearance()
      }
    )
  }

  private static func applyWindowedAppearance() {
    guard let window = mainWindow,
          let controller = window.contentViewController as? DesktopWindowBootstrapViewController
    else {
      return
    }

    configureWindowShell(
      window,
      visualStyle: visualStyle,
      backgroundColor: opaqueBackgroundColor
    )
    window.standardWindowButton(.zoomButton)?.isEnabled = false
    configureVisualEffect(
      controller.visualEffectView,
      visualStyle: visualStyle,
      backgroundColor: opaqueBackgroundColor
    )
    configureFlutterBackground(
      controller,
      visualStyle: visualStyle,
      backgroundColor: opaqueBackgroundColor
    )
    window.invalidateShadow()
  }

  private static func applyFullscreenAppearance() {
    guard let window = mainWindow,
          let controller = window.contentViewController as? DesktopWindowBootstrapViewController
    else {
      return
    }

    configureWindowShell(
      window,
      visualStyle: .opaque,
      backgroundColor: opaqueBackgroundColor
    )
    configureVisualEffect(
      controller.visualEffectView,
      visualStyle: .opaque,
      backgroundColor: opaqueBackgroundColor
    )
    configureFlutterBackground(
      controller,
      visualStyle: .opaque,
      backgroundColor: opaqueBackgroundColor
    )
    window.invalidateShadow()
  }
}
