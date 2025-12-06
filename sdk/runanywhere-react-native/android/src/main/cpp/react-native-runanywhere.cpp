/**
 * react-native-runanywhere.cpp
 *
 * JNI entry point for Android - registers the C++ TurboModule with React Native.
 * This file is the minimal JNI glue that allows the pure C++ RunAnywhereModule
 * to work on Android without any Kotlin/Java bridge code.
 */

#include <jni.h>
#include <fbjni/fbjni.h>
#include <react/renderer/componentregistry/ComponentDescriptorProviderRegistry.h>
#include <ReactCommon/CallInvokerHolder.h>
#include <ReactCommon/TurboModuleBinding.h>
#include "RunAnywhereModule.h"

using namespace facebook;
using namespace facebook::react;

/**
 * TurboModule provider function - called by React Native to create our module.
 * This is the key function that connects our C++ module to React Native's
 * TurboModule system.
 *
 * @param name The module name being requested (should be "RunAnywhere")
 * @param params Initialization parameters including the JSInvoker
 * @return Shared pointer to our RunAnywhereModule, or nullptr if name doesn't match
 */
std::shared_ptr<TurboModule> provideRunAnywhereTurboModule(
    const std::string &name,
    const JavaTurboModule::InitParams &params) {
  if (name == "RunAnywhere") {
    return std::make_shared<RunAnywhereModule>(params.jsInvoker);
  }
  return nullptr;
}

/**
 * JNI_OnLoad - called when the native library is loaded.
 * This is where we register our TurboModule provider with React Native.
 *
 * IMPORTANT: This function is called automatically by Android when
 * System.loadLibrary("runanywhere-react-native") is invoked.
 */
JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM *vm, void *reserved) {
  return facebook::jni::initialize(vm, [] {
    // Register our TurboModule provider function
    // React Native will call provideRunAnywhereTurboModule when
    // JavaScript requests the "RunAnywhere" module
    TurboModuleBinding::registerBinding(&provideRunAnywhereTurboModule);
  });
}
