import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

const MethodChannel _channel = MethodChannel(
  'desktop_window_bootstrap/methods',
);

/// App-specific desktop window bootstrap helpers.
class DesktopWindowBootstrap {
  DesktopWindowBootstrap._();

  /// Default windowed titlebar overlap for the macOS full-size-content shell.
  ///
  /// The package treats macOS as the design source of truth: if an app designs
  /// against a 1080 x 720 macOS window, the usable app body is 1080 x 688 after
  /// this titlebar safe area is applied. Windows layout helpers use that body
  /// size as the Win32 client-area target.
  static const double defaultMacOSWindowedTitlebarInset = 32;

  static double _cachedTitlebarInset = 0;

  /// Applies the platform's default visual treatment.
  ///
  /// macOS startup appearance is configured natively before the window is
  /// shown, so the method-channel hop is intentionally a no-op there.
  static Future<void> initialize() async {
    if (kIsWeb) return;
    if (!_isSupportedDesktopPlatform) return;
    await _channel.invokeMethod<void>('initialize');
    if (Platform.isMacOS) {
      _cachedTitlebarInset = await _readTitlebarInset();
    }
  }

  /// Height of the overlapping macOS titlebar area when full-size content view
  /// is enabled. Returns 0 on non-macOS platforms.
  static Future<double> getTitlebarInset() async {
    if (kIsWeb || !Platform.isMacOS) return 0;
    final inset = await _readTitlebarInset();
    _cachedTitlebarInset = inset;
    return inset;
  }

  static bool get _isSupportedDesktopPlatform {
    return Platform.isMacOS || Platform.isWindows || Platform.isLinux;
  }

  static double get cachedTitlebarInset {
    return _cachedTitlebarInset;
  }

  /// Returns the usable app-body size implied by a macOS design window size.
  ///
  /// For the default shell, `Size(1080, 720)` becomes `Size(1080, 688)`.
  static Size macOSWindowedContentSizeFor(
    Size windowSize, {
    double titlebarInset = defaultMacOSWindowedTitlebarInset,
  }) {
    final normalizedInset = titlebarInset >= 0 ? titlebarInset : 0.0;
    final contentHeight = windowSize.height - normalizedInset;
    return Size(windowSize.width, contentHeight > 0 ? contentHeight : 0);
  }

  /// Applies a desktop window layout expressed in macOS design-window units.
  ///
  /// On macOS, [size] is applied as the native NSWindow frame size. On Windows,
  /// [size] is translated into a Win32 client-area target by subtracting
  /// [titlebarInset] from the height; the outer HWND is then expanded by the
  /// current native frame/titlebar thickness. This keeps the actual Flutter
  /// content area aligned with the macOS full-size-content design surface.
  static Future<void> applyMacOSDesignWindowLayout({
    required Size size,
    Size? minimumSize,
    bool enforceAspectRatio = true,
    bool center = false,
    double titlebarInset = defaultMacOSWindowedTitlebarInset,
  }) async {
    if (kIsWeb) return;
    if (!_isSupportedDesktopPlatform) return;
    if (size.width <= 0 || size.height <= 0) {
      throw ArgumentError.value(size, 'size', 'Must be positive.');
    }
    if (minimumSize != null &&
        (minimumSize.width <= 0 || minimumSize.height <= 0)) {
      throw ArgumentError.value(
        minimumSize,
        'minimumSize',
        'Must be positive when provided.',
      );
    }

    final arguments = <String, Object?>{
      'width': size.width,
      'height': size.height,
      'enforceAspectRatio': enforceAspectRatio,
      'center': center,
      'titlebarInset': titlebarInset,
    };
    if (minimumSize != null) {
      arguments['minimumWidth'] = minimumSize.width;
      arguments['minimumHeight'] = minimumSize.height;
    }

    await _channel.invokeMethod<void>(
      'applyMacOSDesignWindowLayout',
      arguments,
    );
  }

  /// Returns the current usable Flutter content size where the platform can
  /// report it. Unsupported platforms return `Size.zero`.
  static Future<Size> getContentSize({
    double titlebarInset = defaultMacOSWindowedTitlebarInset,
  }) async {
    if (kIsWeb) return Size.zero;
    if (!_isSupportedDesktopPlatform) return Size.zero;

    final result = await _channel.invokeMapMethod<String, Object?>(
      'getContentSize',
      <String, Object?>{'titlebarInset': titlebarInset},
    );
    final width = result?['width'];
    final height = result?['height'];
    if (width is num && height is num) {
      return Size(width.toDouble(), height.toDouble());
    }
    return Size.zero;
  }

  static Future<double> _readTitlebarInset() async {
    final inset = await _channel.invokeMethod<double>('getTitlebarInset');
    return inset ?? 0;
  }
}

/// Pads the app body below the overlapping macOS titlebar area.
class DesktopWindowTitlebarSafeArea extends StatefulWidget {
  const DesktopWindowTitlebarSafeArea({
    super.key,
    required this.child,
    this.isEnabled = true,
  });

  final Widget child;
  final bool isEnabled;

  @override
  State<DesktopWindowTitlebarSafeArea> createState() =>
      _DesktopWindowTitlebarSafeAreaState();
}

class _DesktopWindowTitlebarSafeAreaState
    extends State<DesktopWindowTitlebarSafeArea>
    with WidgetsBindingObserver {
  static const _metricsRefreshDebounce = Duration(milliseconds: 75);

  late double _titlebarInset;
  int _refreshRequestId = 0;
  Timer? _refreshDebounce;

  @override
  void initState() {
    super.initState();
    _titlebarInset = DesktopWindowBootstrap.cachedTitlebarInset;
    WidgetsBinding.instance.addObserver(this);
    _refreshInset();
  }

  @override
  void didUpdateWidget(covariant DesktopWindowTitlebarSafeArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isEnabled != widget.isEnabled && widget.isEnabled) {
      _refreshInset();
    } else if (oldWidget.isEnabled && !widget.isEnabled) {
      _refreshDebounce?.cancel();
    }
  }

  @override
  void didChangeMetrics() {
    if (!widget.isEnabled) return;
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(_metricsRefreshDebounce, _refreshInset);
  }

  @override
  void dispose() {
    _refreshDebounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _refreshInset() async {
    final requestId = ++_refreshRequestId;
    if (!widget.isEnabled) return;
    final inset = await DesktopWindowBootstrap.getTitlebarInset();
    if (!mounted || !widget.isEnabled || requestId != _refreshRequestId) return;
    final normalizedInset = inset >= 0 ? inset : 0.0;
    if (normalizedInset == _titlebarInset) return;
    setState(() => _titlebarInset = normalizedInset);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isEnabled || kIsWeb || !Platform.isMacOS) {
      return widget.child;
    }

    return Padding(
      padding: EdgeInsets.only(top: _titlebarInset),
      child: widget.child,
    );
  }
}
