package com.runanywhere.sdk.core.onnx

import com.runanywhere.sdk.native.bridge.RunAnywhereBridge

/**
 * JVM/Android implementation of ONNX native registration.
 * Calls rac_backend_onnx_register() via JNI.
 */
internal actual fun ONNX.registerNative(): Int {
    RunAnywhereBridge.ensureNativeLibraryLoaded()
    return RunAnywhereBridge.racBackendOnnxRegister()
}

/**
 * JVM/Android implementation of ONNX native unregistration.
 * Calls rac_backend_onnx_unregister() via JNI.
 */
internal actual fun ONNX.unregisterNative(): Int {
    return RunAnywhereBridge.racBackendOnnxUnregister()
}
