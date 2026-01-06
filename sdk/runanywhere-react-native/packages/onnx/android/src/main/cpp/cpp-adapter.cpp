/**
 * cpp-adapter.cpp
 *
 * Android JNI entry point for RunAnywhereONNX native module.
 * This file is required by React Native's CMake build system.
 */

#include <jni.h>

extern "C" JNIEXPORT jint JNI_OnLoad(JavaVM* vm, void* reserved) {
    return JNI_VERSION_1_6;
}
