package com.runanywhere.sdk.llm.llamacpp

import com.runanywhere.sdk.native.bridge.RunAnywhereBridge

/**
 * JVM/Android implementation of LlamaCPP native registration.
 * Calls rac_backend_llamacpp_register() via JNI.
 */
internal actual fun LlamaCPP.registerNative(): Int {
    RunAnywhereBridge.ensureNativeLibraryLoaded()
    return RunAnywhereBridge.racBackendLlamacppRegister()
}

/**
 * JVM/Android implementation of LlamaCPP native unregistration.
 * Calls rac_backend_llamacpp_unregister() via JNI.
 */
internal actual fun LlamaCPP.unregisterNative(): Int {
    return RunAnywhereBridge.racBackendLlamacppUnregister()
}
