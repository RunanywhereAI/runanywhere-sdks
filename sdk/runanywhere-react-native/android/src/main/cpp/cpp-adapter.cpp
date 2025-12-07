/**
 * cpp-adapter.cpp
 *
 * JNI entry point for RunAnywhere React Native SDK.
 * Uses Nitrogen's auto-generated initialization.
 */

#include <jni.h>

// Include Nitrogen-generated initialization header
#include "runanywhereOnLoad.hpp"

/**
 * JNI_OnLoad - Called when the native library is loaded
 *
 * This initializes the Nitrogen HybridObjects and registers them
 * with the JavaScript runtime.
 */
JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void*) {
    return margelo::nitro::runanywhere::initialize(vm);
}

