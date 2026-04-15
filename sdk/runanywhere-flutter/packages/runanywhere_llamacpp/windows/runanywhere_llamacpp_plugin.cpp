#include "runanywhere_llamacpp_plugin.h"

#include <windows.h>

#include <VersionHelpers.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <sstream>

namespace runanywhere_llamacpp {

void RunanywhereLlamacppPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "runanywhere_llamacpp",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<RunanywhereLlamacppPlugin>();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

RunanywhereLlamacppPlugin::RunanywhereLlamacppPlugin() {}

RunanywhereLlamacppPlugin::~RunanywhereLlamacppPlugin() {}

void RunanywhereLlamacppPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name().compare("getPlatformVersion") == 0) {
    std::ostringstream version_stream;
    version_stream << "Windows ";
    if (IsWindows10OrGreater()) {
      version_stream << "10+";
    } else if (IsWindows8OrGreater()) {
      version_stream << "8";
    } else if (IsWindows7OrGreater()) {
      version_stream << "7";
    }
    result->Success(flutter::EncodableValue(version_stream.str()));
  } else if (method_call.method_name().compare("getBackendVersion") == 0) {
    result->Success(flutter::EncodableValue("0.1.5"));
  } else if (method_call.method_name().compare("getBackendName") == 0) {
    result->Success(flutter::EncodableValue("LlamaCPP"));
  } else {
    result->NotImplemented();
  }
}

}  // namespace runanywhere_llamacpp
