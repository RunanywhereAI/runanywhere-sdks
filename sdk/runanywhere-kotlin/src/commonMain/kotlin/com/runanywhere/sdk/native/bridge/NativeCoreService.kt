package com.runanywhere.sdk.native.bridge

/**
 * NativeCoreService - Interface for all RunAnywhere Core native backends.
 *
 * This is the generic interface that ALL native backends (ONNX, TFLite, CoreML, etc.)
 * must implement. It provides a unified API for ML capabilities across different runtimes.
 *
 * This is the Kotlin equivalent of UnifiedFrameworkAdapter in the Swift SDK.
 *
 * Usage:
 * ```kotlin
 * // Create backend-specific implementation
 * val service: NativeCoreService = ONNXCoreService()  // or TFLiteCoreService, etc.
 * service.initialize()
 *
 * // Load STT model
 * service.loadSTTModel("/path/to/model", "zipformer")
 *
 * // Transcribe audio
 * val result = service.transcribe(audioSamples, 16000)
 *
 * // Cleanup
 * service.destroy()
 * ```
 */
interface NativeCoreService {

    /**
     * Initialize the native backend.
     * Must be called before any other operations.
     *
     * @param configJson Optional JSON configuration
     * @throws NativeBridgeException if initialization fails
     */
    suspend fun initialize(configJson: String? = null)

    /**
     * Check if the backend is initialized.
     */
    val isInitialized: Boolean

    /**
     * Get supported capabilities.
     */
    val supportedCapabilities: List<NativeCapability>

    /**
     * Check if a specific capability is supported.
     */
    fun supportsCapability(capability: NativeCapability): Boolean

    /**
     * Get device type being used.
     */
    val deviceType: NativeDeviceType

    /**
     * Get current memory usage in bytes.
     */
    val memoryUsage: Long

    // =============================================================================
    // STT Operations
    // =============================================================================

    /**
     * Load an STT model.
     *
     * @param modelPath Path to the model directory
     * @param modelType Model type (e.g., "whisper", "zipformer", "paraformer")
     * @param configJson Optional JSON configuration
     * @throws NativeBridgeException if loading fails
     */
    suspend fun loadSTTModel(modelPath: String, modelType: String, configJson: String? = null)

    /**
     * Check if STT model is loaded.
     */
    val isSTTModelLoaded: Boolean

    /**
     * Unload STT model.
     */
    suspend fun unloadSTTModel()

    /**
     * Transcribe audio (batch mode).
     *
     * @param audioSamples Float32 audio samples [-1.0, 1.0]
     * @param sampleRate Sample rate (e.g., 16000)
     * @param language ISO 639-1 language code or null for auto-detect
     * @return Transcription result as JSON string
     * @throws NativeBridgeException if transcription fails
     */
    suspend fun transcribe(
        audioSamples: FloatArray,
        sampleRate: Int,
        language: String? = null
    ): String

    /**
     * Check if STT supports streaming.
     */
    val supportsSTTStreaming: Boolean

    // =============================================================================
    // TTS Operations
    // =============================================================================

    /**
     * Load a TTS model.
     *
     * @param modelPath Path to the model directory
     * @param modelType Model type (e.g., "piper", "vits")
     * @param configJson Optional JSON configuration
     * @throws NativeBridgeException if loading fails
     */
    suspend fun loadTTSModel(modelPath: String, modelType: String, configJson: String? = null)

    /**
     * Check if TTS model is loaded.
     */
    val isTTSModelLoaded: Boolean

    /**
     * Unload TTS model.
     */
    suspend fun unloadTTSModel()

    /**
     * Synthesize speech from text.
     *
     * @param text Text to synthesize
     * @param voiceId Voice identifier or null for default
     * @param speedRate Speed rate (1.0 = normal)
     * @param pitchShift Pitch shift in semitones
     * @return NativeTTSSynthesisResult with audio samples and sample rate
     * @throws NativeBridgeException if synthesis fails
     */
    suspend fun synthesize(
        text: String,
        voiceId: String? = null,
        speedRate: Float = 1.0f,
        pitchShift: Float = 0.0f
    ): NativeTTSSynthesisResult

    /**
     * Get available TTS voices as JSON array.
     */
    suspend fun getVoices(): String

    // =============================================================================
    // VAD Operations
    // =============================================================================

    /**
     * Load a VAD model.
     *
     * @param modelPath Path to the model (or null for built-in)
     * @param configJson Optional JSON configuration
     */
    suspend fun loadVADModel(modelPath: String? = null, configJson: String? = null)

    /**
     * Check if VAD model is loaded.
     */
    val isVADModelLoaded: Boolean

    /**
     * Unload VAD model.
     */
    suspend fun unloadVADModel()

    /**
     * Process audio and detect speech.
     *
     * @param audioSamples Float32 audio samples
     * @param sampleRate Sample rate
     * @return NativeVADResult with speech status and probability
     */
    suspend fun processVAD(audioSamples: FloatArray, sampleRate: Int): NativeVADResult

    /**
     * Detect speech segments in audio.
     *
     * @param audioSamples Float32 audio samples
     * @param sampleRate Sample rate
     * @return JSON array of speech segments
     */
    suspend fun detectVADSegments(audioSamples: FloatArray, sampleRate: Int): String

    // =============================================================================
    // Embedding Operations
    // =============================================================================

    /**
     * Load an embedding model.
     *
     * @param modelPath Path to the model
     * @param configJson Optional JSON configuration
     */
    suspend fun loadEmbeddingModel(modelPath: String, configJson: String? = null)

    /**
     * Check if embedding model is loaded.
     */
    val isEmbeddingModelLoaded: Boolean

    /**
     * Unload embedding model.
     */
    suspend fun unloadEmbeddingModel()

    /**
     * Generate embedding for text.
     *
     * @param text Text to embed
     * @return Float array of embedding values
     */
    suspend fun embed(text: String): FloatArray

    /**
     * Get embedding dimensions.
     */
    val embeddingDimensions: Int

    // =============================================================================
    // Lifecycle
    // =============================================================================

    /**
     * Destroy the backend and release all resources.
     */
    fun destroy()
}
