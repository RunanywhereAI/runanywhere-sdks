package com.runanywhere.sdk.diffusion.sdcpp

/**
 * JVM/Android actual implementation for sd.cpp native registration.
 * Calls rac_backend_sdcpp_register() via JNI.
 */
internal actual fun SdcppDiffusion.registerNative(): Int {
    if (!SdcppBridge.ensureNativeLibraryLoaded()) {
        return -1
    }
    return SdcppBridge.nativeRegister()
}
