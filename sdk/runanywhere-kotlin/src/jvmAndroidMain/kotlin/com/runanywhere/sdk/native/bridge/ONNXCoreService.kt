package com.runanywhere.sdk.native.bridge

import com.runanywhere.sdk.foundation.SDKLogger
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlin.concurrent.Volatile

/**
 * ONNX Runtime implementation of NativeCoreService.
 *
 * Uses the unified RunAnywhere JNI bridge to access ONNX Runtime backend.
 * Supports STT, TTS, VAD, and Embeddings capabilities.
 *
 * Usage:
 * ```kotlin
 * val service = ONNXCoreService()
 * service.initialize()
 * service.loadSTTModel("/path/to/model", "whisper")
 * val result = service.transcribe(audioSamples, 16000)
 * service.destroy()
 * ```
 *
 * Thread Safety:
 * - All operations use synchronized blocks to prevent concurrent access
 * - Operations are dispatched to IO dispatcher for JNI calls
 */
class ONNXCoreService : NativeCoreService {

    private val logger = SDKLogger("ONNXCoreService")

    @Volatile
    private var backendHandle: Long = 0

    @Volatile
    private var _isInitialized: Boolean = false

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

            logger.info("Creating ONNX backend...")
            backendHandle = RunAnywhereBridge.nativeCreateBackend("onnx")

            if (backendHandle == 0L) {
                throw NativeBridgeException(
                    NativeResultCode.ERROR_INIT_FAILED,
                    "Failed to create ONNX backend"
                )
            }

            val resultCode = RunAnywhereBridge.nativeInitialize(backendHandle, configJson)
            val result = NativeResultCode.fromValue(resultCode)

            if (!result.isSuccess) {
                RunAnywhereBridge.nativeDestroy(backendHandle)
                backendHandle = 0
                throw NativeBridgeException(result, "Failed to initialize ONNX backend")
            }

            _isInitialized = true
            logger.info("✅ ONNX backend initialized")
        }
    }

    override fun destroy() {
        synchronized(lock) {
            if (backendHandle != 0L) {
                logger.info("Destroying ONNX backend...")
                RunAnywhereBridge.nativeDestroy(backendHandle)
                backendHandle = 0
                _isInitialized = false
                logger.info("✅ ONNX backend destroyed")
            }
        }
    }

    // =============================================================================
    // STT Operations
    // =============================================================================

    override val isSTTModelLoaded: Boolean
        get() = backendHandle != 0L && RunAnywhereBridge.nativeSTTIsModelLoaded(backendHandle)

    override val supportsSTTStreaming: Boolean
        get() = backendHandle != 0L && RunAnywhereBridge.nativeSTTSupportsStreaming(backendHandle)

    override suspend fun loadSTTModel(
        modelPath: String,
        modelType: String,
        configJson: String?
    ) = withContext(Dispatchers.IO) {
        ensureInitialized()

        logger.info("Loading STT model: $modelPath (type: $modelType)")
        val resultCode = RunAnywhereBridge.nativeSTTLoadModel(
            backendHandle,
            modelPath,
            modelType,
            configJson
        )
        val result = NativeResultCode.fromValue(resultCode)

        if (!result.isSuccess) {
            throw NativeBridgeException(result, "Failed to load STT model: $modelPath")
        }
        logger.info("✅ STT model loaded")
    }

    override suspend fun unloadSTTModel() = withContext(Dispatchers.IO) {
        ensureInitialized()

        val resultCode = RunAnywhereBridge.nativeSTTUnloadModel(backendHandle)
        val result = NativeResultCode.fromValue(resultCode)

        if (!result.isSuccess) {
            throw NativeBridgeException(result, "Failed to unload STT model")
        }
        logger.debug("STT model unloaded")
    }

    override suspend fun transcribe(
        audioSamples: FloatArray,
        sampleRate: Int,
        language: String?
    ): String = withContext(Dispatchers.IO) {
        ensureInitialized()
        ensureSTTModelLoaded()

        val result = RunAnywhereBridge.nativeSTTTranscribe(
            backendHandle,
            audioSamples,
            sampleRate,
            language
        )

        result ?: throw NativeBridgeException(
            NativeResultCode.ERROR_INFERENCE_FAILED,
            "Transcription failed: ${RunAnywhereBridge.nativeGetLastError()}"
        )
    }

    // =============================================================================
    // TTS Operations
    // =============================================================================

    override val isTTSModelLoaded: Boolean
        get() = backendHandle != 0L && RunAnywhereBridge.nativeTTSIsModelLoaded(backendHandle)

    override suspend fun loadTTSModel(
        modelPath: String,
        modelType: String,
        configJson: String?
    ) = withContext(Dispatchers.IO) {
        ensureInitialized()

        logger.info("Loading TTS model: $modelPath (type: $modelType)")
        val resultCode = RunAnywhereBridge.nativeTTSLoadModel(
            backendHandle,
            modelPath,
            modelType,
            configJson
        )
        val result = NativeResultCode.fromValue(resultCode)

        if (!result.isSuccess) {
            throw NativeBridgeException(result, "Failed to load TTS model: $modelPath")
        }
        logger.info("✅ TTS model loaded")
    }

    override suspend fun unloadTTSModel() = withContext(Dispatchers.IO) {
        ensureInitialized()

        val resultCode = RunAnywhereBridge.nativeTTSUnloadModel(backendHandle)
        val result = NativeResultCode.fromValue(resultCode)

        if (!result.isSuccess) {
            throw NativeBridgeException(result, "Failed to unload TTS model")
        }
        logger.debug("TTS model unloaded")
    }

    override suspend fun synthesize(
        text: String,
        voiceId: String?,
        speedRate: Float,
        pitchShift: Float
    ): NativeTTSSynthesisResult = withContext(Dispatchers.IO) {
        ensureInitialized()
        ensureTTSModelLoaded()

        val result = RunAnywhereBridge.nativeTTSSynthesize(
            backendHandle,
            text,
            voiceId,
            speedRate,
            pitchShift
        )

        result ?: throw NativeBridgeException(
            NativeResultCode.ERROR_INFERENCE_FAILED,
            "TTS synthesis failed: ${RunAnywhereBridge.nativeGetLastError()}"
        )
    }

    override suspend fun getVoices(): String = withContext(Dispatchers.IO) {
        ensureInitialized()
        RunAnywhereBridge.nativeTTSGetVoices(backendHandle)
    }

    // =============================================================================
    // VAD Operations
    // =============================================================================

    override val isVADModelLoaded: Boolean
        get() = backendHandle != 0L && RunAnywhereBridge.nativeVADIsModelLoaded(backendHandle)

    override suspend fun loadVADModel(
        modelPath: String?,
        configJson: String?
    ) = withContext(Dispatchers.IO) {
        ensureInitialized()

        logger.info("Loading VAD model: ${modelPath ?: "built-in"}")
        val resultCode = RunAnywhereBridge.nativeVADLoadModel(
            backendHandle,
            modelPath,
            configJson
        )
        val result = NativeResultCode.fromValue(resultCode)

        if (!result.isSuccess) {
            throw NativeBridgeException(result, "Failed to load VAD model")
        }
        logger.info("✅ VAD model loaded")
    }

    override suspend fun unloadVADModel() = withContext(Dispatchers.IO) {
        ensureInitialized()

        val resultCode = RunAnywhereBridge.nativeVADUnloadModel(backendHandle)
        val result = NativeResultCode.fromValue(resultCode)

        if (!result.isSuccess) {
            throw NativeBridgeException(result, "Failed to unload VAD model")
        }
        logger.debug("VAD model unloaded")
    }

    override suspend fun processVAD(
        audioSamples: FloatArray,
        sampleRate: Int
    ): NativeVADResult = withContext(Dispatchers.IO) {
        ensureInitialized()
        ensureVADModelLoaded()

        val result = RunAnywhereBridge.nativeVADProcess(
            backendHandle,
            audioSamples,
            sampleRate
        )

        result ?: throw NativeBridgeException(
            NativeResultCode.ERROR_INFERENCE_FAILED,
            "VAD processing failed: ${RunAnywhereBridge.nativeGetLastError()}"
        )
    }

    override suspend fun detectVADSegments(
        audioSamples: FloatArray,
        sampleRate: Int
    ): String = withContext(Dispatchers.IO) {
        ensureInitialized()
        ensureVADModelLoaded()

        val result = RunAnywhereBridge.nativeVADDetectSegments(
            backendHandle,
            audioSamples,
            sampleRate
        )

        result ?: throw NativeBridgeException(
            NativeResultCode.ERROR_INFERENCE_FAILED,
            "VAD segment detection failed: ${RunAnywhereBridge.nativeGetLastError()}"
        )
    }

    // =============================================================================
    // Embedding Operations
    // =============================================================================

    override val isEmbeddingModelLoaded: Boolean
        get() = backendHandle != 0L && RunAnywhereBridge.nativeEmbedIsModelLoaded(backendHandle)

    override val embeddingDimensions: Int
        get() {
            if (backendHandle == 0L) return 0
            return RunAnywhereBridge.nativeEmbedGetDimensions(backendHandle)
        }

    override suspend fun loadEmbeddingModel(
        modelPath: String,
        configJson: String?
    ) = withContext(Dispatchers.IO) {
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
        ensureEmbeddingModelLoaded()

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
                "ONNX backend not initialized. Call initialize() first."
            )
        }
    }

    private fun ensureSTTModelLoaded() {
        if (!isSTTModelLoaded) {
            throw NativeBridgeException(
                NativeResultCode.ERROR_MODEL_LOAD_FAILED,
                "STT model not loaded. Call loadSTTModel() first."
            )
        }
    }

    private fun ensureTTSModelLoaded() {
        if (!isTTSModelLoaded) {
            throw NativeBridgeException(
                NativeResultCode.ERROR_MODEL_LOAD_FAILED,
                "TTS model not loaded. Call loadTTSModel() first."
            )
        }
    }

    private fun ensureVADModelLoaded() {
        if (!isVADModelLoaded) {
            throw NativeBridgeException(
                NativeResultCode.ERROR_MODEL_LOAD_FAILED,
                "VAD model not loaded. Call loadVADModel() first."
            )
        }
    }

    private fun ensureEmbeddingModelLoaded() {
        if (!isEmbeddingModelLoaded) {
            throw NativeBridgeException(
                NativeResultCode.ERROR_MODEL_LOAD_FAILED,
                "Embedding model not loaded. Call loadEmbeddingModel() first."
            )
        }
    }
}
