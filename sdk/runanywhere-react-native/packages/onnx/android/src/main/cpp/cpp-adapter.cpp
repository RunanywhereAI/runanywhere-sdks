/**
 * cpp-adapter.cpp
 *
 * Android JNI entry point for RunAnywhereONNX native module.
 * This file is required by React Native's CMake build system.
 */

#include <jni.h>
#include <fbjni/fbjni.h>
#include "runanywhereonnxOnLoad.hpp"

extern "C" JNIEXPORT jint JNI_OnLoad(JavaVM* vm, void* reserved) {
    return facebook::jni::initialize(vm, []() {
        margelo::nitro::runanywhere::onnx::registerAllNatives();
    });
}
