package com.runanywhere.sdk.llm.llamacpp

import com.runanywhere.sdk.native.bridge.RunAnywhereBridge

/**
 * JVM/Android implementation of LlamaCPP native registration.
 *
 * Uses the self-contained LlamaCPPBridge to register the backend,
 * mirroring the Swift LlamaCPPBackend XCFramework architecture.
 *
 * The LlamaCPP module has its own JNI library (librunanywhere_llamacpp.so)
 * that provides backend registration via rac_backend_llamacpp_jni.cpp.
 */
internal actual fun LlamaCPP.registerNative(): Int {
    // Ensure main JNI is loaded first (provides core infrastructure)
    RunAnywhereBridge.ensureNativeLibraryLoaded()

    // Load and use the dedicated LlamaCPP JNI
    if (!LlamaCPPBridge.ensureNativeLibraryLoaded()) {
        throw UnsatisfiedLinkError("Failed to load LlamaCPP native library")
    }

    // Call the actual JNI method
    return LlamaCPPBridge.nativeRegister()
}

/**
 * JVM/Android implementation of LlamaCPP native unregistration.
 */
internal actual fun LlamaCPP.unregisterNative(): Int {
    return LlamaCPPBridge.nativeUnregister()
}
