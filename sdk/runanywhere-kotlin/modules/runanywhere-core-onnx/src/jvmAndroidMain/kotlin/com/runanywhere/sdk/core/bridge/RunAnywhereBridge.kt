package com.runanywhere.sdk.core.bridge

/**
 * RunAnywhere Native Bridge
 *
 * This object provides JNI bindings to the RunAnywhere Core C API (runanywhere_bridge.h).
 * It serves as the low-level interface to native ML capabilities.
 *
 * This is the Kotlin equivalent of CRunAnywhereONNX in the Swift SDK.
 *
 * Thread Safety:
 * - All methods are thread-safe at the C API level
 * - Handles are opaque pointers managed by native code
 * - Stream handles must be destroyed on the same thread they were created (recommended)
 */
object RunAnywhereBridge {

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
                System.loadLibrary("onnxruntime")
            } catch (e: UnsatisfiedLinkError) {
                // May already be loaded
            }

            isLibraryLoaded = true
        } catch (e: UnsatisfiedLinkError) {
            throw RuntimeException("Failed to load RunAnywhere native library", e)
        }
    }

    /**
     * Check if the native library is loaded.
     */
    fun isLoaded(): Boolean = isLibraryLoaded

    // =============================================================================
    // Backend Lifecycle
    // =============================================================================

    /**
     * Get list of available backend names.
     */
    @JvmStatic
    external fun nativeGetAvailableBackends(): Array<String>

    /**
     * Create a new backend instance.
     * @param backendName Name of the backend (e.g., "onnx")
     * @return Handle to the backend (0 on failure)
     */
    @JvmStatic
    external fun nativeCreateBackend(backendName: String): Long

    /**
     * Initialize a backend with optional JSON configuration.
     * @param handle Backend handle
     * @param configJson Optional JSON configuration string
     * @return Result code (0 = success)
     */
    @JvmStatic
    external fun nativeInitialize(handle: Long, configJson: String?): Int

    /**
     * Check if backend is initialized.
     */
    @JvmStatic
    external fun nativeIsInitialized(handle: Long): Boolean

    /**
     * Destroy a backend and release resources.
     */
    @JvmStatic
    external fun nativeDestroy(handle: Long)

    /**
     * Get backend info as JSON string.
     */
    @JvmStatic
    external fun nativeGetBackendInfo(handle: Long): String

    /**
     * Check if backend supports a specific capability.
     */
    @JvmStatic
    external fun nativeSupportsCapability(handle: Long, capability: Int): Boolean

    /**
     * Get all supported capabilities.
     * @return Array of capability type integers
     */
    @JvmStatic
    external fun nativeGetCapabilities(handle: Long): IntArray

    /**
     * Get the device type being used.
     */
    @JvmStatic
    external fun nativeGetDevice(handle: Long): Int

    /**
     * Get current memory usage in bytes.
     */
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

    /**
     * Generate text synchronously.
     * @return JSON result string
     */
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

    /**
     * Transcribe audio in batch mode.
     * @param audioSamples Float32 audio samples [-1.0, 1.0]
     * @param sampleRate Sample rate (e.g., 16000)
     * @param language ISO 639-1 language code or null for auto-detect
     * @return JSON result string
     */
    @JvmStatic
    external fun nativeSTTTranscribe(
        handle: Long,
        audioSamples: FloatArray,
        sampleRate: Int,
        language: String?
    ): String?

    @JvmStatic
    external fun nativeSTTSupportsStreaming(handle: Long): Boolean

    /**
     * Create a streaming STT session.
     * @return Stream handle (0 on failure)
     */
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

    /**
     * Synthesize speech from text.
     * @return TTSSynthesisResult with audio samples and sample rate
     */
    @JvmStatic
    external fun nativeTTSSynthesize(
        handle: Long,
        text: String,
        voiceId: String?,
        speedRate: Float,
        pitchShift: Float
    ): TTSSynthesisResult?

    @JvmStatic
    external fun nativeTTSSupportsStreaming(handle: Long): Boolean

    /**
     * Get available voices as JSON array.
     */
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

    /**
     * Process audio and detect speech.
     * @return VADResult with speech status and probability
     */
    @JvmStatic
    external fun nativeVADProcess(
        handle: Long,
        audioSamples: FloatArray,
        sampleRate: Int
    ): VADResult?

    /**
     * Detect speech segments in audio.
     * @return JSON array of segments
     */
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

    /**
     * Generate embedding for text.
     * @return Float array of embedding values
     */
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

    /**
     * Perform speaker diarization on audio.
     * @return JSON result with speaker segments
     */
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

    /**
     * Get the last error message.
     */
    @JvmStatic
    external fun nativeGetLastError(): String

    /**
     * Get the library version.
     */
    @JvmStatic
    external fun nativeGetVersion(): String

    /**
     * Extract an archive (tar.bz2, tar.gz, zip) to destination directory.
     * @return Result code (0 = success)
     */
    @JvmStatic
    external fun nativeExtractArchive(archivePath: String, destDir: String): Int
}
