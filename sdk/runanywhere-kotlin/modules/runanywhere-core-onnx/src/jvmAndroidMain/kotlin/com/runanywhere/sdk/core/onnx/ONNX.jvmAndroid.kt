package com.runanywhere.sdk.core.onnx

import com.runanywhere.sdk.native.bridge.RunAnywhereBridge

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
    // Ensure commons JNI is loaded first (provides service registry)
    RunAnywhereBridge.ensureNativeLibraryLoaded()

    // Load and use the dedicated ONNX JNI
    if (!ONNXBridge.ensureNativeLibraryLoaded()) {
        throw UnsatisfiedLinkError("Failed to load ONNX native library")
    }

    return ONNXBridge.nativeRegister()
}

/**
 * JVM/Android implementation of ONNX native unregistration.
 */
internal actual fun ONNX.unregisterNative(): Int {
    return ONNXBridge.nativeUnregister()
}
