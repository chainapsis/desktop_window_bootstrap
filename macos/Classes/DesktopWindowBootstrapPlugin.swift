import Cocoa
import FlutterMacOS

public final class DesktopWindowBootstrapPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "desktop_window_bootstrap/methods",
      binaryMessenger: registrar.messenger
    )
    let instance = DesktopWindowBootstrapPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "initialize":
      result(true)
    case "getTitlebarInset":
      result(DesktopWindowBootstrapMacOS.titlebarInset())
    case "applyMacOSDesignWindowLayout":
      guard let arguments = call.arguments as? [String: Any] else {
        result(
          FlutterError(
            code: "bad_args",
            message: "Expected layout arguments.",
            details: nil
          )
        )
        return
      }
      result(DesktopWindowBootstrapMacOS.applyMacOSDesignWindowLayout(arguments))
    case "getContentSize":
      let arguments = call.arguments as? [String: Any] ?? [:]
      let fallback = (arguments["titlebarInset"] as? NSNumber)?.doubleValue ?? 32
      result(DesktopWindowBootstrapMacOS.contentSize(titlebarInsetFallback: fallback))
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
