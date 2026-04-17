#ifndef FLUTTER_PLUGIN_DESKTOP_WINDOW_BOOTSTRAP_PLUGIN_H_
#define FLUTTER_PLUGIN_DESKTOP_WINDOW_BOOTSTRAP_PLUGIN_H_

#include <windows.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

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
  void ApplyDefaultAcrylic() const;

  flutter::PluginRegistrarWindows* registrar_;
};

}  // namespace desktop_window_bootstrap

#endif  // FLUTTER_PLUGIN_DESKTOP_WINDOW_BOOTSTRAP_PLUGIN_H_
