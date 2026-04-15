#include "runanywhere_plugin.h"

#include <windows.h>

#include <VersionHelpers.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <sstream>

namespace runanywhere {

void RunanywherePlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "runanywhere",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<RunanywherePlugin>();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

RunanywherePlugin::RunanywherePlugin() {}

RunanywherePlugin::~RunanywherePlugin() {}

void RunanywherePlugin::HandleMethodCall(
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
  } else if (method_call.method_name().compare("getSDKVersion") == 0) {
    result->Success(flutter::EncodableValue("0.16.0"));
  } else if (method_call.method_name().compare("getCommonsVersion") == 0) {
    result->Success(flutter::EncodableValue("0.1.5"));
  } else {
    result->NotImplemented();
  }
}

}  // namespace runanywhere
