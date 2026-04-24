#ifndef FLUTTER_PLUGIN_RUNANYWHERE_ONNX_PLUGIN_H_
#define FLUTTER_PLUGIN_RUNANYWHERE_ONNX_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace runanywhere_onnx {

class RunanywhereOnnxPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  RunanywhereOnnxPlugin();

  virtual ~RunanywhereOnnxPlugin();

  RunanywhereOnnxPlugin(const RunanywhereOnnxPlugin&) = delete;
  RunanywhereOnnxPlugin& operator=(const RunanywhereOnnxPlugin&) = delete;

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace runanywhere_onnx

#endif  // FLUTTER_PLUGIN_RUNANYWHERE_ONNX_PLUGIN_H_
