import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

const MethodChannel _channel = MethodChannel('desktop_window_bootstrap/methods');

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
  State<DesktopWindowTitlebarSafeArea> createState() => _DesktopWindowTitlebarSafeAreaState();
}

class _DesktopWindowTitlebarSafeAreaState extends State<DesktopWindowTitlebarSafeArea>
    with WidgetsBindingObserver {
  late double _titlebarInset;

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
    }
  }

  @override
  void didChangeMetrics() {
    _refreshInset();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _refreshInset() async {
    if (!widget.isEnabled) return;
    final inset = await DesktopWindowBootstrap.getTitlebarInset();
    if (!mounted || inset == _titlebarInset) return;
    setState(() => _titlebarInset = inset >= 0 ? inset : 0);
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
