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
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
