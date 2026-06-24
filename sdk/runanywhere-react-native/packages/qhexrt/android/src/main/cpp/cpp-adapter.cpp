/**
 * cpp-adapter.cpp
 *
 * Android JNI entry point for the RunAnywhereQHexRT native module.
 * This file is required by React Native's CMake build system.
 */

#include <jni.h>
#include "runanywhereqhexrtOnLoad.hpp"

extern "C" JNIEXPORT jint JNI_OnLoad(JavaVM* vm, void* reserved) {
    // Initialize nitrogen module and register HybridObjects
    return margelo::nitro::runanywhere::qhexrt::initialize(vm);
}
