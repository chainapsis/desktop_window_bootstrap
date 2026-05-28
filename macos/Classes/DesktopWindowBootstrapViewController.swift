import Cocoa
import FlutterMacOS

public final class DesktopWindowBootstrapViewController: NSViewController {
  private let _flutterViewController: FlutterViewController
  private let visualStyle: DesktopWindowVisualStyle

  public var flutterViewController: FlutterViewController {
    _flutterViewController
  }

  public var visualEffectView: NSVisualEffectView {
    view as! NSVisualEffectView
  }

  public init(
    flutterViewController: FlutterViewController? = nil,
    visualStyle: DesktopWindowVisualStyle = .system
  ) {
    _flutterViewController = flutterViewController ?? FlutterViewController()
    self.visualStyle = visualStyle
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  public override func loadView() {
    let effectView = NSVisualEffectView()
    effectView.autoresizingMask = [.width, .height]
    effectView.state = .active
    switch visualStyle {
    case .system:
      effectView.blendingMode = .behindWindow
      if #available(macOS 10.14, *) {
        effectView.material = .fullScreenUI
      }
    case .opaque:
      effectView.blendingMode = .withinWindow
      if #available(macOS 10.14, *) {
        effectView.material = .windowBackground
      }
    }
    view = effectView
  }

  public override func viewDidLoad() {
    super.viewDidLoad()

    addChild(_flutterViewController)
    _flutterViewController.view.frame = view.bounds
    _flutterViewController.view.autoresizingMask = [.width, .height]
    _flutterViewController.backgroundColor = .clear
    view.addSubview(_flutterViewController.view)
  }
}
