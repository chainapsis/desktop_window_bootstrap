# desktop_window_bootstrap

Minimal desktop window bootstrap helpers for Flutter desktop apps.

## macOS Design Window Layout

This package treats the macOS full-size-content window as the design source of
truth. In the default shell, a macOS window sized to `1080 x 720` has a
`32 dp` overlapping titlebar safe area, so the usable Flutter app body is
`1080 x 688`.

Windows does not overlap Flutter content with its native titlebar. When
`applyMacOSDesignWindowLayout` receives a macOS design window size, the Windows
implementation subtracts the macOS titlebar inset from the requested height and
targets that result as the Win32 client rect. It then expands the outer HWND by
the current native frame/titlebar thickness for the active DPI.

```dart
await DesktopWindowBootstrap.applyMacOSDesignWindowLayout(
  size: const Size(1080, 720),
  minimumSize: const Size(1080, 720),
  enforceAspectRatio: true,
  center: true,
);
```

On Windows, the example above targets:

```text
client/content:     1080 x 688
8 dp shell gap:     1064 x 672
content ratio:      1080 / 688
```

The default titlebar inset is
`DesktopWindowBootstrap.defaultMacOSWindowedTitlebarInset`, currently `32`.
Pass `titlebarInset` to override it for a different macOS shell.
