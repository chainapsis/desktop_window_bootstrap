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

  @discardableResult
  public static func start(
    mainFlutterWindow: NSWindow,
    visualStyle: DesktopWindowVisualStyle = .system
  ) -> DesktopWindowBootstrapViewController {
    self.visualStyle = visualStyle
    configureWindowShell(mainFlutterWindow, visualStyle: visualStyle)

    let controller = DesktopWindowBootstrapViewController(visualStyle: visualStyle)
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

  private static func configureWindowShell(
    _ window: NSWindow,
    visualStyle: DesktopWindowVisualStyle
  ) {
    switch visualStyle {
    case .system:
      window.isOpaque = false
      window.backgroundColor = .clear
    case .opaque:
      window.isOpaque = true
      window.backgroundColor = .windowBackgroundColor
    }
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.styleMask.insert(.fullSizeContentView)
  }

  private static func configureVisualEffect(
    _ visualEffectView: NSVisualEffectView,
    visualStyle: DesktopWindowVisualStyle
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

    configureWindowShell(window, visualStyle: visualStyle)
    window.standardWindowButton(.zoomButton)?.isEnabled = false
    configureVisualEffect(controller.visualEffectView, visualStyle: visualStyle)
    window.invalidateShadow()
  }

  private static func applyFullscreenAppearance() {
    guard let window = mainWindow,
          let controller = window.contentViewController as? DesktopWindowBootstrapViewController
    else {
      return
    }

    configureWindowShell(window, visualStyle: .opaque)
    configureVisualEffect(controller.visualEffectView, visualStyle: .opaque)
    window.invalidateShadow()
  }
}
