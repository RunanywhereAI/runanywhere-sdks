package com.runanywhere.sdk.core.onnx

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge

private val logger = SDKLogger.onnx

/**
 * JVM/Android implementation of ONNX native registration.
 *
 * Uses the self-contained ONNXBridge to register the backend,
 * mirroring the Swift ONNXBackend XCFramework architecture.
 *
 * The ONNX module has its own JNI library (librac_backend_onnx_jni.so)
 * that provides backend registration, separate from the main commons JNI.
 */
internal actual fun ONNX.registerNative(): Int {
    logger.debug("Ensuring commons JNI is loaded for service registry")
    // Ensure commons JNI is loaded first (provides service registry)
    RunAnywhereBridge.ensureNativeLibraryLoaded()

    logger.debug("Loading ONNX JNI library")
    // Load and use the dedicated ONNX JNI
    if (!ONNXBridge.ensureNativeLibraryLoaded()) {
        logger.error("Failed to load ONNX native library")
        throw UnsatisfiedLinkError("Failed to load ONNX native library")
    }

    logger.debug("Calling native ONNX register")
    val result = ONNXBridge.nativeRegister()
    logger.debug("Native ONNX register returned: $result")
    return result
}

/**
 * JVM/Android implementation of ONNX native unregistration.
 */
internal actual fun ONNX.unregisterNative(): Int {
    logger.debug("Calling native ONNX unregister")
    val result = ONNXBridge.nativeUnregister()
    logger.debug("Native ONNX unregister returned: $result")
    return result
}
