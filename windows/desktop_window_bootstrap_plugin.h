#ifndef FLUTTER_PLUGIN_DESKTOP_WINDOW_BOOTSTRAP_PLUGIN_H_
#define FLUTTER_PLUGIN_DESKTOP_WINDOW_BOOTSTRAP_PLUGIN_H_

#ifndef NOMINMAX
#define NOMINMAX
#endif

#include <windows.h>

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>
#include <optional>

namespace desktop_window_bootstrap {

class DesktopWindowBootstrapPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  explicit DesktopWindowBootstrapPlugin(flutter::PluginRegistrarWindows* registrar);

  virtual ~DesktopWindowBootstrapPlugin();

  // Disallow copy and assign.
  DesktopWindowBootstrapPlugin(const DesktopWindowBootstrapPlugin&) = delete;
  DesktopWindowBootstrapPlugin& operator=(const DesktopWindowBootstrapPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

 private:
  HWND GetParentWindow() const;
  void ApplySystemBackdrop() const;
  bool ApplyMacOSDesignWindowLayout(const flutter::EncodableMap& args);
  flutter::EncodableMap GetContentSize(const flutter::EncodableMap& args) const;
  bool SetClientSize(double width, double height, bool center);
  SIZE GetNonClientSize() const;
  double GetWindowScaleFactor() const;
  bool ApplyMinimumClientSize(LPARAM const lparam) const;
  bool ApplyClientAspectRatio(WPARAM const wparam, LPARAM const lparam) const;
  std::optional<LRESULT> HandleWindowProc(HWND hwnd,
                                          UINT message,
                                          WPARAM wparam,
                                          LPARAM lparam);

  flutter::PluginRegistrarWindows* registrar_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  int window_proc_id_ = -1;
  double minimum_client_width_ = 0.0;
  double minimum_client_height_ = 0.0;
  double client_aspect_ratio_ = 0.0;
};

}  // namespace desktop_window_bootstrap

#endif  // FLUTTER_PLUGIN_DESKTOP_WINDOW_BOOTSTRAP_PLUGIN_H_
