#include "desktop_window_bootstrap_plugin.h"

#include <windows.h>
#include <dwmapi.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>

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

// DWM_SYSTEMBACKDROP_TYPE values:
//   1 = Auto, 2 = DWMSBT_MAINWINDOW (mica),
//   3 = DWMSBT_TRANSIENTWINDOW (acrylic), 4 = DWMSBT_TABBEDWINDOW.
constexpr INT kDwmsbtTransientWindow = 3;

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
    : registrar_(registrar) {}

DesktopWindowBootstrapPlugin::~DesktopWindowBootstrapPlugin() {}

HWND DesktopWindowBootstrapPlugin::GetParentWindow() const {
  return ::GetAncestor(registrar_->GetView()->GetNativeWindow(), GA_ROOT);
}

void DesktopWindowBootstrapPlugin::ApplyDefaultAcrylic() const {
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

  // (2) Win11 22H2+ : DWMWA_SYSTEMBACKDROP_TYPE is the documented path. DWM
  //     handles theme transitions, multi-monitor moves, and RDP reconnects
  //     internally. If this call succeeds we skip the legacy fallback.
  if (GetWindowsBuildNumber() >= 22523) {
    INT backdrop_type = kDwmsbtTransientWindow;
    HRESULT hr = ::DwmSetWindowAttribute(
        hwnd, DWMWA_SYSTEMBACKDROP_TYPE,
        &backdrop_type, sizeof(backdrop_type));
    if (SUCCEEDED(hr)) {
      return;
    }
    // Fall through to the legacy path on driver-level failures.
  }

  // (3) Win10 / pre-22523 Win11 : SetWindowCompositionAttribute is the only
  //     way to get acrylic. The symbol is not exported by user32's import
  //     library, so it must be resolved via GetProcAddress.
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

void DesktopWindowBootstrapPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name() == "initialize") {
    ApplyDefaultAcrylic();
    result->Success(flutter::EncodableValue(true));
  } else if (method_call.method_name() == "getTitlebarInset") {
    result->Success(flutter::EncodableValue(0.0));
  } else {
    result->NotImplemented();
  }
}

}  // namespace desktop_window_bootstrap
