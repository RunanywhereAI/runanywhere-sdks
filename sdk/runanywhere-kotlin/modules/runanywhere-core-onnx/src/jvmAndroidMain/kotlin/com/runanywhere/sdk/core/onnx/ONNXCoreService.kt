package com.runanywhere.sdk.core.onnx

import com.runanywhere.sdk.native.bridge.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/**
 * ONNX Runtime implementation of NativeCoreService.
 *
 * This provides the ONNX Runtime backend for RunAnywhere Core.
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
 * val service = ONNXCoreService()
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
class ONNXCoreService : NativeCoreService {
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

                // Create backend
                backendHandle = RunAnywhereBridge.nativeCreateBackend("onnx")
                if (backendHandle == 0L) {
                    throw NativeBridgeException(
                        NativeResultCode.ERROR_INIT_FAILED,
                        "Failed to create ONNX backend"
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
    // STT Operations
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
    // TTS Operations
    // =============================================================================

    override suspend fun loadTTSModel(modelPath: String, modelType: String, configJson: String?) {
        withContext(Dispatchers.IO) {
            mutex.withLock {
                ensureInitialized()
                val result = NativeResultCode.fromValue(
                    RunAnywhereBridge.nativeTTSLoadModel(backendHandle, modelPath, modelType, configJson)
                )
                if (!result.isSuccess) {
                    throw NativeBridgeException(result, RunAnywhereBridge.nativeGetLastError())
                }
            }
        }
    }

    override val isTTSModelLoaded: Boolean
        get() = backendHandle != 0L && RunAnywhereBridge.nativeTTSIsModelLoaded(backendHandle)

    override suspend fun unloadTTSModel() {
        withContext(Dispatchers.IO) {
            mutex.withLock {
                if (backendHandle != 0L) {
                    RunAnywhereBridge.nativeTTSUnloadModel(backendHandle)
                }
            }
        }
    }

    override suspend fun synthesize(
        text: String,
        voiceId: String?,
        speedRate: Float,
        pitchShift: Float
    ): NativeTTSSynthesisResult {
        return withContext(Dispatchers.IO) {
            mutex.withLock {
                ensureInitialized()
                RunAnywhereBridge.nativeTTSSynthesize(
                    backendHandle,
                    text,
                    voiceId,
                    speedRate,
                    pitchShift
                ) ?: throw NativeBridgeException(
                    NativeResultCode.ERROR_INFERENCE_FAILED,
                    RunAnywhereBridge.nativeGetLastError()
                )
            }
        }
    }

    override suspend fun getVoices(): String {
        return withContext(Dispatchers.IO) {
            mutex.withLock {
                if (backendHandle == 0L) return@withContext "[]"
                RunAnywhereBridge.nativeTTSGetVoices(backendHandle)
            }
        }
    }

    // =============================================================================
    // VAD Operations
    // =============================================================================

    override suspend fun loadVADModel(modelPath: String?, configJson: String?) {
        withContext(Dispatchers.IO) {
            mutex.withLock {
                ensureInitialized()
                val result = NativeResultCode.fromValue(
                    RunAnywhereBridge.nativeVADLoadModel(backendHandle, modelPath, configJson)
                )
                if (!result.isSuccess) {
                    throw NativeBridgeException(result, RunAnywhereBridge.nativeGetLastError())
                }
            }
        }
    }

    override val isVADModelLoaded: Boolean
        get() = backendHandle != 0L && RunAnywhereBridge.nativeVADIsModelLoaded(backendHandle)

    override suspend fun unloadVADModel() {
        withContext(Dispatchers.IO) {
            mutex.withLock {
                if (backendHandle != 0L) {
                    RunAnywhereBridge.nativeVADUnloadModel(backendHandle)
                }
            }
        }
    }

    override suspend fun processVAD(audioSamples: FloatArray, sampleRate: Int): NativeVADResult {
        return withContext(Dispatchers.IO) {
            mutex.withLock {
                ensureInitialized()
                RunAnywhereBridge.nativeVADProcess(backendHandle, audioSamples, sampleRate)
                    ?: throw NativeBridgeException(
                        NativeResultCode.ERROR_INFERENCE_FAILED,
                        RunAnywhereBridge.nativeGetLastError()
                    )
            }
        }
    }

    override suspend fun detectVADSegments(audioSamples: FloatArray, sampleRate: Int): String {
        return withContext(Dispatchers.IO) {
            mutex.withLock {
                ensureInitialized()
                RunAnywhereBridge.nativeVADDetectSegments(backendHandle, audioSamples, sampleRate)
                    ?: throw NativeBridgeException(
                        NativeResultCode.ERROR_INFERENCE_FAILED,
                        RunAnywhereBridge.nativeGetLastError()
                    )
            }
        }
    }

    // =============================================================================
    // Embedding Operations
    // =============================================================================

    override suspend fun loadEmbeddingModel(modelPath: String, configJson: String?) {
        withContext(Dispatchers.IO) {
            mutex.withLock {
                ensureInitialized()
                val result = NativeResultCode.fromValue(
                    RunAnywhereBridge.nativeEmbedLoadModel(backendHandle, modelPath, configJson)
                )
                if (!result.isSuccess) {
                    throw NativeBridgeException(result, RunAnywhereBridge.nativeGetLastError())
                }
            }
        }
    }

    override val isEmbeddingModelLoaded: Boolean
        get() = backendHandle != 0L && RunAnywhereBridge.nativeEmbedIsModelLoaded(backendHandle)

    override suspend fun unloadEmbeddingModel() {
        withContext(Dispatchers.IO) {
            mutex.withLock {
                if (backendHandle != 0L) {
                    RunAnywhereBridge.nativeEmbedUnloadModel(backendHandle)
                }
            }
        }
    }

    override suspend fun embed(text: String): FloatArray {
        return withContext(Dispatchers.IO) {
            mutex.withLock {
                ensureInitialized()
                RunAnywhereBridge.nativeEmbedText(backendHandle, text)
                    ?: throw NativeBridgeException(
                        NativeResultCode.ERROR_INFERENCE_FAILED,
                        RunAnywhereBridge.nativeGetLastError()
                    )
            }
        }
    }

    override val embeddingDimensions: Int
        get() {
            if (backendHandle == 0L) return 0
            return RunAnywhereBridge.nativeEmbedGetDimensions(backendHandle)
        }

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
         * Get available backend names.
         */
        fun getAvailableBackends(): List<String> {
            RunAnywhereBridge.loadLibrary()
            return RunAnywhereBridge.nativeGetAvailableBackends().toList()
        }

        /**
         * Get the library version.
         */
        fun getVersion(): String {
            RunAnywhereBridge.loadLibrary()
            return RunAnywhereBridge.nativeGetVersion()
        }

        /**
         * Extract an archive to a destination directory.
         */
        fun extractArchive(archivePath: String, destDir: String): NativeResultCode {
            RunAnywhereBridge.loadLibrary()
            return NativeResultCode.fromValue(
                RunAnywhereBridge.nativeExtractArchive(archivePath, destDir)
            )
        }
    }
}
