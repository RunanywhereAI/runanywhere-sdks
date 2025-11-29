package com.runanywhere.sdk.native.bridge

/**
 * LlamaCPP Native Bridge
 *
 * This object provides JNI bindings to the RunAnywhere Core C API (runanywhere_bridge.h)
 * specifically for the LlamaCPP backend (TEXT_GENERATION capability).
 *
 * Thread Safety:
 * - All methods are thread-safe at the C API level
 * - Handles are opaque pointers managed by native code
 */
internal object RunAnywhereBridge {

    private var isLibraryLoaded = false

    /**
     * Load the native library. Must be called before any other methods.
     * This is idempotent - calling it multiple times is safe.
     */
    @Synchronized
    fun loadLibrary() {
        if (isLibraryLoaded) return

        try {
            // Try to load the JNI bridge library
            System.loadLibrary("runanywhere_jni")

            // Also load dependencies if needed
            try {
                System.loadLibrary("runanywhere_bridge")
            } catch (e: UnsatisfiedLinkError) {
                // May already be loaded or linked statically
            }

            try {
                System.loadLibrary("runanywhere_llamacpp")
            } catch (e: UnsatisfiedLinkError) {
                // May already be loaded or linked statically
            }

            try {
                System.loadLibrary("llama")
            } catch (e: UnsatisfiedLinkError) {
                // May already be loaded
            }

            try {
                System.loadLibrary("ggml")
            } catch (e: UnsatisfiedLinkError) {
                // May already be loaded
            }

            isLibraryLoaded = true
        } catch (e: UnsatisfiedLinkError) {
            throw RuntimeException("Failed to load RunAnywhere LlamaCPP native library", e)
        }
    }

    /**
     * Check if the native library is loaded.
     */
    fun isLoaded(): Boolean = isLibraryLoaded

    // =============================================================================
    // Backend Lifecycle
    // =============================================================================

    @JvmStatic
    external fun nativeGetAvailableBackends(): Array<String>

    @JvmStatic
    external fun nativeCreateBackend(backendName: String): Long

    @JvmStatic
    external fun nativeInitialize(handle: Long, configJson: String?): Int

    @JvmStatic
    external fun nativeIsInitialized(handle: Long): Boolean

    @JvmStatic
    external fun nativeDestroy(handle: Long)

    @JvmStatic
    external fun nativeGetBackendInfo(handle: Long): String

    @JvmStatic
    external fun nativeSupportsCapability(handle: Long, capability: Int): Boolean

    @JvmStatic
    external fun nativeGetCapabilities(handle: Long): IntArray

    @JvmStatic
    external fun nativeGetDevice(handle: Long): Int

    @JvmStatic
    external fun nativeGetMemoryUsage(handle: Long): Long

    // =============================================================================
    // Text Generation
    // =============================================================================

    @JvmStatic
    external fun nativeTextLoadModel(handle: Long, modelPath: String, configJson: String?): Int

    @JvmStatic
    external fun nativeTextIsModelLoaded(handle: Long): Boolean

    @JvmStatic
    external fun nativeTextUnloadModel(handle: Long): Int

    @JvmStatic
    external fun nativeTextGenerate(
        handle: Long,
        prompt: String,
        systemPrompt: String?,
        maxTokens: Int,
        temperature: Float
    ): String?

    @JvmStatic
    external fun nativeTextGenerateStream(
        handle: Long,
        prompt: String,
        systemPrompt: String?,
        maxTokens: Int,
        temperature: Float,
        callback: TextStreamCallback
    ): Int

    @JvmStatic
    external fun nativeTextCancel(handle: Long)

    @JvmStatic
    external fun nativeTextGetModelInfo(handle: Long): String

    // =============================================================================
    // Utility
    // =============================================================================

    @JvmStatic
    external fun nativeGetLastError(): String

    @JvmStatic
    external fun nativeGetVersion(): String

    /**
     * Callback interface for streaming text generation.
     */
    interface TextStreamCallback {
        /**
         * Called for each generated token.
         * @param token The generated token
         * @return true to continue, false to cancel
         */
        fun onToken(token: String): Boolean
    }
}
