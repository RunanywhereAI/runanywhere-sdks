package com.runanywhere.sdk.native.bridge

private const val TAG = "RunAnywhereBridge"

// Simple logging that works on both JVM and Android (println shows in logcat on Android)
private fun logI(tag: String, msg: String) = println("I/$tag: $msg")
private fun logD(tag: String, msg: String) = println("D/$tag: $msg")
private fun logE(tag: String, msg: String) = println("E/$tag: $msg")

/**
 * Unified RunAnywhere Native Bridge
 *
 * This object provides JNI bindings to the RunAnywhere Core C API (runanywhere_bridge.h).
 * It works with ALL backends (ONNX, LlamaCPP, TFLite, etc.) through a SINGLE unified interface.
 *
 * The package name MUST be `com.runanywhere.sdk.native.bridge` to match the JNI function
 * registration in the native library (Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_*).
 *
 * Architecture:
 * - Single unified JNI library (librunanywhere_jni.so) handles all backend operations
 * - Backend selection is done at runtime via nativeCreateBackend()
 * - No need to load individual backend libraries - the unified bridge handles everything
 *
 * Thread Safety:
 * - All methods are thread-safe at the C API level
 * - Handles are opaque pointers managed by native code
 * - Stream handles must be destroyed on the same thread they were created (recommended)
 *
 * Usage:
 * 1. Call loadLibrary() before any other methods
 * 2. Create a backend handle with nativeCreateBackend("onnx") or nativeCreateBackend("llamacpp")
 * 3. Use the handle to call capability-specific methods
 * 4. Destroy the handle when done with nativeDestroy()
 */
object RunAnywhereBridge {

    private var isLibraryLoaded = false

    /**
     * Load the unified JNI bridge library. Must be called before any other methods.
     * This is idempotent - calling it multiple times is safe.
     *
     * The unified library contains all backend support (ONNX, LlamaCPP, etc.)
     * and handles dependency loading internally.
     */
    @Synchronized
    fun loadLibrary() {
        if (isLibraryLoaded) return

        try {
            logI(TAG, "Loading unified RunAnywhere JNI library...")
            System.loadLibrary("runanywhere_jni")
            isLibraryLoaded = true
            logI(TAG, "Successfully loaded librunanywhere_jni.so")
        } catch (e: UnsatisfiedLinkError) {
            logE(TAG, "Failed to load RunAnywhere JNI native library: ${e.message}")
            throw RuntimeException("Failed to load RunAnywhere JNI native library", e)
        }
    }

    /**
     * Check if the unified JNI library is loaded.
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
    external fun nativeTextCancel(handle: Long)

    // =============================================================================
    // Speech-to-Text (STT)
    // =============================================================================

    @JvmStatic
    external fun nativeSTTLoadModel(
        handle: Long,
        modelPath: String,
        modelType: String,
        configJson: String?
    ): Int

    @JvmStatic
    external fun nativeSTTIsModelLoaded(handle: Long): Boolean

    @JvmStatic
    external fun nativeSTTUnloadModel(handle: Long): Int

    @JvmStatic
    external fun nativeSTTTranscribe(
        handle: Long,
        audioSamples: FloatArray,
        sampleRate: Int,
        language: String?
    ): String?

    @JvmStatic
    external fun nativeSTTSupportsStreaming(handle: Long): Boolean

    @JvmStatic
    external fun nativeSTTCreateStream(handle: Long, configJson: String?): Long

    @JvmStatic
    external fun nativeSTTFeedAudio(
        handle: Long,
        streamHandle: Long,
        audioSamples: FloatArray,
        sampleRate: Int
    ): Int

    @JvmStatic
    external fun nativeSTTIsReady(handle: Long, streamHandle: Long): Boolean

    @JvmStatic
    external fun nativeSTTDecode(handle: Long, streamHandle: Long): String

    @JvmStatic
    external fun nativeSTTIsEndpoint(handle: Long, streamHandle: Long): Boolean

    @JvmStatic
    external fun nativeSTTInputFinished(handle: Long, streamHandle: Long)

    @JvmStatic
    external fun nativeSTTResetStream(handle: Long, streamHandle: Long)

    @JvmStatic
    external fun nativeSTTDestroyStream(handle: Long, streamHandle: Long)

    @JvmStatic
    external fun nativeSTTCancel(handle: Long)

    // =============================================================================
    // Text-to-Speech (TTS)
    // =============================================================================

    @JvmStatic
    external fun nativeTTSLoadModel(
        handle: Long,
        modelPath: String,
        modelType: String,
        configJson: String?
    ): Int

    @JvmStatic
    external fun nativeTTSIsModelLoaded(handle: Long): Boolean

    @JvmStatic
    external fun nativeTTSUnloadModel(handle: Long): Int

    @JvmStatic
    external fun nativeTTSSynthesize(
        handle: Long,
        text: String,
        voiceId: String?,
        speedRate: Float,
        pitchShift: Float
    ): NativeTTSSynthesisResult?

    @JvmStatic
    external fun nativeTTSSupportsStreaming(handle: Long): Boolean

    @JvmStatic
    external fun nativeTTSGetVoices(handle: Long): String

    @JvmStatic
    external fun nativeTTSCancel(handle: Long)

    // =============================================================================
    // Voice Activity Detection (VAD)
    // =============================================================================

    @JvmStatic
    external fun nativeVADLoadModel(handle: Long, modelPath: String?, configJson: String?): Int

    @JvmStatic
    external fun nativeVADIsModelLoaded(handle: Long): Boolean

    @JvmStatic
    external fun nativeVADUnloadModel(handle: Long): Int

    @JvmStatic
    external fun nativeVADProcess(
        handle: Long,
        audioSamples: FloatArray,
        sampleRate: Int
    ): NativeVADResult?

    @JvmStatic
    external fun nativeVADDetectSegments(
        handle: Long,
        audioSamples: FloatArray,
        sampleRate: Int
    ): String?

    @JvmStatic
    external fun nativeVADReset(handle: Long)

    // =============================================================================
    // Embeddings
    // =============================================================================

    @JvmStatic
    external fun nativeEmbedLoadModel(handle: Long, modelPath: String, configJson: String?): Int

    @JvmStatic
    external fun nativeEmbedIsModelLoaded(handle: Long): Boolean

    @JvmStatic
    external fun nativeEmbedUnloadModel(handle: Long): Int

    @JvmStatic
    external fun nativeEmbedText(handle: Long, text: String): FloatArray?

    @JvmStatic
    external fun nativeEmbedGetDimensions(handle: Long): Int

    // =============================================================================
    // Speaker Diarization
    // =============================================================================

    @JvmStatic
    external fun nativeDiarizeLoadModel(handle: Long, modelPath: String, configJson: String?): Int

    @JvmStatic
    external fun nativeDiarizeIsModelLoaded(handle: Long): Boolean

    @JvmStatic
    external fun nativeDiarizeUnloadModel(handle: Long): Int

    @JvmStatic
    external fun nativeDiarize(
        handle: Long,
        audioSamples: FloatArray,
        sampleRate: Int,
        minSpeakers: Int,
        maxSpeakers: Int
    ): String?

    @JvmStatic
    external fun nativeDiarizeCancel(handle: Long)

    // =============================================================================
    // Utility
    // =============================================================================

    @JvmStatic
    external fun nativeGetLastError(): String

    @JvmStatic
    external fun nativeGetVersion(): String

    @JvmStatic
    external fun nativeExtractArchive(archivePath: String, destDir: String): Int

}
