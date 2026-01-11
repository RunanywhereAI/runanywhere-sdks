package com.runanywhere.sdk.llm.llamacpp

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge

private val logger = SDKLogger.llamacpp

/**
 * JVM/Android implementation of LlamaCPP native registration.
 *
 * Uses the self-contained LlamaCPPBridge to register the backend,
 * mirroring the Swift LlamaCPPBackend XCFramework architecture.
 *
 * The LlamaCPP module has its own JNI library (librac_backend_llamacpp_jni.so)
 * that provides backend registration, separate from the main commons JNI.
 */
internal actual fun LlamaCPP.registerNative(): Int {
    logger.debug("Ensuring commons JNI is loaded for service registry")
    // Ensure commons JNI is loaded first (provides service registry)
    RunAnywhereBridge.ensureNativeLibraryLoaded()

    logger.debug("Loading dedicated LlamaCPP JNI library")
    // Load and use the dedicated LlamaCPP JNI
    if (!LlamaCPPBridge.ensureNativeLibraryLoaded()) {
        logger.error("Failed to load LlamaCPP native library")
        throw UnsatisfiedLinkError("Failed to load LlamaCPP native library")
    }

    logger.debug("Calling native register")
    val result = LlamaCPPBridge.nativeRegister()
    logger.debug("Native register returned: $result")
    return result
}

/**
 * JVM/Android implementation of LlamaCPP native unregistration.
 */
internal actual fun LlamaCPP.unregisterNative(): Int {
    logger.debug("Calling native unregister")
    val result = LlamaCPPBridge.nativeUnregister()
    logger.debug("Native unregister returned: $result")
    return result
}
