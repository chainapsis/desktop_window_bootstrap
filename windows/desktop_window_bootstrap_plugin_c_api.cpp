#include "include/desktop_window_bootstrap/desktop_window_bootstrap_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "desktop_window_bootstrap_plugin.h"

void DesktopWindowBootstrapPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  desktop_window_bootstrap::DesktopWindowBootstrapPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
