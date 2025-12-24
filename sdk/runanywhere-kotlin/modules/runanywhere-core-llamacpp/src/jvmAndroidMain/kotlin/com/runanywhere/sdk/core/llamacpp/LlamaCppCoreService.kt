package com.runanywhere.sdk.core.llamacpp

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.native.bridge.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.channels.awaitClose
import java.util.concurrent.atomic.AtomicLong

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
    /**
     * Backend handle stored as AtomicLong for thread-safe reads.
     * Writes are still protected by mutex, but reads can safely happen without locking.
     */
    private val backendHandle = AtomicLong(0L)
    private val mutex = Mutex()
    private val logger = SDKLogger("LlamaCppCoreService")

    init {
        // Load unified JNI bridge on construction
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
                if (backendHandle.get() != 0L) {
                    // Already initialized
                    return@withContext
                }

                // Create backend
                val handle = RunAnywhereBridge.nativeCreateBackend("llamacpp")
                if (handle == 0L) {
                    throw NativeBridgeException(
                        NativeResultCode.ERROR_INIT_FAILED,
                        "Failed to create LlamaCPP backend"
                    )
                }
                backendHandle.set(handle)

                // Initialize backend
                val result = NativeResultCode.fromValue(
                    RunAnywhereBridge.nativeInitialize(handle, configJson)
                )
                if (!result.isSuccess) {
                    val error = RunAnywhereBridge.nativeGetLastError()
                    RunAnywhereBridge.nativeDestroy(handle)
                    backendHandle.set(0L)
                    throw NativeBridgeException(result, error.ifEmpty { "Initialization failed" })
                }
            }
        }
    }

    /**
     * Check if the backend is initialized.
     * Thread-safe: uses AtomicLong for lock-free read.
     */
    val isInitialized: Boolean
        get() {
            val handle = backendHandle.get()
            return handle != 0L && RunAnywhereBridge.nativeIsInitialized(handle)
        }

    /**
     * Get supported capabilities.
     * Thread-safe: uses AtomicLong for lock-free read.
     */
    val supportedCapabilities: List<NativeCapability>
        get() {
            val handle = backendHandle.get()
            if (handle == 0L) return emptyList()
            return RunAnywhereBridge.nativeGetCapabilities(handle)
                .toList()
                .mapNotNull { NativeCapability.fromValue(it) }
        }

    /**
     * Check if a specific capability is supported.
     * Thread-safe: uses AtomicLong for lock-free read.
     */
    fun supportsCapability(capability: NativeCapability): Boolean {
        val handle = backendHandle.get()
        if (handle == 0L) return false
        return RunAnywhereBridge.nativeSupportsCapability(handle, capability.value)
    }

    /**
     * Get device type being used.
     * Thread-safe: uses AtomicLong for lock-free read.
     */
    val deviceType: NativeDeviceType
        get() {
            val handle = backendHandle.get()
            if (handle == 0L) return NativeDeviceType.CPU
            return NativeDeviceType.fromValue(RunAnywhereBridge.nativeGetDevice(handle))
        }

    /**
     * Get current memory usage in bytes.
     * Thread-safe: uses AtomicLong for lock-free read.
     */
    val memoryUsage: Long
        get() {
            val handle = backendHandle.get()
            if (handle == 0L) return 0
            return RunAnywhereBridge.nativeGetMemoryUsage(handle)
        }

    /**
     * Destroy the backend and release all resources.
     * Thread-safe via mutex to prevent use-after-free.
     */
    suspend fun destroy() {
        withContext(Dispatchers.IO) {
            mutex.withLock {
                val handle = backendHandle.get()
                if (handle != 0L) {
                    RunAnywhereBridge.nativeDestroy(handle)
                    backendHandle.set(0L)
                }
            }
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
                logger.info("📂 Loading model from path: $modelPath")
                val handle = backendHandle.get()
                val result = NativeResultCode.fromValue(
                    RunAnywhereBridge.nativeTextLoadModel(handle, modelPath, configJson)
                )
                if (!result.isSuccess) {
                    logger.error("❌ Failed to load model from path: $modelPath")
                    throw NativeBridgeException(result, RunAnywhereBridge.nativeGetLastError())
                }
                logger.info("✅ Model loaded successfully from: $modelPath")
            }
        }
    }

    /**
     * Check if a model is loaded.
     * Thread-safe: uses AtomicLong for lock-free read.
     */
    val isModelLoaded: Boolean
        get() {
            val handle = backendHandle.get()
            return handle != 0L && RunAnywhereBridge.nativeTextIsModelLoaded(handle)
        }

    /**
     * Unload the current model.
     */
    suspend fun unloadModel() {
        withContext(Dispatchers.IO) {
            mutex.withLock {
                val handle = backendHandle.get()
                if (handle != 0L) {
                    RunAnywhereBridge.nativeTextUnloadModel(handle)
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
        // TODO: Not yet implemented in native library
        return "{}"
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
                val handle = backendHandle.get()
                val jsonResponse = RunAnywhereBridge.nativeTextGenerate(
                    handle,
                    prompt,
                    systemPrompt,
                    maxTokens,
                    temperature
                ) ?: throw NativeBridgeException(
                    NativeResultCode.ERROR_INFERENCE_FAILED,
                    RunAnywhereBridge.nativeGetLastError()
                )

                // Parse JSON response and extract text field
                // Response format: {"finish_reason":"stop","inference_time_ms":256.0,"text":"...","tokens_generated":9}
                parseTextFromResponse(jsonResponse)
            }
        }
    }

    /**
     * Parse the JSON response from native layer and extract the text field.
     */
    private fun parseTextFromResponse(jsonResponse: String): String {
        return try {
            // Simple JSON parsing - extract "text" field value
            val textRegex = """"text"\s*:\s*"((?:[^"\\]|\\.)*)"""".toRegex()
            val match = textRegex.find(jsonResponse)
            if (match != null) {
                // Unescape the JSON string
                match.groupValues[1]
                    .replace("\\n", "\n")
                    .replace("\\t", "\t")
                    .replace("\\\"", "\"")
                    .replace("\\\\", "\\")
            } else {
                // If parsing fails, return the raw response (backward compatibility)
                jsonResponse
            }
        } catch (e: Exception) {
            // If any error, return raw response
            jsonResponse
        }
    }

    /**
     * Generate text completion with streaming (callback-based).
     *
     * Note: The current native library doesn't support true streaming, so this
     * generates the full response and emits it as a single token.
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
        // Generate full response (native streaming not yet available)
        val fullResponse = generate(prompt, systemPrompt, maxTokens, temperature)

        // Emit the full response as a single "token"
        // TODO: When native streaming is available, use actual streaming
        onToken(fullResponse)
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
            close() // Signal completion after streaming finishes
        } catch (e: Exception) {
            close(e)
        }
        awaitClose { }
    }

    /**
     * Cancel ongoing text generation.
     * Thread-safe: uses AtomicLong for lock-free read.
     */
    fun cancel() {
        val handle = backendHandle.get()
        if (handle != 0L) {
            RunAnywhereBridge.nativeTextCancel(handle)
        }
    }

    // =============================================================================
    // Private Helpers
    // =============================================================================

    private fun ensureInitialized() {
        if (backendHandle.get() == 0L) {
            throw NativeBridgeException(
                NativeResultCode.ERROR_INVALID_HANDLE,
                "Backend not initialized. Call initialize() first."
            )
        }
    }

    private fun ensureModelLoaded() {
        val handle = backendHandle.get()
        if (!RunAnywhereBridge.nativeTextIsModelLoaded(handle)) {
            throw NativeBridgeException(
                NativeResultCode.ERROR_INVALID_PARAMS,
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
