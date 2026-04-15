#ifndef FLUTTER_PLUGIN_RUNANYWHERE_LLAMACPP_PLUGIN_H_
#define FLUTTER_PLUGIN_RUNANYWHERE_LLAMACPP_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace runanywhere_llamacpp {

class RunanywhereLlamacppPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  RunanywhereLlamacppPlugin();

  virtual ~RunanywhereLlamacppPlugin();

  RunanywhereLlamacppPlugin(const RunanywhereLlamacppPlugin&) = delete;
  RunanywhereLlamacppPlugin& operator=(const RunanywhereLlamacppPlugin&) = delete;

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace runanywhere_llamacpp

#endif  // FLUTTER_PLUGIN_RUNANYWHERE_LLAMACPP_PLUGIN_H_
