#include "include/runanywhere_onnx/runanywhere_onnx_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "runanywhere_onnx_plugin.h"

void RunanywhereOnnxPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  runanywhere_onnx::RunanywhereOnnxPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
