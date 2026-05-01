# desktop_window_bootstrap

Minimal desktop window bootstrap helpers for Flutter desktop apps.

## Windows Client Area

`applyWindowsClientAreaLayout` adjusts the native Windows outer HWND so the
Flutter client area matches a design window size after a caller-supplied top
inset is removed.

The inset is intentionally not owned by this package. Apps that design against a
macOS full-size-content window should pass their own macOS titlebar/safe-area
height, for example `32`.

```dart
await DesktopWindowBootstrap.applyWindowsClientAreaLayout(
  windowSize: const Size(1080, 720),
  minimumWindowSize: const Size(1080, 720),
  contentTopInset: 32,
  center: true,
);
```

With those values, Windows targets a Flutter client area of `1080 x 688`.
`getWindowsClientAreaSize()` returns the current Windows client area in logical
pixels for resize reconciliation.

