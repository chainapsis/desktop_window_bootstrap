#include "desktop_window_bootstrap_plugin.h"

#include <windows.h>
#include <dwmapi.h>
#include <shellscalingapi.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <memory>
#include <optional>

namespace {

static constexpr auto kChannelName = "desktop_window_bootstrap/methods";

typedef enum _WINDOWCOMPOSITIONATTRIB {
  WCA_ACCENT_POLICY = 19,
} WINDOWCOMPOSITIONATTRIB;

typedef struct _WINDOWCOMPOSITIONATTRIBDATA {
  WINDOWCOMPOSITIONATTRIB Attrib;
  PVOID pvData;
  SIZE_T cbData;
} WINDOWCOMPOSITIONATTRIBDATA;

typedef enum _ACCENT_STATE {
  ACCENT_ENABLE_ACRYLICBLURBEHIND = 4,
} ACCENT_STATE;

typedef struct _ACCENT_POLICY {
  ACCENT_STATE AccentState;
  DWORD AccentFlags;
  DWORD GradientColor;
  DWORD AnimationId;
} ACCENT_POLICY;

typedef BOOL(WINAPI* SetWindowCompositionAttributeFn)(
    HWND, WINDOWCOMPOSITIONATTRIBDATA*);

// --- Win11 22H2+ system-backdrop ---
// Older Windows SDK headers may not define DWMWA_SYSTEMBACKDROP_TYPE; redefine
// locally so the plugin builds against any SDK >= 10.0.22000. The value is
// stable and documented at:
// https://learn.microsoft.com/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute
#ifndef DWMWA_SYSTEMBACKDROP_TYPE
#define DWMWA_SYSTEMBACKDROP_TYPE 38
#endif

// DWM_SYSTEMBACKDROP_TYPE values
// (https://learn.microsoft.com/windows/win32/api/dwmapi/ne-dwmapi-dwm_systembackdrop_type):
//   0 = DWMSBT_AUTO,            1 = DWMSBT_NONE,
//   2 = DWMSBT_MAINWINDOW       (Mica - long-lived main window),
//   3 = DWMSBT_TRANSIENTWINDOW  (Desktop Acrylic, brightest variant),
//   4 = DWMSBT_TABBEDWINDOW     (Mica Alt - tabbed title bar).
//
// Use Mica for our long-lived main window: it matches every first-party Win11
// app (Settings, File Explorer, Calculator, Notepad, Photos, Microsoft Store).
// Microsoft explicitly prohibits acrylic on app backgrounds:
//   "Don't put desktop acrylic on large background surfaces of your app."
//   https://learn.microsoft.com/windows/apps/design/style/acrylic
// Acrylic is reserved for transient surfaces (Start menu, flyouts, context
// menus); applying it to the root window is off-spec and looks heavier than
// every other Win11 app.
constexpr INT kDwmsbtMainWindow = 2;

// IsWindows*OrGreater can lie under app-compat shims unless we ship a manifest
// pinning the supported OS versions. RtlGetVersion always returns the real
// build number.
typedef LONG(WINAPI* RtlGetVersionFn)(PRTL_OSVERSIONINFOW);

DWORD GetWindowsBuildNumber() {
  HMODULE ntdll = ::GetModuleHandleW(L"ntdll.dll");
  if (!ntdll) return 0;
  auto rtl_get_version = reinterpret_cast<RtlGetVersionFn>(
      ::GetProcAddress(ntdll, "RtlGetVersion"));
  if (!rtl_get_version) return 0;
  RTL_OSVERSIONINFOW info = {};
  info.dwOSVersionInfoSize = sizeof(info);
  if (rtl_get_version(&info) != 0 /* STATUS_SUCCESS */) return 0;
  return info.dwBuildNumber;
}

std::optional<double> GetDoubleArgument(const flutter::EncodableMap& args,
                                        const char* name) {
  const auto value = args.find(flutter::EncodableValue(name));
  if (value == args.end()) {
    return std::nullopt;
  }
  if (const auto* double_value = std::get_if<double>(&value->second)) {
    return *double_value;
  }
  if (const auto* int32_value = std::get_if<int32_t>(&value->second)) {
    return static_cast<double>(*int32_value);
  }
  if (const auto* int64_value = std::get_if<int64_t>(&value->second)) {
    return static_cast<double>(*int64_value);
  }
  return std::nullopt;
}

bool GetBoolArgument(const flutter::EncodableMap& args,
                     const char* name,
                     bool fallback) {
  const auto value = args.find(flutter::EncodableValue(name));
  if (value == args.end()) {
    return fallback;
  }
  if (const auto* bool_value = std::get_if<bool>(&value->second)) {
    return *bool_value;
  }
  return fallback;
}

double ClientHeightForWindowHeight(double window_height,
                                   double content_top_inset) {
  return std::max(1.0, window_height - std::max(0.0, content_top_inset));
}

int RoundedPhysicalPixels(double logical_value, double scale_factor) {
  return static_cast<int>(std::round(logical_value * scale_factor));
}

double GetMonitorScaleFactor(HWND hwnd) {
  const HMONITOR monitor = ::MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
  if (!monitor) {
    return 1.0;
  }

  UINT dpi_x = 0;
  UINT dpi_y = 0;
  if (SUCCEEDED(::GetDpiForMonitor(
          monitor, MDT_EFFECTIVE_DPI, &dpi_x, &dpi_y)) &&
      dpi_x > 0) {
    return dpi_x / 96.0;
  }
  return 1.0;
}

}  // namespace

namespace desktop_window_bootstrap {

void DesktopWindowBootstrapPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), kChannelName,
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<DesktopWindowBootstrapPlugin>(registrar);

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

DesktopWindowBootstrapPlugin::DesktopWindowBootstrapPlugin(
    flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar) {
  window_proc_id_ = registrar_->RegisterTopLevelWindowProcDelegate(
      [this](HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
        return HandleWindowProc(hwnd, message, wparam, lparam);
      });
}

DesktopWindowBootstrapPlugin::~DesktopWindowBootstrapPlugin() {
  if (window_proc_id_ != -1) {
    registrar_->UnregisterTopLevelWindowProcDelegate(window_proc_id_);
  }
}

HWND DesktopWindowBootstrapPlugin::GetParentWindow() const {
  return ::GetAncestor(registrar_->GetView()->GetNativeWindow(), GA_ROOT);
}

void DesktopWindowBootstrapPlugin::ApplySystemBackdrop() const {
  const HWND hwnd = GetParentWindow();
  if (!hwnd) {
    return;
  }

  // (1) Extend the DWM-composited frame across the entire client area.
  //     Without this, Flutter's swapchain composes opaquely on top of the DWM
  //     backdrop and the user just sees a black window even when the backdrop
  //     attribute below is honored.
  MARGINS margins = {-1, -1, -1, -1};
  ::DwmExtendFrameIntoClientArea(hwnd, &margins);

  // (2) Win11 22H2+ : DWMWA_SYSTEMBACKDROP_TYPE with DWMSBT_MAINWINDOW
  //     applies Mica - the same material every first-party Win11 app uses
  //     for its main window. DWM handles theme transitions, multi-monitor
  //     moves, RDP reconnects, and the EnableTransparency / battery-saver /
  //     high-contrast / low-end-hardware fallbacks internally.
  if (GetWindowsBuildNumber() >= 22523) {
    INT backdrop_type = kDwmsbtMainWindow;
    HRESULT hr = ::DwmSetWindowAttribute(
        hwnd, DWMWA_SYSTEMBACKDROP_TYPE,
        &backdrop_type, sizeof(backdrop_type));
    if (SUCCEEDED(hr)) {
      return;
    }
    // Fall through to the legacy path on driver-level failures.
  }

  // (3) Win10 / pre-22523 Win11 : DWMWA_MICA_EFFECT (1029) is undocumented
  //     and was only present on a narrow band of pre-RTM Insider builds, so
  //     we don't try it. SetWindowCompositionAttribute with acrylic-blur is
  //     the best translucent material available on these systems. The symbol
  //     is not exported by user32's import library, so it must be resolved
  //     via GetProcAddress.
  const auto user32 = ::GetModuleHandleA("user32.dll");
  if (!user32) {
    return;
  }

  const auto set_window_composition_attribute =
      reinterpret_cast<SetWindowCompositionAttributeFn>(
          ::GetProcAddress(user32, "SetWindowCompositionAttribute"));
  if (!set_window_composition_attribute) {
    return;
  }

  ACCENT_POLICY accent = {
      ACCENT_ENABLE_ACRYLICBLURBEHIND,
      2,
      0xCC222222,
      0,
  };
  WINDOWCOMPOSITIONATTRIBDATA data = {
      WCA_ACCENT_POLICY,
      &accent,
      sizeof(accent),
  };
  set_window_composition_attribute(hwnd, &data);
}

bool DesktopWindowBootstrapPlugin::ApplyWindowsClientAreaLayout(
    const flutter::EncodableMap& args) {
  const auto width = GetDoubleArgument(args, "width");
  const auto height = GetDoubleArgument(args, "height");
  if (!width || !height || *width <= 0 || *height <= 0) {
    return false;
  }

  const double content_top_inset =
      GetDoubleArgument(args, "contentTopInset").value_or(0.0);
  const double client_width = std::max(1.0, *width);
  const double client_height =
      ClientHeightForWindowHeight(*height, content_top_inset);

  const auto minimum_width = GetDoubleArgument(args, "minimumWidth");
  const auto minimum_height = GetDoubleArgument(args, "minimumHeight");
  if (minimum_width && minimum_height && *minimum_width > 0 &&
      *minimum_height > 0) {
    minimum_client_width_ = std::max(1.0, *minimum_width);
    minimum_client_height_ =
        ClientHeightForWindowHeight(*minimum_height, content_top_inset);
  }

  const bool enforce_aspect_ratio =
      GetBoolArgument(args, "enforceAspectRatio", true);
  client_aspect_ratio_ =
      enforce_aspect_ratio ? client_width / client_height : 0.0;

  if (!GetBoolArgument(args, "resize", true)) {
    return true;
  }
  return SetClientSize(
      client_width, client_height, GetBoolArgument(args, "center", false));
}

flutter::EncodableMap DesktopWindowBootstrapPlugin::GetWindowsClientAreaSize()
    const {
  flutter::EncodableMap result;
  const HWND hwnd = GetParentWindow();
  RECT client_rect = {};
  if (!hwnd || !::GetClientRect(hwnd, &client_rect)) {
    result[flutter::EncodableValue("width")] = flutter::EncodableValue(0.0);
    result[flutter::EncodableValue("height")] = flutter::EncodableValue(0.0);
    return result;
  }

  const double scale_factor = GetWindowScaleFactor();
  result[flutter::EncodableValue("width")] = flutter::EncodableValue(
      (client_rect.right - client_rect.left) / scale_factor);
  result[flutter::EncodableValue("height")] = flutter::EncodableValue(
      (client_rect.bottom - client_rect.top) / scale_factor);
  return result;
}

bool DesktopWindowBootstrapPlugin::SetClientSize(double width,
                                                 double height,
                                                 bool center) {
  const HWND hwnd = GetParentWindow();
  if (!hwnd) {
    return false;
  }

  const double scale_factor = GetWindowScaleFactor();
  const SIZE non_client_size = GetNonClientSize();
  const int outer_width =
      RoundedPhysicalPixels(width, scale_factor) + non_client_size.cx;
  const int outer_height =
      RoundedPhysicalPixels(height, scale_factor) + non_client_size.cy;

  int x = 0;
  int y = 0;
  UINT flags = SWP_NOZORDER | SWP_NOOWNERZORDER;
  if (center) {
    HMONITOR monitor = ::MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
    MONITORINFO monitor_info = {};
    monitor_info.cbSize = sizeof(MONITORINFO);
    if (monitor && ::GetMonitorInfo(monitor, &monitor_info)) {
      const RECT work_area = monitor_info.rcWork;
      x = work_area.left +
          ((work_area.right - work_area.left) - outer_width) / 2;
      y = work_area.top +
          ((work_area.bottom - work_area.top) - outer_height) / 2;
    } else {
      flags |= SWP_NOMOVE;
    }
  } else {
    flags |= SWP_NOMOVE;
  }

  return ::SetWindowPos(hwnd, HWND_TOP, x, y, outer_width, outer_height,
                        flags) == TRUE;
}

SIZE DesktopWindowBootstrapPlugin::GetNonClientSize() const {
  const HWND hwnd = GetParentWindow();
  RECT window_rect = {};
  RECT client_rect = {};
  if (!hwnd || !::GetWindowRect(hwnd, &window_rect) ||
      !::GetClientRect(hwnd, &client_rect)) {
    return SIZE{0, 0};
  }

  const int window_width = window_rect.right - window_rect.left;
  const int window_height = window_rect.bottom - window_rect.top;
  const int client_width = client_rect.right - client_rect.left;
  const int client_height = client_rect.bottom - client_rect.top;
  return SIZE{std::max(0, window_width - client_width),
              std::max(0, window_height - client_height)};
}

double DesktopWindowBootstrapPlugin::GetWindowScaleFactor() const {
  const HWND hwnd = GetParentWindow();
  if (!hwnd) {
    return 1.0;
  }

  const UINT dpi = ::GetDpiForWindow(hwnd);
  if (::IsWindowVisible(hwnd) && dpi > 0) {
    return dpi / 96.0;
  }

  const double monitor_scale_factor = GetMonitorScaleFactor(hwnd);
  if (monitor_scale_factor > 0) {
    return monitor_scale_factor;
  }
  return dpi > 0 ? dpi / 96.0 : 1.0;
}

bool DesktopWindowBootstrapPlugin::ApplyMinimumClientSize(
    LPARAM const lparam) const {
  if (minimum_client_width_ <= 0 && minimum_client_height_ <= 0) {
    return false;
  }

  auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
  const double scale_factor = GetWindowScaleFactor();
  const SIZE non_client_size = GetNonClientSize();

  if (minimum_client_width_ > 0) {
    const LONG minimum_outer_width =
        RoundedPhysicalPixels(minimum_client_width_, scale_factor) +
        non_client_size.cx;
    info->ptMinTrackSize.x =
        std::max(info->ptMinTrackSize.x, minimum_outer_width);
  }
  if (minimum_client_height_ > 0) {
    const LONG minimum_outer_height =
        RoundedPhysicalPixels(minimum_client_height_, scale_factor) +
        non_client_size.cy;
    info->ptMinTrackSize.y =
        std::max(info->ptMinTrackSize.y, minimum_outer_height);
  }
  return true;
}

bool DesktopWindowBootstrapPlugin::ApplyClientAspectRatio(
    WPARAM const wparam,
    LPARAM const lparam) const {
  if (client_aspect_ratio_ <= 0) {
    return false;
  }

  auto* rect = reinterpret_cast<RECT*>(lparam);
  const SIZE non_client_size = GetNonClientSize();

  int client_width = std::max(
      1, static_cast<int>(rect->right - rect->left - non_client_size.cx));
  int client_height = std::max(
      1, static_cast<int>(rect->bottom - rect->top - non_client_size.cy));

  const bool is_resizing_horizontally =
      wparam == WMSZ_LEFT || wparam == WMSZ_RIGHT ||
      wparam == WMSZ_TOPLEFT || wparam == WMSZ_BOTTOMLEFT;

  if (is_resizing_horizontally) {
    client_height =
        std::max(1, static_cast<int>(std::round(client_width /
                                                client_aspect_ratio_)));
  } else {
    client_width =
        std::max(1, static_cast<int>(std::round(client_height *
                                                client_aspect_ratio_)));
  }

  const int outer_width = client_width + non_client_size.cx;
  const int outer_height = client_height + non_client_size.cy;
  int left = rect->left;
  int top = rect->top;
  int right = rect->right;
  int bottom = rect->bottom;

  switch (wparam) {
    case WMSZ_RIGHT:
    case WMSZ_BOTTOM:
      right = left + outer_width;
      bottom = top + outer_height;
      break;
    case WMSZ_TOP:
      right = left + outer_width;
      top = bottom - outer_height;
      break;
    case WMSZ_LEFT:
    case WMSZ_TOPLEFT:
      left = right - outer_width;
      top = bottom - outer_height;
      break;
    case WMSZ_TOPRIGHT:
      right = left + outer_width;
      top = bottom - outer_height;
      break;
    case WMSZ_BOTTOMLEFT:
      left = right - outer_width;
      bottom = top + outer_height;
      break;
    case WMSZ_BOTTOMRIGHT:
      right = left + outer_width;
      bottom = top + outer_height;
      break;
  }

  rect->left = left;
  rect->top = top;
  rect->right = right;
  rect->bottom = bottom;
  return true;
}

std::optional<LRESULT> DesktopWindowBootstrapPlugin::HandleWindowProc(
    HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  (void)hwnd;
  if (message == WM_GETMINMAXINFO && ApplyMinimumClientSize(lparam)) {
    return 0;
  }
  if (message == WM_SIZING && ApplyClientAspectRatio(wparam, lparam)) {
    return TRUE;
  }
  return std::nullopt;
}

void DesktopWindowBootstrapPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name() == "initialize") {
    ApplySystemBackdrop();
    result->Success(flutter::EncodableValue(true));
  } else if (method_call.method_name() == "getTitlebarInset") {
    result->Success(flutter::EncodableValue(0.0));
  } else if (method_call.method_name() == "applyWindowsClientAreaLayout") {
    const auto* args =
        std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (!args) {
      result->Error("bad_args", "Expected a map of layout arguments.");
      return;
    }
    result->Success(
        flutter::EncodableValue(ApplyWindowsClientAreaLayout(*args)));
  } else if (method_call.method_name() == "getWindowsClientAreaSize") {
    result->Success(flutter::EncodableValue(GetWindowsClientAreaSize()));
  } else {
    result->NotImplemented();
  }
}

}  // namespace desktop_window_bootstrap
