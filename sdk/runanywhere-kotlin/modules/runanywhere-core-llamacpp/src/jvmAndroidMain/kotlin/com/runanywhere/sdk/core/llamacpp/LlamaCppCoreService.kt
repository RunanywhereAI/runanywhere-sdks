package com.runanywhere.sdk.core.llamacpp

import com.runanywhere.sdk.native.bridge.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.channels.awaitClose

/**
 * LlamaCPP implementation of text generation via RunAnywhere Core.
 *
 * This provides the LlamaCPP backend for RunAnywhere Core, focused on
 * TEXT_GENERATION capability for LLM inference.
 *
 * Thread Safety:
 * - All public methods are thread-safe via mutex
 * - Native operations run on IO dispatcher
 * - Handle is protected by mutex to prevent use-after-free
 *
 * Usage:
 * ```kotlin
 * val service = LlamaCppCoreService()
 * service.initialize()
 *
 * // Load GGUF model
 * service.loadModel("/path/to/model.gguf")
 *
 * // Generate text
 * val result = service.generate("Hello, how are you?")
 *
 * // Stream generation
 * service.generateStream("Tell me a story") { token ->
 *     print(token)
 *     true // continue
 * }
 *
 * // Cleanup
 * service.destroy()
 * ```
 */
class LlamaCppCoreService {
    private var backendHandle: Long = 0
    private val mutex = Mutex()

    init {
        // Load native library on construction
        RunAnywhereBridge.loadLibrary()
    }

    // =============================================================================
    // Lifecycle
    // =============================================================================

    /**
     * Initialize the LlamaCPP backend.
     *
     * @param configJson Optional JSON configuration with keys:
     *   - "n_threads": Number of threads to use (default: auto)
     *   - "use_mmap": Whether to use memory mapping (default: true)
     *   - "use_mlock": Whether to lock memory (default: false)
     * @throws NativeBridgeException if initialization fails
     */
    suspend fun initialize(configJson: String? = null) {
        withContext(Dispatchers.IO) {
            mutex.withLock {
                if (backendHandle != 0L) {
                    // Already initialized
                    return@withContext
                }

                // Create backend
                backendHandle = RunAnywhereBridge.nativeCreateBackend("llamacpp")
                if (backendHandle == 0L) {
                    throw NativeBridgeException(
                        NativeResultCode.ERROR_INIT_FAILED,
                        "Failed to create LlamaCPP backend"
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

    /**
     * Check if the backend is initialized.
     */
    val isInitialized: Boolean
        get() = backendHandle != 0L && RunAnywhereBridge.nativeIsInitialized(backendHandle)

    /**
     * Get supported capabilities.
     */
    val supportedCapabilities: List<NativeCapability>
        get() {
            if (backendHandle == 0L) return emptyList()
            return RunAnywhereBridge.nativeGetCapabilities(backendHandle)
                .toList()
                .mapNotNull { NativeCapability.fromValue(it) }
        }

    /**
     * Check if a specific capability is supported.
     */
    fun supportsCapability(capability: NativeCapability): Boolean {
        if (backendHandle == 0L) return false
        return RunAnywhereBridge.nativeSupportsCapability(backendHandle, capability.value)
    }

    /**
     * Get device type being used.
     */
    val deviceType: NativeDeviceType
        get() {
            if (backendHandle == 0L) return NativeDeviceType.CPU
            return NativeDeviceType.fromValue(RunAnywhereBridge.nativeGetDevice(backendHandle))
        }

    /**
     * Get current memory usage in bytes.
     */
    val memoryUsage: Long
        get() {
            if (backendHandle == 0L) return 0
            return RunAnywhereBridge.nativeGetMemoryUsage(backendHandle)
        }

    /**
     * Destroy the backend and release all resources.
     */
    fun destroy() {
        if (backendHandle != 0L) {
            RunAnywhereBridge.nativeDestroy(backendHandle)
            backendHandle = 0
        }
    }

    // =============================================================================
    // Model Operations
    // =============================================================================

    /**
     * Load a GGUF model.
     *
     * @param modelPath Path to the GGUF model file
     * @param configJson Optional JSON configuration with keys:
     *   - "n_ctx": Context window size (default: 2048)
     *   - "n_batch": Batch size for prompt processing (default: 512)
     *   - "n_gpu_layers": Number of layers to offload to GPU (default: 0)
     * @throws NativeBridgeException if loading fails
     */
    suspend fun loadModel(modelPath: String, configJson: String? = null) {
        withContext(Dispatchers.IO) {
            mutex.withLock {
                ensureInitialized()
                val result = NativeResultCode.fromValue(
                    RunAnywhereBridge.nativeTextLoadModel(backendHandle, modelPath, configJson)
                )
                if (!result.isSuccess) {
                    throw NativeBridgeException(result, RunAnywhereBridge.nativeGetLastError())
                }
            }
        }
    }

    /**
     * Check if a model is loaded.
     */
    val isModelLoaded: Boolean
        get() = backendHandle != 0L && RunAnywhereBridge.nativeTextIsModelLoaded(backendHandle)

    /**
     * Unload the current model.
     */
    suspend fun unloadModel() {
        withContext(Dispatchers.IO) {
            mutex.withLock {
                if (backendHandle != 0L) {
                    RunAnywhereBridge.nativeTextUnloadModel(backendHandle)
                }
            }
        }
    }

    /**
     * Get information about the loaded model.
     *
     * @return JSON string with model info, or empty object if no model loaded
     */
    fun getModelInfo(): String {
        if (backendHandle == 0L) return "{}"
        return RunAnywhereBridge.nativeTextGetModelInfo(backendHandle)
    }

    // =============================================================================
    // Text Generation
    // =============================================================================

    /**
     * Generate text completion (synchronous).
     *
     * @param prompt The prompt text
     * @param systemPrompt Optional system prompt
     * @param maxTokens Maximum tokens to generate (default: 256)
     * @param temperature Sampling temperature (default: 0.8, matches LLM.swift)
     * @return Generated text
     * @throws NativeBridgeException if generation fails
     */
    suspend fun generate(
        prompt: String,
        systemPrompt: String? = null,
        maxTokens: Int = 256,
        temperature: Float = 0.8f  // Match LLM.swift default
    ): String {
        return withContext(Dispatchers.IO) {
            mutex.withLock {
                ensureInitialized()
                ensureModelLoaded()
                RunAnywhereBridge.nativeTextGenerate(
                    backendHandle,
                    prompt,
                    systemPrompt,
                    maxTokens,
                    temperature
                ) ?: throw NativeBridgeException(
                    NativeResultCode.ERROR_INFERENCE_FAILED,
                    RunAnywhereBridge.nativeGetLastError()
                )
            }
        }
    }

    /**
     * Generate text completion with streaming (callback-based).
     *
     * @param prompt The prompt text
     * @param systemPrompt Optional system prompt
     * @param maxTokens Maximum tokens to generate (default: 256)
     * @param temperature Sampling temperature (default: 0.8, matches LLM.swift)
     * @param onToken Callback for each generated token, return false to cancel
     * @throws NativeBridgeException if generation fails
     */
    suspend fun generateStream(
        prompt: String,
        systemPrompt: String? = null,
        maxTokens: Int = 256,
        temperature: Float = 0.8f,  // Match LLM.swift default
        onToken: (String) -> Boolean
    ) {
        withContext(Dispatchers.IO) {
            mutex.withLock {
                ensureInitialized()
                ensureModelLoaded()

                val callback = object : RunAnywhereBridge.TextStreamCallback {
                    override fun onToken(token: String): Boolean = onToken(token)
                }

                val result = NativeResultCode.fromValue(
                    RunAnywhereBridge.nativeTextGenerateStream(
                        backendHandle,
                        prompt,
                        systemPrompt,
                        maxTokens,
                        temperature,
                        callback
                    )
                )

                if (!result.isSuccess && result != NativeResultCode.ERROR_CANCELLED) {
                    throw NativeBridgeException(result, RunAnywhereBridge.nativeGetLastError())
                }
            }
        }
    }

    /**
     * Generate text completion as a Flow.
     *
     * @param prompt The prompt text
     * @param systemPrompt Optional system prompt
     * @param maxTokens Maximum tokens to generate (default: 256)
     * @param temperature Sampling temperature (default: 0.8, matches LLM.swift)
     * @return Flow of generated tokens
     */
    fun generateFlow(
        prompt: String,
        systemPrompt: String? = null,
        maxTokens: Int = 256,
        temperature: Float = 0.8f  // Match LLM.swift default
    ): Flow<String> = callbackFlow {
        try {
            generateStream(prompt, systemPrompt, maxTokens, temperature) { token ->
                trySend(token).isSuccess
            }
        } catch (e: Exception) {
            close(e)
        }
        close()
        awaitClose { cancel() }
    }

    /**
     * Cancel ongoing text generation.
     */
    fun cancel() {
        if (backendHandle != 0L) {
            RunAnywhereBridge.nativeTextCancel(backendHandle)
        }
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

    private fun ensureModelLoaded() {
        if (!RunAnywhereBridge.nativeTextIsModelLoaded(backendHandle)) {
            throw NativeBridgeException(
                NativeResultCode.ERROR_MODEL_NOT_LOADED,
                "No model loaded. Call loadModel() first."
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
    }
}
