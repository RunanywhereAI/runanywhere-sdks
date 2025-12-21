package com.runanywhere.sdk.core.whispercpp

import com.runanywhere.sdk.native.bridge.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/**
 * WhisperCPP implementation of NativeCoreService.
 *
 * This provides the whisper.cpp backend for RunAnywhere Core.
 * It wraps the JNI bridge (RunAnywhereBridge) and implements the generic
 * NativeCoreService interface.
 *
 * Thread Safety:
 * - All public methods are thread-safe via mutex
 * - Native operations run on IO dispatcher
 * - Handle is protected by mutex to prevent use-after-free
 *
 * Usage:
 * ```kotlin
 * val service = WhisperCPPCoreService()
 * service.initialize()
 *
 * // Load STT model (GGML whisper model)
 * service.loadSTTModel("/path/to/whisper-tiny.bin", "whisper")
 *
 * // Transcribe audio
 * val result = service.transcribe(audioSamples, 16000)
 *
 * // Cleanup
 * service.destroy()
 * ```
 */
class WhisperCPPCoreService : NativeCoreService {
    private var backendHandle: Long = 0
    private val mutex = Mutex()

    init {
        // Load unified JNI bridge on construction
        RunAnywhereBridge.loadLibrary()
    }

    // =============================================================================
    // Lifecycle
    // =============================================================================

    override suspend fun initialize(configJson: String?) {
        withContext(Dispatchers.IO) {
            mutex.withLock {
                if (backendHandle != 0L) {
                    // Already initialized
                    return@withContext
                }

                // Create WhisperCPP backend
                backendHandle = RunAnywhereBridge.nativeCreateBackend("whispercpp")
                if (backendHandle == 0L) {
                    throw NativeBridgeException(
                        NativeResultCode.ERROR_INIT_FAILED,
                        "Failed to create WhisperCPP backend"
                    )
                }

                // Initialize backend
                val result = NativeResultCode.fromValue(
                    RunAnywhereBridge.nativeInitialize(backendHandle, configJson)
                )
                if (!result.isSuccess) {
                    val error = RunAnywhereBridge.nativeGetLastError()
                    RunAnywhereBridge.nativeDestroy(backendHandle)
                    backendHandle = 0
                    throw NativeBridgeException(result, error.ifEmpty { "Initialization failed" })
                }
            }
        }
    }

    override val isInitialized: Boolean
        get() = backendHandle != 0L && RunAnywhereBridge.nativeIsInitialized(backendHandle)

    override val supportedCapabilities: List<NativeCapability>
        get() {
            if (backendHandle == 0L) return emptyList()
            return RunAnywhereBridge.nativeGetCapabilities(backendHandle)
                .toList()
                .mapNotNull { NativeCapability.fromValue(it) }
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
            if (backendHandle == 0L) return 0
            return RunAnywhereBridge.nativeGetMemoryUsage(backendHandle)
        }

    override fun destroy() {
        if (backendHandle != 0L) {
            RunAnywhereBridge.nativeDestroy(backendHandle)
            backendHandle = 0
        }
    }

    // =============================================================================
    // STT Operations (Primary capability for whisper.cpp)
    // =============================================================================

    override suspend fun loadSTTModel(modelPath: String, modelType: String, configJson: String?) {
        withContext(Dispatchers.IO) {
            mutex.withLock {
                ensureInitialized()
                val result = NativeResultCode.fromValue(
                    RunAnywhereBridge.nativeSTTLoadModel(backendHandle, modelPath, modelType, configJson)
                )
                if (!result.isSuccess) {
                    throw NativeBridgeException(result, RunAnywhereBridge.nativeGetLastError())
                }
            }
        }
    }

    override val isSTTModelLoaded: Boolean
        get() = backendHandle != 0L && RunAnywhereBridge.nativeSTTIsModelLoaded(backendHandle)

    override suspend fun unloadSTTModel() {
        withContext(Dispatchers.IO) {
            mutex.withLock {
                if (backendHandle != 0L) {
                    RunAnywhereBridge.nativeSTTUnloadModel(backendHandle)
                }
            }
        }
    }

    override suspend fun transcribe(
        audioSamples: FloatArray,
        sampleRate: Int,
        language: String?
    ): String {
        return withContext(Dispatchers.IO) {
            mutex.withLock {
                ensureInitialized()
                RunAnywhereBridge.nativeSTTTranscribe(
                    backendHandle,
                    audioSamples,
                    sampleRate,
                    language
                ) ?: throw NativeBridgeException(
                    NativeResultCode.ERROR_INFERENCE_FAILED,
                    RunAnywhereBridge.nativeGetLastError()
                )
            }
        }
    }

    override val supportsSTTStreaming: Boolean
        get() = backendHandle != 0L && RunAnywhereBridge.nativeSTTSupportsStreaming(backendHandle)

    // =============================================================================
    // TTS Operations (Not supported by whisper.cpp)
    // =============================================================================

    override suspend fun loadTTSModel(modelPath: String, modelType: String, configJson: String?) {
        throw UnsupportedOperationException("WhisperCPP does not support TTS")
    }

    override val isTTSModelLoaded: Boolean
        get() = false

    override suspend fun unloadTTSModel() {
        // No-op - TTS not supported
    }

    override suspend fun synthesize(
        text: String,
        voiceId: String?,
        speedRate: Float,
        pitchShift: Float
    ): NativeTTSSynthesisResult {
        throw UnsupportedOperationException("WhisperCPP does not support TTS")
    }

    override suspend fun getVoices(): String {
        return "[]" // No voices available
    }

    // =============================================================================
    // VAD Operations (Not supported by whisper.cpp standalone)
    // =============================================================================

    override suspend fun loadVADModel(modelPath: String?, configJson: String?) {
        throw UnsupportedOperationException("WhisperCPP does not support standalone VAD")
    }

    override val isVADModelLoaded: Boolean
        get() = false

    override suspend fun unloadVADModel() {
        // No-op - VAD not supported
    }

    override suspend fun processVAD(audioSamples: FloatArray, sampleRate: Int): NativeVADResult {
        throw UnsupportedOperationException("WhisperCPP does not support standalone VAD")
    }

    override suspend fun detectVADSegments(audioSamples: FloatArray, sampleRate: Int): String {
        throw UnsupportedOperationException("WhisperCPP does not support standalone VAD")
    }

    // =============================================================================
    // Embedding Operations (Not supported by whisper.cpp)
    // =============================================================================

    override suspend fun loadEmbeddingModel(modelPath: String, configJson: String?) {
        throw UnsupportedOperationException("WhisperCPP does not support embeddings")
    }

    override val isEmbeddingModelLoaded: Boolean
        get() = false

    override suspend fun unloadEmbeddingModel() {
        // No-op - Embeddings not supported
    }

    override suspend fun embed(text: String): FloatArray {
        throw UnsupportedOperationException("WhisperCPP does not support embeddings")
    }

    override val embeddingDimensions: Int
        get() = 0

    // =============================================================================
    // Private Helpers
    // =============================================================================

    private fun ensureInitialized() {
        if (backendHandle == 0L) {
            throw NativeBridgeException(
                NativeResultCode.ERROR_INVALID_HANDLE,
                "Backend not initialized. Call initialize() first."
            )
        }
    }

    companion object {
        /**
         * Check if WhisperCPP backend is available.
         */
        fun isAvailable(): Boolean {
            RunAnywhereBridge.loadLibrary()
            return RunAnywhereBridge.nativeGetAvailableBackends().contains("whispercpp")
        }

        /**
         * Get the library version.
         */
        fun getVersion(): String {
            RunAnywhereBridge.loadLibrary()
            return RunAnywhereBridge.nativeGetVersion()
        }
    }
}
