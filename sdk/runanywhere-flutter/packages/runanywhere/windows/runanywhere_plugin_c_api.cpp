#include "include/runanywhere/runanywhere_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "runanywhere_plugin.h"

void RunanywherePluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  runanywhere::RunanywherePlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
