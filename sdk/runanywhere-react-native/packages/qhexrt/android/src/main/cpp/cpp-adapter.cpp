/**
 * cpp-adapter.cpp
 *
 * Android JNI entry point for the RunAnywhereQHexRT native module.
 * This file is required by React Native's CMake build system.
 */

#include <jni.h>
#include "runanywhereqhexrtOnLoad.hpp"

#ifndef RAC_QHEXRT_BACKEND_AVAILABLE
#define RAC_QHEXRT_BACKEND_AVAILABLE 0
#endif

#if RAC_QHEXRT_BACKEND_AVAILABLE
extern "C" void rac_qhexrt_set_skel_directory(const char* path);
#endif

extern "C" JNIEXPORT void JNICALL
Java_com_margelo_nitro_runanywhere_qhexrt_RunAnywhereQHexRTPackage_nativeSetSkelDirectory(
    JNIEnv* env,
    jclass,
    jstring path) {
#if RAC_QHEXRT_BACKEND_AVAILABLE
    if (path == nullptr) {
        rac_qhexrt_set_skel_directory(nullptr);
        return;
    }

    const char* chars = env->GetStringUTFChars(path, nullptr);
    if (chars == nullptr) {
        return;
    }
    rac_qhexrt_set_skel_directory(chars);
    env->ReleaseStringUTFChars(path, chars);
#else
    (void)env;
    (void)path;
#endif
}

extern "C" JNIEXPORT jint JNI_OnLoad(JavaVM* vm, void* reserved) {
    // Initialize nitrogen module and register HybridObjects
    return margelo::nitro::runanywhere::qhexrt::initialize(vm);
}
