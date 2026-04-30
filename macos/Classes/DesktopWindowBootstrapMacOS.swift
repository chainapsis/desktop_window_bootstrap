import Cocoa
import FlutterMacOS

public enum DesktopWindowBootstrapMacOS {
  private static weak var mainWindow: NSWindow?
  private static var fullscreenObservers: [NSObjectProtocol] = []
  private static var cachedWindowedTitlebarInset: Double = 0
  private static let defaultWindowedTitlebarInset: Double = 32

  @discardableResult
  public static func start(mainFlutterWindow: NSWindow) -> DesktopWindowBootstrapViewController {
    configureWindowShell(mainFlutterWindow)

    let controller = DesktopWindowBootstrapViewController()
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

  public static func applyMacOSDesignWindowLayout(_ arguments: [String: Any]) -> Bool {
    guard let window = mainWindow,
          let width = numberArgument(arguments, "width"),
          let height = numberArgument(arguments, "height"),
          width > 0,
          height > 0
    else {
      return false
    }

    if let minimumWidth = numberArgument(arguments, "minimumWidth"),
       let minimumHeight = numberArgument(arguments, "minimumHeight"),
       minimumWidth > 0,
       minimumHeight > 0 {
      window.minSize = NSSize(width: minimumWidth, height: minimumHeight)
    }

    let enforceAspectRatio = arguments["enforceAspectRatio"] as? Bool ?? true
    if enforceAspectRatio {
      window.aspectRatio = NSSize(width: width, height: height)
    } else {
      window.resizeIncrements = NSSize(width: 1, height: 1)
    }

    let shouldCenter = arguments["center"] as? Bool ?? false
    var frame = window.frame
    let maxY = frame.maxY
    frame.size = NSSize(width: width, height: height)
    frame.origin.y = maxY - height
    window.setFrame(frame, display: true)
    if shouldCenter {
      window.center()
    }
    return true
  }

  public static func contentSize(titlebarInsetFallback: Double) -> [String: Double] {
    guard let window = mainWindow else {
      return ["width": 0, "height": 0]
    }

    let inset = normalizedTitlebarInset(
      measuredInset: titlebarInset(),
      fallback: titlebarInsetFallback
    )
    return [
      "width": Double(window.frame.width),
      "height": max(0.0, Double(window.frame.height) - inset),
    ]
  }

  private static func configureWindowShell(_ window: NSWindow) {
    window.isOpaque = false
    window.backgroundColor = .clear
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.styleMask.insert(.fullSizeContentView)
  }

  private static func normalizedTitlebarInset(
    measuredInset: Double,
    fallback: Double
  ) -> Double {
    guard let window = mainWindow,
          !window.styleMask.contains(.fullScreen)
    else {
      return 0
    }
    if measuredInset > 0 {
      return measuredInset
    }
    if fallback >= 0 {
      return fallback
    }
    return defaultWindowedTitlebarInset
  }

  private static func numberArgument(
    _ arguments: [String: Any],
    _ name: String
  ) -> Double? {
    if let value = arguments[name] as? NSNumber {
      return value.doubleValue
    }
    if let value = arguments[name] as? Double {
      return value
    }
    return nil
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

    configureWindowShell(window)
    window.standardWindowButton(.zoomButton)?.isEnabled = false
    controller.visualEffectView.state = .active
    if #available(macOS 10.14, *) {
      controller.visualEffectView.material = .fullScreenUI
    }
    window.invalidateShadow()
  }

  private static func applyFullscreenAppearance() {
    guard let window = mainWindow,
          let controller = window.contentViewController as? DesktopWindowBootstrapViewController
    else {
      return
    }

    window.isOpaque = true
    window.backgroundColor = .windowBackgroundColor
    if #available(macOS 10.14, *) {
      controller.visualEffectView.material = .windowBackground
    }
    window.invalidateShadow()
  }
}
