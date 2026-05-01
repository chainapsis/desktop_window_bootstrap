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

  /// Applies a Windows client-area layout derived from a design window size.
  ///
  /// [contentTopInset] is supplied by the app because it belongs to the app's
  /// macOS shell/design policy. For example, a `Size(1080, 720)` design window
  /// with a `32` top inset targets a Windows Flutter client area of
  /// `1080 x 688`.
  static Future<bool> applyWindowsClientAreaLayout({
    required Size windowSize,
    Size? minimumWindowSize,
    required double contentTopInset,
    bool enforceAspectRatio = true,
    bool resize = true,
    bool center = false,
  }) async {
    if (kIsWeb || !Platform.isWindows) return false;
    if (windowSize.width <= 0 || windowSize.height <= 0) {
      throw ArgumentError.value(windowSize, 'windowSize', 'Must be positive.');
    }
    if (minimumWindowSize != null &&
        (minimumWindowSize.width <= 0 || minimumWindowSize.height <= 0)) {
      throw ArgumentError.value(
        minimumWindowSize,
        'minimumWindowSize',
        'Must be positive when provided.',
      );
    }
    if (contentTopInset < 0) {
      throw ArgumentError.value(
        contentTopInset,
        'contentTopInset',
        'Must be non-negative.',
      );
    }

    final arguments = <String, Object?>{
      'width': windowSize.width,
      'height': windowSize.height,
      'contentTopInset': contentTopInset,
      'enforceAspectRatio': enforceAspectRatio,
      'resize': resize,
      'center': center,
    };
    if (minimumWindowSize != null) {
      arguments['minimumWidth'] = minimumWindowSize.width;
      arguments['minimumHeight'] = minimumWindowSize.height;
    }

    final applied = await _channel.invokeMethod<bool>(
      'applyWindowsClientAreaLayout',
      arguments,
    );
    return applied ?? false;
  }

  /// Returns the current Windows Flutter client-area size in logical pixels.
  static Future<Size> getWindowsClientAreaSize() async {
    if (kIsWeb || !Platform.isWindows) return Size.zero;
    final result = await _channel.invokeMapMethod<String, Object?>(
      'getWindowsClientAreaSize',
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
