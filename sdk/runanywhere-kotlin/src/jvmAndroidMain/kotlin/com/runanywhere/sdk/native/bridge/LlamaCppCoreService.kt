package com.runanywhere.sdk.native.bridge

import com.runanywhere.sdk.foundation.SDKLogger
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlin.concurrent.Volatile

/**
 * LlamaCPP implementation of NativeCoreService.
 *
 * Uses the unified RunAnywhere JNI bridge to access LlamaCPP backend.
 * Primarily supports TEXT_GENERATION capability (LLM).
 *
 * Usage:
 * ```kotlin
 * val service = LlamaCppCoreService()
 * service.initialize()
 * service.loadTextModel("/path/to/model.gguf")
 * val result = service.generate("Hello, world!", null, 256, 0.7f)
 * service.destroy()
 * ```
 *
 * Thread Safety:
 * - All operations use synchronized blocks to prevent concurrent access
 * - Operations are dispatched to IO dispatcher for JNI calls
 */
class LlamaCppCoreService : NativeCoreService {

    private val logger = SDKLogger("LlamaCppCoreService")

    @Volatile
    private var backendHandle: Long = 0

    @Volatile
    private var _isInitialized: Boolean = false

    @Volatile
    private var _isTextModelLoaded: Boolean = false

    private val lock = Any()

    override val isInitialized: Boolean
        get() = _isInitialized

    override val supportedCapabilities: List<NativeCapability>
        get() {
            if (backendHandle == 0L) return emptyList()
            val caps = RunAnywhereBridge.nativeGetCapabilities(backendHandle)
            return caps.toList().mapNotNull { NativeCapability.fromValue(it) }
        }

    override fun supportsCapability(capability: NativeCapability): Boolean {
        if (backendHandle == 0L) return false
        return RunAnywhereBridge.nativeSupportsCapability(backendHandle, capability.value)
    }

    override val deviceType: NativeDeviceType
        get() {
            if (backendHandle == 0L) return NativeDeviceType.CPU
            return NativeDeviceType.fromValue(RunAnywhereBridge.nativeGetDevice(backendHandle))
        }

    override val memoryUsage: Long
        get() {
            if (backendHandle == 0L) return 0L
            return RunAnywhereBridge.nativeGetMemoryUsage(backendHandle)
        }

    // =============================================================================
    // Lifecycle
    // =============================================================================

    override suspend fun initialize(configJson: String?) = withContext(Dispatchers.IO) {
        synchronized(lock) {
            if (_isInitialized) {
                logger.debug("Already initialized")
                return@synchronized
            }

            // Ensure library is loaded
            RunAnywhereBridge.loadLibrary()

            logger.info("Creating LlamaCPP backend...")
            backendHandle = RunAnywhereBridge.nativeCreateBackend("llamacpp")

            if (backendHandle == 0L) {
                throw NativeBridgeException(
                    NativeResultCode.ERROR_INIT_FAILED,
                    "Failed to create LlamaCPP backend"
                )
            }

            val resultCode = RunAnywhereBridge.nativeInitialize(backendHandle, configJson)
            val result = NativeResultCode.fromValue(resultCode)

            if (!result.isSuccess) {
                RunAnywhereBridge.nativeDestroy(backendHandle)
                backendHandle = 0
                throw NativeBridgeException(result, "Failed to initialize LlamaCPP backend")
            }

            _isInitialized = true
            logger.info("✅ LlamaCPP backend initialized")
        }
    }

    override fun destroy() {
        synchronized(lock) {
            if (backendHandle != 0L) {
                logger.info("Destroying LlamaCPP backend...")
                RunAnywhereBridge.nativeDestroy(backendHandle)
                backendHandle = 0
                _isInitialized = false
                _isTextModelLoaded = false
                logger.info("✅ LlamaCPP backend destroyed")
            }
        }
    }

    // =============================================================================
    // Text Generation (LLM) Operations
    // =============================================================================

    /**
     * Check if a text generation model is loaded
     */
    val isTextModelLoaded: Boolean
        get() = backendHandle != 0L && RunAnywhereBridge.nativeTextIsModelLoaded(backendHandle)

    /**
     * Load a text generation model (GGUF format)
     *
     * @param modelPath Path to the model file
     * @param configJson Optional JSON configuration (e.g., context size, GPU layers)
     */
    suspend fun loadTextModel(
        modelPath: String,
        configJson: String? = null
    ) = withContext(Dispatchers.IO) {
        ensureInitialized()

        logger.info("Loading text model: $modelPath")
        val resultCode = RunAnywhereBridge.nativeTextLoadModel(
            backendHandle,
            modelPath,
            configJson
        )
        val result = NativeResultCode.fromValue(resultCode)

        if (!result.isSuccess) {
            throw NativeBridgeException(result, "Failed to load text model: $modelPath")
        }

        _isTextModelLoaded = true
        logger.info("✅ Text model loaded")
    }

    /**
     * Unload the current text generation model
     */
    suspend fun unloadTextModel() = withContext(Dispatchers.IO) {
        ensureInitialized()

        val resultCode = RunAnywhereBridge.nativeTextUnloadModel(backendHandle)
        val result = NativeResultCode.fromValue(resultCode)

        if (!result.isSuccess) {
            throw NativeBridgeException(result, "Failed to unload text model")
        }

        _isTextModelLoaded = false
        logger.debug("Text model unloaded")
    }

    /**
     * Generate text from a prompt (synchronous/batch mode)
     *
     * @param prompt The input prompt
     * @param systemPrompt Optional system prompt
     * @param maxTokens Maximum tokens to generate
     * @param temperature Sampling temperature (0.0 - 2.0)
     * @return Generated text as JSON string with result metadata
     */
    suspend fun generate(
        prompt: String,
        systemPrompt: String? = null,
        maxTokens: Int = 256,
        temperature: Float = 0.7f
    ): String = withContext(Dispatchers.IO) {
        ensureInitialized()
        ensureTextModelLoaded()

        val result = RunAnywhereBridge.nativeTextGenerate(
            backendHandle,
            prompt,
            systemPrompt,
            maxTokens,
            temperature
        )

        result ?: throw NativeBridgeException(
            NativeResultCode.ERROR_INFERENCE_FAILED,
            "Text generation failed: ${RunAnywhereBridge.nativeGetLastError()}"
        )
    }

    /**
     * Cancel an ongoing text generation
     */
    fun cancelGeneration() {
        if (backendHandle != 0L) {
            RunAnywhereBridge.nativeTextCancel(backendHandle)
        }
    }

    /**
     * Get backend info as JSON
     */
    fun getBackendInfo(): String {
        if (backendHandle == 0L) return "{}"
        return RunAnywhereBridge.nativeGetBackendInfo(backendHandle)
    }

    // =============================================================================
    // STT Operations (Not supported by LlamaCPP - delegate to stub)
    // =============================================================================

    override val isSTTModelLoaded: Boolean = false
    override val supportsSTTStreaming: Boolean = false

    override suspend fun loadSTTModel(modelPath: String, modelType: String, configJson: String?) {
        throw NativeBridgeException(
            NativeResultCode.ERROR_NOT_IMPLEMENTED,
            "STT not supported by LlamaCPP backend. Use ONNX backend for STT."
        )
    }

    override suspend fun unloadSTTModel() {
        // No-op
    }

    override suspend fun transcribe(audioSamples: FloatArray, sampleRate: Int, language: String?): String {
        throw NativeBridgeException(
            NativeResultCode.ERROR_NOT_IMPLEMENTED,
            "STT not supported by LlamaCPP backend. Use ONNX backend for STT."
        )
    }

    // =============================================================================
    // TTS Operations (Not supported by LlamaCPP - delegate to stub)
    // =============================================================================

    override val isTTSModelLoaded: Boolean = false

    override suspend fun loadTTSModel(modelPath: String, modelType: String, configJson: String?) {
        throw NativeBridgeException(
            NativeResultCode.ERROR_NOT_IMPLEMENTED,
            "TTS not supported by LlamaCPP backend. Use ONNX backend for TTS."
        )
    }

    override suspend fun unloadTTSModel() {
        // No-op
    }

    override suspend fun synthesize(
        text: String,
        voiceId: String?,
        speedRate: Float,
        pitchShift: Float
    ): NativeTTSSynthesisResult {
        throw NativeBridgeException(
            NativeResultCode.ERROR_NOT_IMPLEMENTED,
            "TTS not supported by LlamaCPP backend. Use ONNX backend for TTS."
        )
    }

    override suspend fun getVoices(): String = "[]"

    // =============================================================================
    // VAD Operations (Not supported by LlamaCPP - delegate to stub)
    // =============================================================================

    override val isVADModelLoaded: Boolean = false

    override suspend fun loadVADModel(modelPath: String?, configJson: String?) {
        throw NativeBridgeException(
            NativeResultCode.ERROR_NOT_IMPLEMENTED,
            "VAD not supported by LlamaCPP backend. Use ONNX backend for VAD."
        )
    }

    override suspend fun unloadVADModel() {
        // No-op
    }

    override suspend fun processVAD(audioSamples: FloatArray, sampleRate: Int): NativeVADResult {
        throw NativeBridgeException(
            NativeResultCode.ERROR_NOT_IMPLEMENTED,
            "VAD not supported by LlamaCPP backend. Use ONNX backend for VAD."
        )
    }

    override suspend fun detectVADSegments(audioSamples: FloatArray, sampleRate: Int): String {
        throw NativeBridgeException(
            NativeResultCode.ERROR_NOT_IMPLEMENTED,
            "VAD not supported by LlamaCPP backend. Use ONNX backend for VAD."
        )
    }

    // =============================================================================
    // Embedding Operations (LlamaCPP can do embeddings with embedding models)
    // =============================================================================

    override val isEmbeddingModelLoaded: Boolean
        get() = backendHandle != 0L && RunAnywhereBridge.nativeEmbedIsModelLoaded(backendHandle)

    override val embeddingDimensions: Int
        get() {
            if (backendHandle == 0L) return 0
            return RunAnywhereBridge.nativeEmbedGetDimensions(backendHandle)
        }

    override suspend fun loadEmbeddingModel(modelPath: String, configJson: String?) =
        withContext(Dispatchers.IO) {
            ensureInitialized()

            logger.info("Loading embedding model: $modelPath")
            val resultCode = RunAnywhereBridge.nativeEmbedLoadModel(
                backendHandle,
                modelPath,
                configJson
            )
            val result = NativeResultCode.fromValue(resultCode)

            if (!result.isSuccess) {
                throw NativeBridgeException(result, "Failed to load embedding model: $modelPath")
            }
            logger.info("✅ Embedding model loaded")
        }

    override suspend fun unloadEmbeddingModel() = withContext(Dispatchers.IO) {
        ensureInitialized()

        val resultCode = RunAnywhereBridge.nativeEmbedUnloadModel(backendHandle)
        val result = NativeResultCode.fromValue(resultCode)

        if (!result.isSuccess) {
            throw NativeBridgeException(result, "Failed to unload embedding model")
        }
        logger.debug("Embedding model unloaded")
    }

    override suspend fun embed(text: String): FloatArray = withContext(Dispatchers.IO) {
        ensureInitialized()

        if (!isEmbeddingModelLoaded) {
            throw NativeBridgeException(
                NativeResultCode.ERROR_MODEL_LOAD_FAILED,
                "Embedding model not loaded. Call loadEmbeddingModel() first."
            )
        }

        val result = RunAnywhereBridge.nativeEmbedText(backendHandle, text)

        result ?: throw NativeBridgeException(
            NativeResultCode.ERROR_INFERENCE_FAILED,
            "Embedding failed: ${RunAnywhereBridge.nativeGetLastError()}"
        )
    }

    // =============================================================================
    // Private Helpers
    // =============================================================================

    private fun ensureInitialized() {
        if (!_isInitialized || backendHandle == 0L) {
            throw NativeBridgeException(
                NativeResultCode.ERROR_INVALID_HANDLE,
                "LlamaCPP backend not initialized. Call initialize() first."
            )
        }
    }

    private fun ensureTextModelLoaded() {
        if (!isTextModelLoaded) {
            throw NativeBridgeException(
                NativeResultCode.ERROR_MODEL_LOAD_FAILED,
                "Text model not loaded. Call loadTextModel() first."
            )
        }
    }
}
