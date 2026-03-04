package com.runanywhere.sdk.rag

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge

private val logger = SDKLogger.rag

/**
 * JVM/Android implementation of RAG native registration.
 *
 * Uses the self-contained RAGBridge to register the backend,
 * mirroring the Swift RAGBackend XCFramework architecture.
 *
 * The RAG module has its own JNI library (librac_backend_rag_jni.so)
 * that provides backend registration and pipeline operations,
 * separate from the main commons JNI.
 */
internal actual fun RAGModule.registerNative(): Int {
    logger.debug("Ensuring commons JNI is loaded for service registry")
    // Ensure commons JNI is loaded first (provides service registry)
    RunAnywhereBridge.ensureNativeLibraryLoaded()

    logger.debug("Loading dedicated RAG JNI library")
    // Load and use the dedicated RAG JNI
    if (!RAGBridge.ensureNativeLibraryLoaded()) {
        logger.error("Failed to load RAG native library")
        return -1
    }

    logger.debug("Calling native register")
    val result = RAGBridge.nativeRegister()
    logger.debug("Native register returned: $result")
    return result
}

/**
 * JVM/Android implementation of RAG native unregistration.
 */
internal actual fun RAGModule.unregisterNative(): Int {
    logger.debug("Calling native unregister")
    val result = RAGBridge.nativeUnregister()
    logger.debug("Native unregister returned: $result")
    return result
}
