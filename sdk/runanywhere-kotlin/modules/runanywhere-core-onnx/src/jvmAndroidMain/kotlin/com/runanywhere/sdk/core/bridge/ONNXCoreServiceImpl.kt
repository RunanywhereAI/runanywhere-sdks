package com.runanywhere.sdk.core.bridge

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/**
 * JVM/Android implementation of ONNXCoreService.
 *
 * This implementation wraps the JNI bridge (RunAnywhereBridge) and provides
 * a clean, coroutine-based API on top of native calls.
 *
 * Thread Safety:
 * - All public methods are thread-safe via mutex
 * - Native operations run on IO dispatcher
 * - Handle is protected by mutex to prevent use-after-free
 */
actual class ONNXCoreService {
    private var backendHandle: Long = 0
    private val mutex = Mutex()

    init {
        // Load native library on construction
        RunAnywhereBridge.loadLibrary()
    }

    // =============================================================================
    // Lifecycle
    // =============================================================================

    actual suspend fun initialize(configJson: String?) {
        withContext(Dispatchers.IO) {
            mutex.withLock {
                if (backendHandle != 0L) {
                    // Already initialized
                    return@withContext
                }

                // Create backend
                backendHandle = RunAnywhereBridge.nativeCreateBackend("onnx")
                if (backendHandle == 0L) {
                    throw RunAnywhereException(
                        ResultCode.ERROR_INIT_FAILED,
                        "Failed to create ONNX backend"
                    )
                }

                // Initialize backend
                val result = ResultCode.fromValue(
                    RunAnywhereBridge.nativeInitialize(backendHandle, configJson)
                )
                if (!result.isSuccess) {
                    val error = RunAnywhereBridge.nativeGetLastError()
                    RunAnywhereBridge.nativeDestroy(backendHandle)
                    backendHandle = 0
                    throw RunAnywhereException(result, error.ifEmpty { "Initialization failed" })
                }
            }
        }
    }

    actual val isInitialized: Boolean
        get() = backendHandle != 0L && RunAnywhereBridge.nativeIsInitialized(backendHandle)

    actual val supportedCapabilities: List<Capability>
        get() {
            if (backendHandle == 0L) return emptyList()
            return RunAnywhereBridge.nativeGetCapabilities(backendHandle)
                .mapNotNull { Capability.fromValue(it) }
        }

    actual fun supportsCapability(capability: Capability): Boolean {
        if (backendHandle == 0L) return false
        return RunAnywhereBridge.nativeSupportsCapability(backendHandle, capability.value)
    }

    actual val deviceType: DeviceType
        get() {
            if (backendHandle == 0L) return DeviceType.CPU
            return DeviceType.fromValue(RunAnywhereBridge.nativeGetDevice(backendHandle))
        }

    actual val memoryUsage: Long
        get() {
            if (backendHandle == 0L) return 0
            return RunAnywhereBridge.nativeGetMemoryUsage(backendHandle)
        }

    actual fun destroy() {
        if (backendHandle != 0L) {
            RunAnywhereBridge.nativeDestroy(backendHandle)
            backendHandle = 0
        }
    }

    // =============================================================================
    // STT Operations
    // =============================================================================

    actual suspend fun loadSTTModel(modelPath: String, modelType: String, configJson: String?) {
        withContext(Dispatchers.IO) {
            mutex.withLock {
                ensureInitialized()
                val result = ResultCode.fromValue(
                    RunAnywhereBridge.nativeSTTLoadModel(backendHandle, modelPath, modelType, configJson)
                )
                if (!result.isSuccess) {
                    throw RunAnywhereException(result, RunAnywhereBridge.nativeGetLastError())
                }
            }
        }
    }

    actual val isSTTModelLoaded: Boolean
        get() = backendHandle != 0L && RunAnywhereBridge.nativeSTTIsModelLoaded(backendHandle)

    actual suspend fun unloadSTTModel() {
        withContext(Dispatchers.IO) {
            mutex.withLock {
                if (backendHandle != 0L) {
                    RunAnywhereBridge.nativeSTTUnloadModel(backendHandle)
                }
            }
        }
    }

    actual suspend fun transcribe(
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
                ) ?: throw RunAnywhereException(
                    ResultCode.ERROR_INFERENCE_FAILED,
                    RunAnywhereBridge.nativeGetLastError()
                )
            }
        }
    }

    actual val supportsSTTStreaming: Boolean
        get() = backendHandle != 0L && RunAnywhereBridge.nativeSTTSupportsStreaming(backendHandle)

    // =============================================================================
    // TTS Operations
    // =============================================================================

    actual suspend fun loadTTSModel(modelPath: String, modelType: String, configJson: String?) {
        withContext(Dispatchers.IO) {
            mutex.withLock {
                ensureInitialized()
                val result = ResultCode.fromValue(
                    RunAnywhereBridge.nativeTTSLoadModel(backendHandle, modelPath, modelType, configJson)
                )
                if (!result.isSuccess) {
                    throw RunAnywhereException(result, RunAnywhereBridge.nativeGetLastError())
                }
            }
        }
    }

    actual val isTTSModelLoaded: Boolean
        get() = backendHandle != 0L && RunAnywhereBridge.nativeTTSIsModelLoaded(backendHandle)

    actual suspend fun unloadTTSModel() {
        withContext(Dispatchers.IO) {
            mutex.withLock {
                if (backendHandle != 0L) {
                    RunAnywhereBridge.nativeTTSUnloadModel(backendHandle)
                }
            }
        }
    }

    actual suspend fun synthesize(
        text: String,
        voiceId: String?,
        speedRate: Float,
        pitchShift: Float
    ): TTSSynthesisResult {
        return withContext(Dispatchers.IO) {
            mutex.withLock {
                ensureInitialized()
                RunAnywhereBridge.nativeTTSSynthesize(
                    backendHandle,
                    text,
                    voiceId,
                    speedRate,
                    pitchShift
                ) ?: throw RunAnywhereException(
                    ResultCode.ERROR_INFERENCE_FAILED,
                    RunAnywhereBridge.nativeGetLastError()
                )
            }
        }
    }

    actual suspend fun getVoices(): String {
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

    actual suspend fun loadVADModel(modelPath: String?, configJson: String?) {
        withContext(Dispatchers.IO) {
            mutex.withLock {
                ensureInitialized()
                val result = ResultCode.fromValue(
                    RunAnywhereBridge.nativeVADLoadModel(backendHandle, modelPath, configJson)
                )
                if (!result.isSuccess) {
                    throw RunAnywhereException(result, RunAnywhereBridge.nativeGetLastError())
                }
            }
        }
    }

    actual val isVADModelLoaded: Boolean
        get() = backendHandle != 0L && RunAnywhereBridge.nativeVADIsModelLoaded(backendHandle)

    actual suspend fun unloadVADModel() {
        withContext(Dispatchers.IO) {
            mutex.withLock {
                if (backendHandle != 0L) {
                    RunAnywhereBridge.nativeVADUnloadModel(backendHandle)
                }
            }
        }
    }

    actual suspend fun processVAD(audioSamples: FloatArray, sampleRate: Int): VADResult {
        return withContext(Dispatchers.IO) {
            mutex.withLock {
                ensureInitialized()
                RunAnywhereBridge.nativeVADProcess(backendHandle, audioSamples, sampleRate)
                    ?: throw RunAnywhereException(
                        ResultCode.ERROR_INFERENCE_FAILED,
                        RunAnywhereBridge.nativeGetLastError()
                    )
            }
        }
    }

    actual suspend fun detectVADSegments(audioSamples: FloatArray, sampleRate: Int): String {
        return withContext(Dispatchers.IO) {
            mutex.withLock {
                ensureInitialized()
                RunAnywhereBridge.nativeVADDetectSegments(backendHandle, audioSamples, sampleRate)
                    ?: throw RunAnywhereException(
                        ResultCode.ERROR_INFERENCE_FAILED,
                        RunAnywhereBridge.nativeGetLastError()
                    )
            }
        }
    }

    // =============================================================================
    // Embedding Operations
    // =============================================================================

    actual suspend fun loadEmbeddingModel(modelPath: String, configJson: String?) {
        withContext(Dispatchers.IO) {
            mutex.withLock {
                ensureInitialized()
                val result = ResultCode.fromValue(
                    RunAnywhereBridge.nativeEmbedLoadModel(backendHandle, modelPath, configJson)
                )
                if (!result.isSuccess) {
                    throw RunAnywhereException(result, RunAnywhereBridge.nativeGetLastError())
                }
            }
        }
    }

    actual val isEmbeddingModelLoaded: Boolean
        get() = backendHandle != 0L && RunAnywhereBridge.nativeEmbedIsModelLoaded(backendHandle)

    actual suspend fun unloadEmbeddingModel() {
        withContext(Dispatchers.IO) {
            mutex.withLock {
                if (backendHandle != 0L) {
                    RunAnywhereBridge.nativeEmbedUnloadModel(backendHandle)
                }
            }
        }
    }

    actual suspend fun embed(text: String): FloatArray {
        return withContext(Dispatchers.IO) {
            mutex.withLock {
                ensureInitialized()
                RunAnywhereBridge.nativeEmbedText(backendHandle, text)
                    ?: throw RunAnywhereException(
                        ResultCode.ERROR_INFERENCE_FAILED,
                        RunAnywhereBridge.nativeGetLastError()
                    )
            }
        }
    }

    actual val embeddingDimensions: Int
        get() {
            if (backendHandle == 0L) return 0
            return RunAnywhereBridge.nativeEmbedGetDimensions(backendHandle)
        }

    // =============================================================================
    // Private Helpers
    // =============================================================================

    private fun ensureInitialized() {
        if (backendHandle == 0L) {
            throw RunAnywhereException(
                ResultCode.ERROR_INVALID_HANDLE,
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
        fun extractArchive(archivePath: String, destDir: String): ResultCode {
            RunAnywhereBridge.loadLibrary()
            return ResultCode.fromValue(
                RunAnywhereBridge.nativeExtractArchive(archivePath, destDir)
            )
        }
    }
}
