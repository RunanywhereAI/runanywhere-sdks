package com.runanywhere.sdk.core.onnx

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge

private val logger = SDKLogger.onnx

/**
 * Platform extension registrar.
 * On Android: Registers KokoroTTSProvider.
 * On JVM desktop: No-op.
 */
internal object PlatformExtensions {
    @Volatile
    private var registrar: (() -> Unit)? = null
    
    /**
     * Set the platform-specific extension registrar.
     * Called from androidMain to provide the Kokoro registration function.
     */
    fun setRegistrar(block: () -> Unit) {
        logger.info("PlatformExtensions.setRegistrar() called")
        registrar = block
    }
    
    /**
     * Register platform extensions if a registrar is set.
     */
    fun register() {
        logger.info("PlatformExtensions.register() called, registrar=${registrar != null}")
        if (registrar != null) {
            logger.info("Invoking registrar...")
            registrar?.invoke()
            logger.info("Registrar invoked successfully")
        } else {
            logger.info("No registrar set, skipping platform extensions")
        }
    }
}

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

/**
 * JVM/Android implementation of TTS provider count query.
 * For debugging purposes.
 */
internal actual fun ONNX.getTTSProviderCountNative(): Int {
    if (!ONNXBridge.isLoaded) {
        return -1  // Library not loaded
    }
    return ONNXBridge.nativeGetTTSProviderCount()
}

/**
 * JVM/Android implementation of last TTS error query.
 * For debugging purposes.
 */
internal actual fun ONNX.getLastTTSErrorNative(): Pair<Int, String> {
    if (!ONNXBridge.isLoaded) {
        return Pair(-1, "Library not loaded")
    }
    val errorCode = ONNXBridge.nativeGetLastTTSError()
    val errorDetails = ONNXBridge.nativeGetLastTTSErrorDetails()
    return Pair(errorCode, errorDetails)
}

/**
 * JVM/Android implementation of platform extension registration.
 * 
 * On Android: Registers KokoroTTSProvider for NPU-accelerated TTS.
 * On JVM desktop: No-op (registrar is not set).
 * 
 * The registrar is set by androidMain code during app startup.
 */
internal actual fun ONNX.registerPlatformExtensions() {
    logger.debug("Registering platform extensions...")
    PlatformExtensions.register()
}
