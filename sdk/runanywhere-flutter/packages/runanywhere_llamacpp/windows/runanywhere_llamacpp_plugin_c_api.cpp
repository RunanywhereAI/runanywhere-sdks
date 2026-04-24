#include "include/runanywhere_llamacpp/runanywhere_llamacpp_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "runanywhere_llamacpp_plugin.h"

void RunanywhereLlamacppPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  runanywhere_llamacpp::RunanywhereLlamacppPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
