#ifndef FLUTTER_PLUGIN_RUNANYWHERE_PLUGIN_H_
#define FLUTTER_PLUGIN_RUNANYWHERE_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace runanywhere {

class RunanywherePlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  RunanywherePlugin();

  virtual ~RunanywherePlugin();

  RunanywherePlugin(const RunanywherePlugin&) = delete;
  RunanywherePlugin& operator=(const RunanywherePlugin&) = delete;

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace runanywhere

#endif  // FLUTTER_PLUGIN_RUNANYWHERE_PLUGIN_H_
