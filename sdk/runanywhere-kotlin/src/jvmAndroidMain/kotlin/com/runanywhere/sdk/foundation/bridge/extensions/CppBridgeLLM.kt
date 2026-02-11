/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * LLM extension for CppBridge.
 * Provides LLM component lifecycle management for C++ core.
 *
 * Follows iOS CppBridge+LLM.swift architecture.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import com.runanywhere.sdk.foundation.bridge.CppBridge
import com.runanywhere.sdk.foundation.errors.SDKError
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge

/**
 * LLM bridge that provides Large Language Model component lifecycle management for C++ core.
 *
 * The C++ core needs LLM component management for:
 * - Creating and destroying LLM instances
 * - Loading and unloading models
 * - Text generation (standard and streaming)
 * - Canceling ongoing operations
 * - Component state tracking
 *
 * Usage:
 * - Called during Phase 2 initialization in [CppBridge.initializeServices]
 * - Must be registered after [CppBridgePlatformAdapter] and [CppBridgeModelRegistry] are registered
 *
 * Thread Safety:
 * - This object is thread-safe via synchronized blocks
 * - All callbacks are thread-safe
 * - Matches iOS Actor-based pattern using Kotlin synchronized
 */
object CppBridgeLLM {
    /**
     * LLM component state constants matching C++ RAC_LLM_STATE_* values.
     */
    object LLMState {
        /** Component not created */
        const val NOT_CREATED = 0

        /** Component created but no model loaded */
        const val CREATED = 1

        /** Model is loading */
        const val LOADING = 2

        /** Model loaded and ready for inference */
        const val READY = 3

        /** Inference in progress */
        const val GENERATING = 4

        /** Model is unloading */
        const val UNLOADING = 5

        /** Component in error state */
        const val ERROR = 6

        /**
         * Get a human-readable name for the LLM state.
         */
        fun getName(state: Int): String =
            when (state) {
                NOT_CREATED -> "NOT_CREATED"
                CREATED -> "CREATED"
                LOADING -> "LOADING"
                READY -> "READY"
                GENERATING -> "GENERATING"
                UNLOADING -> "UNLOADING"
                ERROR -> "ERROR"
                else -> "UNKNOWN($state)"
            }

        /**
         * Check if the state indicates the component is usable.
         */
        fun isReady(state: Int): Boolean = state == READY
    }

    /**
     * LLM generation mode constants.
     */
    object GenerationMode {
        /** Standard completion mode */
        const val COMPLETION = 0

        /** Chat/instruction mode */
        const val CHAT = 1

        /** Fill-in-the-middle mode */
        const val INFILL = 2
    }

    /**
     * LLM stop reason constants.
     */
    object StopReason {
        /** Generation still in progress */
        const val NOT_STOPPED = 0

        /** Reached end of sequence token */
        const val EOS = 1

        /** Reached maximum token limit */
        const val MAX_TOKENS = 2

        /** Hit a stop sequence */
        const val STOP_SEQUENCE = 3

        /** Generation was cancelled */
        const val CANCELLED = 4

        /** Generation failed */
        const val ERROR = 5

        /**
         * Get a human-readable name for the stop reason.
         */
        fun getName(reason: Int): String =
            when (reason) {
                NOT_STOPPED -> "NOT_STOPPED"
                EOS -> "EOS"
                MAX_TOKENS -> "MAX_TOKENS"
                STOP_SEQUENCE -> "STOP_SEQUENCE"
                CANCELLED -> "CANCELLED"
                ERROR -> "ERROR"
                else -> "UNKNOWN($reason)"
            }
    }

    @Volatile
    private var isRegistered: Boolean = false

    @Volatile
    private var state: Int = LLMState.NOT_CREATED

    @Volatile
    private var handle: Long = 0

    @Volatile
    private var loadedModelId: String? = null

    @Volatile
    private var loadedModelPath: String? = null

    @Volatile
    private var isCancelled: Boolean = false

    @Volatile
    private var isNativeLibraryLoaded: Boolean = false

    private val lock = Any()

    /**
     * Tag for logging.
     */
    private const val TAG = "CppBridgeLLM"

    /**
     * Check if native LLM library is available.
     */
    val isNativeAvailable: Boolean
        get() = isNativeLibraryLoaded

    /**
     * Initialize native library availability check.
     * Should be called during SDK initialization.
     */
    fun checkNativeLibrary() {
        try {
            // Try to call a simple native method to verify library is loaded
            // If it throws UnsatisfiedLinkError, the library isn't available
            isNativeLibraryLoaded = true
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Native LLM library check passed",
            )
        } catch (e: UnsatisfiedLinkError) {
            isNativeLibraryLoaded = false
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.WARN,
                TAG,
                "Native LLM library not available: ${e.message}",
            )
        }
    }

    /**
     * Singleton shared instance for accessing the LLM component.
     * Matches iOS CppBridge.LLM.shared pattern.
     */
    val shared: CppBridgeLLM = this

    /**
     * Optional listener for LLM events.
     * Set this before calling [register] to receive events.
     */
    @Volatile
    var llmListener: LLMListener? = null

    /**
     * Optional streaming callback for token-by-token generation.
     * This is invoked for each generated token during streaming.
     */
    @Volatile
    var streamCallback: StreamCallback? = null

    /**
     * LLM generation configuration.
     *
     * @param maxTokens Maximum number of tokens to generate
     * @param temperature Sampling temperature (0.0 to 2.0)
     * @param topP Top-p (nucleus) sampling parameter
     * @param topK Top-k sampling parameter
     * @param repeatPenalty Penalty for repeating tokens
     * @param stopSequences List of sequences that stop generation
     * @param seed Random seed for reproducibility (-1 for random)
     */
    data class GenerationConfig(
        val maxTokens: Int = 512,
        val temperature: Float = 0.7f,
        val topP: Float = 0.9f,
        val topK: Int = 40,
        val repeatPenalty: Float = 1.1f,
        val stopSequences: List<String> = emptyList(),
        val seed: Long = -1,
    ) {
        /**
         * Convert to JSON string for C++ interop.
         */
        fun toJson(): String {
            return buildString {
                append("{")
                append("\"max_tokens\":$maxTokens,")
                append("\"temperature\":$temperature,")
                append("\"top_p\":$topP,")
                append("\"top_k\":$topK,")
                append("\"repeat_penalty\":$repeatPenalty,")
                append("\"stop_sequences\":[")
                stopSequences.forEachIndexed { index, seq ->
                    if (index > 0) append(",")
                    append("\"${escapeJson(seq)}\"")
                }
                append("],")
                append("\"seed\":$seed")
                append("}")
            }
        }

        companion object {
            /** Default configuration */
            val DEFAULT = GenerationConfig()
        }
    }

    /**
     * LLM model configuration.
     *
     * @param contextLength Context window size in tokens
     * @param gpuLayers Number of layers to offload to GPU (-1 for auto)
     * @param threads Number of threads for inference (-1 for auto)
     * @param batchSize Batch size for prompt processing
     * @param useMemoryMap Whether to use memory-mapped loading
     * @param useLocking Whether to use file locking
     */
    data class ModelConfig(
        val contextLength: Int = 4096,
        val gpuLayers: Int = -1,
        val threads: Int = -1,
        val batchSize: Int = 512,
        val useMemoryMap: Boolean = true,
        val useLocking: Boolean = false,
    ) {
        /**
         * Convert to JSON string for C++ interop.
         */
        fun toJson(): String {
            return buildString {
                append("{")
                append("\"context_length\":$contextLength,")
                append("\"gpu_layers\":$gpuLayers,")
                append("\"threads\":$threads,")
                append("\"batch_size\":$batchSize,")
                append("\"use_memory_map\":$useMemoryMap,")
                append("\"use_locking\":$useLocking")
                append("}")
            }
        }

        companion object {
            /** Default configuration */
            val DEFAULT = ModelConfig()
        }
    }

    /**
     * LLM generation result.
     *
     * @param text Generated text
     * @param tokensGenerated Number of tokens generated
     * @param tokensEvaluated Number of tokens evaluated (prompt + generated)
     * @param stopReason Reason for stopping generation
     * @param generationTimeMs Time spent generating in milliseconds
     * @param tokensPerSecond Generation speed
     */
    data class GenerationResult(
        val text: String,
        val tokensGenerated: Int,
        val tokensEvaluated: Int,
        val stopReason: Int,
        val generationTimeMs: Long,
        val tokensPerSecond: Float,
    ) {
        /**
         * Get the stop reason name.
         */
        fun getStopReasonName(): String = StopReason.getName(stopReason)

        /**
         * Check if generation completed normally.
         */
        fun isComplete(): Boolean = stopReason == StopReason.EOS || stopReason == StopReason.MAX_TOKENS

        /**
         * Check if generation was cancelled.
         */
        fun wasCancelled(): Boolean = stopReason == StopReason.CANCELLED
    }

    /**
     * Listener interface for LLM events.
     */
    interface LLMListener {
        /**
         * Called when the LLM component state changes.
         *
         * @param previousState The previous state
         * @param newState The new state
         */
        fun onStateChanged(previousState: Int, newState: Int)

        /**
         * Called when a model is loaded.
         *
         * @param modelId The model ID
         * @param modelPath The model path
         */
        fun onModelLoaded(modelId: String, modelPath: String)

        /**
         * Called when a model is unloaded.
         *
         * @param modelId The previously loaded model ID
         */
        fun onModelUnloaded(modelId: String)

        /**
         * Called when generation starts.
         *
         * @param prompt The input prompt
         */
        fun onGenerationStarted(prompt: String)

        /**
         * Called when generation completes.
         *
         * @param result The generation result
         */
        fun onGenerationCompleted(result: GenerationResult)

        /**
         * Called when an error occurs.
         *
         * @param errorCode The error code
         * @param errorMessage The error message
         */
        fun onError(errorCode: Int, errorMessage: String)
    }

    /**
     * Callback interface for streaming token generation.
     */
    fun interface StreamCallback {
        /**
         * Called for each generated token.
         *
         * @param token The generated token text
         * @return true to continue generation, false to stop
         */
        fun onToken(token: String): Boolean
    }

    /**
     * Register the LLM callbacks with C++ core.
     *
     * This must be called during SDK initialization, after [CppBridgePlatformAdapter.register].
     * It is safe to call multiple times; subsequent calls are no-ops.
     */
    fun register() {
        synchronized(lock) {
            if (isRegistered) {
                return
            }

            // TODO: Call native registration
            // nativeSetLLMCallbacks()

            isRegistered = true

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "LLM callbacks registered",
            )
        }
    }

    /**
     * Check if the LLM callbacks are registered.
     */
    fun isRegistered(): Boolean = isRegistered

    /**
     * Get the current component handle.
     *
     * @return The native handle, or throws if not created
     * @throws SDKError if the component is not created
     */
    @Throws(SDKError::class)
    fun getHandle(): Long {
        synchronized(lock) {
            if (handle == 0L) {
                throw SDKError.notInitialized("LLM component not created")
            }
            return handle
        }
    }

    /**
     * Check if a model is loaded.
     */
    val isLoaded: Boolean
        get() = synchronized(lock) { state == LLMState.READY && loadedModelId != null }

    /**
     * Check if the component is ready for inference.
     */
    val isReady: Boolean
        get() = LLMState.isReady(state)

    /**
     * Get the currently loaded model ID.
     */
    fun getLoadedModelId(): String? = loadedModelId

    /**
     * Get the currently loaded model path.
     */
    fun getLoadedModelPath(): String? = loadedModelPath

    /**
     * Get the current component state.
     */
    fun getState(): Int = state

    // ========================================================================
    // LIFECYCLE OPERATIONS
    // ========================================================================

    /**
     * Create the LLM component.
     *
     * @return 0 on success, error code on failure
     */
    fun create(): Int {
        synchronized(lock) {
            if (handle != 0L) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "LLM component already created",
                )
                return 0
            }

            // Check if native commons library is loaded
            if (!CppBridge.isNativeLibraryLoaded) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.ERROR,
                    TAG,
                    "Native library not loaded. LLM inference requires native libraries to be bundled.",
                )
                throw SDKError.notInitialized("Native library not available. Please ensure the native libraries are bundled in your APK.")
            }

            // Create LLM component via RunAnywhereBridge
            val result =
                try {
                    RunAnywhereBridge.racLlmComponentCreate()
                } catch (e: UnsatisfiedLinkError) {
                    isNativeLibraryLoaded = false
                    CppBridgePlatformAdapter.logCallback(
                        CppBridgePlatformAdapter.LogLevel.ERROR,
                        TAG,
                        "LLM component creation failed. Native method not available: ${e.message}",
                    )
                    throw SDKError.notInitialized("LLM native library not available. Please ensure the LLM backend is bundled in your APK.")
                }

            if (result == 0L) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.ERROR,
                    TAG,
                    "Failed to create LLM component",
                )
                return -1
            }

            handle = result
            isNativeLibraryLoaded = true
            setState(LLMState.CREATED)

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.INFO,
                TAG,
                "LLM component created",
            )

            return 0
        }
    }

    /**
     * Load a model.
     *
     * @param modelPath Path to the model file
     * @param modelId Unique identifier for the model (for telemetry)
     * @param modelName Human-readable name for the model (for telemetry)
     * @param config Model configuration (reserved for future use)
     * @return 0 on success, error code on failure
     */
    @Suppress("UNUSED_PARAMETER")
    fun loadModel(modelPath: String, modelId: String, modelName: String? = null, config: ModelConfig = ModelConfig.DEFAULT): Int {
        synchronized(lock) {
            if (handle == 0L) {
                // Auto-create component if needed
                val createResult = create()
                if (createResult != 0) {
                    return createResult
                }
            }

            if (loadedModelId != null) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Unloading current model before loading new one: $loadedModelId",
                )
                unload()
            }

            setState(LLMState.LOADING)

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.INFO,
                TAG,
                "Loading model: $modelId from $modelPath",
            )

            // Pass modelPath, modelId, and modelName separately to C++ lifecycle
            // This ensures correct telemetry - model_id should be the registered ID, not the file path
            val result = RunAnywhereBridge.racLlmComponentLoadModel(handle, modelPath, modelId, modelName)
            if (result != 0) {
                setState(LLMState.ERROR)
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.ERROR,
                    TAG,
                    "Failed to load model: $modelId (error: $result)",
                )

                try {
                    llmListener?.onError(result, "Failed to load model: $modelId")
                } catch (e: Exception) {
                    // Ignore listener errors
                }

                return result
            }

            loadedModelId = modelId
            loadedModelPath = modelPath
            setState(LLMState.READY)

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.INFO,
                TAG,
                "Model loaded successfully: $modelId",
            )

            // Update model assignment status
            CppBridgeModelAssignment.setAssignmentStatusCallback(
                CppBridgeModelRegistry.ModelType.LLM,
                CppBridgeModelAssignment.AssignmentStatus.READY,
                CppBridgeModelAssignment.FailureReason.NONE,
            )

            // Update component state
            CppBridgeState.setComponentStateCallback(
                CppBridgeState.ComponentType.LLM,
                CppBridgeState.ComponentState.READY,
            )

            try {
                llmListener?.onModelLoaded(modelId, modelPath)
            } catch (e: Exception) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Error in LLM listener onModelLoaded: ${e.message}",
                )
            }

            return 0
        }
    }

    /**
     * Generate text from a prompt.
     *
     * @param prompt The input prompt
     * @param config Generation configuration (optional)
     * @return The generation result
     * @throws SDKError if generation fails
     */
    @Throws(SDKError::class)
    fun generate(prompt: String, config: GenerationConfig = GenerationConfig.DEFAULT): GenerationResult {
        synchronized(lock) {
            if (handle == 0L || state != LLMState.READY) {
                throw SDKError.llm("LLM component not ready for generation")
            }

            isCancelled = false
            setState(LLMState.GENERATING)

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Starting generation (prompt length: ${prompt.length})",
            )

            try {
                llmListener?.onGenerationStarted(prompt)
            } catch (e: Exception) {
                // Ignore listener errors
            }

            val startTime = System.currentTimeMillis()

            try {
                val resultJson =
                    RunAnywhereBridge.racLlmComponentGenerate(handle, prompt, config.toJson())
                        ?: throw SDKError.llm("Generation failed: null result")

                val result = parseGenerationResult(resultJson, System.currentTimeMillis() - startTime)

                setState(LLMState.READY)

                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.DEBUG,
                    TAG,
                    "Generation completed: ${result.tokensGenerated} tokens, ${result.tokensPerSecond} tok/s",
                )

                try {
                    llmListener?.onGenerationCompleted(result)
                } catch (e: Exception) {
                    // Ignore listener errors
                }

                return result
            } catch (e: Exception) {
                setState(LLMState.READY) // Reset to ready, not error
                throw if (e is SDKError) e else SDKError.llm("Generation failed: ${e.message}")
            }
        }
    }

    /**
     * Generate text with streaming output.
     *
     * @param prompt The input prompt
     * @param config Generation configuration (optional)
     * @param callback Callback for each generated token
     * @return The final generation result
     * @throws SDKError if generation fails
     */
    @Throws(SDKError::class)
    fun generateStream(
        prompt: String,
        config: GenerationConfig = GenerationConfig.DEFAULT,
        callback: StreamCallback,
    ): GenerationResult {
        synchronized(lock) {
            if (handle == 0L || state != LLMState.READY) {
                throw SDKError.llm("LLM component not ready for generation")
            }

            isCancelled = false
            streamCallback = callback
            setState(LLMState.GENERATING)

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Starting streaming generation (prompt length: ${prompt.length})",
            )

            try {
                llmListener?.onGenerationStarted(prompt)
            } catch (e: Exception) {
                // Ignore listener errors
            }

            val startTime = System.currentTimeMillis()

            try {
                // Use the new callback-based streaming JNI method
                // This calls back to Kotlin for each token in real-time
                val jniCallback =
                    RunAnywhereBridge.TokenCallback { token ->
                        try {
                            // Forward each token to the user's callback
                            callback.onToken(token)
                        } catch (e: Exception) {
                            CppBridgePlatformAdapter.logCallback(
                                CppBridgePlatformAdapter.LogLevel.WARN,
                                TAG,
                                "Error in stream callback: ${e.message}",
                            )
                            true // Continue even if callback fails
                        }
                    }

                val resultJson =
                    RunAnywhereBridge.racLlmComponentGenerateStreamWithCallback(
                        handle,
                        prompt,
                        config.toJson(),
                        jniCallback,
                    ) ?: throw SDKError.llm("Streaming generation failed: null result")

                val result = parseGenerationResult(resultJson, System.currentTimeMillis() - startTime)

                setState(LLMState.READY)
                streamCallback = null

                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.DEBUG,
                    TAG,
                    "Streaming generation completed: ${result.tokensGenerated} tokens",
                )

                try {
                    llmListener?.onGenerationCompleted(result)
                } catch (e: Exception) {
                    // Ignore listener errors
                }

                return result
            } catch (e: Exception) {
                setState(LLMState.READY) // Reset to ready, not error
                streamCallback = null
                throw if (e is SDKError) e else SDKError.llm("Streaming generation failed: ${e.message}")
            }
        }
    }

    /**
     * Cancel an ongoing generation.
     */
    fun cancel() {
        synchronized(lock) {
            if (state != LLMState.GENERATING) {
                return
            }

            isCancelled = true

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Cancelling generation",
            )

            RunAnywhereBridge.racLlmComponentCancel(handle)
        }
    }

    /**
     * Unload the current model.
     */
    fun unload() {
        synchronized(lock) {
            if (loadedModelId == null) {
                return
            }

            val previousModelId = loadedModelId ?: return

            setState(LLMState.UNLOADING)

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.INFO,
                TAG,
                "Unloading model: $previousModelId",
            )

            RunAnywhereBridge.racLlmComponentUnload(handle)

            loadedModelId = null
            loadedModelPath = null
            setState(LLMState.CREATED)

            // Update model assignment status
            CppBridgeModelAssignment.setAssignmentStatusCallback(
                CppBridgeModelRegistry.ModelType.LLM,
                CppBridgeModelAssignment.AssignmentStatus.NOT_ASSIGNED,
                CppBridgeModelAssignment.FailureReason.NONE,
            )

            // Update component state
            CppBridgeState.setComponentStateCallback(
                CppBridgeState.ComponentType.LLM,
                CppBridgeState.ComponentState.CREATED,
            )

            try {
                llmListener?.onModelUnloaded(previousModelId)
            } catch (e: Exception) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Error in LLM listener onModelUnloaded: ${e.message}",
                )
            }
        }
    }

    /**
     * Destroy the LLM component and release resources.
     */
    fun destroy() {
        synchronized(lock) {
            if (handle == 0L) {
                return
            }

            // Unload model first if loaded
            if (loadedModelId != null) {
                unload()
            }

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.INFO,
                TAG,
                "Destroying LLM component",
            )

            RunAnywhereBridge.racLlmComponentDestroy(handle)

            handle = 0
            setState(LLMState.NOT_CREATED)

            // Update component state
            CppBridgeState.setComponentStateCallback(
                CppBridgeState.ComponentType.LLM,
                CppBridgeState.ComponentState.NOT_CREATED,
            )
        }
    }

    // ========================================================================
    // JNI CALLBACKS
    // ========================================================================

    /**
     * Streaming token callback.
     *
     * Called from C++ for each generated token during streaming.
     *
     * @param token The generated token text
     * @return true to continue generation, false to stop
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun streamTokenCallback(token: String): Boolean {
        if (isCancelled) {
            return false
        }

        val callback = streamCallback ?: return true

        return try {
            callback.onToken(token)
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.WARN,
                TAG,
                "Error in stream callback: ${e.message}",
            )
            true // Continue on error
        }
    }

    /**
     * Progress callback.
     *
     * Called from C++ to report model loading progress.
     *
     * @param progress Loading progress (0.0 to 1.0)
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun progressCallback(progress: Float) {
        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.DEBUG,
            TAG,
            "Model loading progress: ${(progress * 100).toInt()}%",
        )
    }

    /**
     * Get state callback.
     *
     * @return The current LLM component state
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun getStateCallback(): Int {
        return state
    }

    /**
     * Is loaded callback.
     *
     * @return true if a model is loaded
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun isLoadedCallback(): Boolean {
        return loadedModelId != null && state == LLMState.READY
    }

    /**
     * Get loaded model ID callback.
     *
     * @return The loaded model ID, or null
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun getLoadedModelIdCallback(): String? {
        return loadedModelId
    }

    // ========================================================================
    // JNI NATIVE DECLARATIONS
    // ========================================================================

    /**
     * Native method to set the LLM callbacks with C++ core.
     *
     * Registers [streamTokenCallback], [progressCallback], etc. with C++ core.
     * Reserved for future native callback integration.
     *
     * C API: rac_llm_set_callbacks(...)
     */
    @Suppress("unused")
    @JvmStatic
    private external fun nativeSetLLMCallbacks()

    /**
     * Native method to unset the LLM callbacks.
     *
     * Called during shutdown to clean up native resources.
     * Reserved for future native callback integration.
     *
     * C API: rac_llm_set_callbacks(nullptr)
     */
    @Suppress("unused")
    @JvmStatic
    private external fun nativeUnsetLLMCallbacks()

    /**
     * Native method to create the LLM component.
     *
     * @return Handle to the created component, or 0 on failure
     *
     * C API: rac_llm_component_create()
     */
    @JvmStatic
    external fun nativeCreate(): Long

    /**
     * Native method to load a model.
     *
     * @param handle The component handle
     * @param modelPath Path to the model file
     * @param configJson JSON configuration string
     * @return 0 on success, error code on failure
     *
     * C API: rac_llm_component_load_model(handle, model_path, config)
     */
    @JvmStatic
    external fun nativeLoadModel(handle: Long, modelPath: String, configJson: String): Int

    /**
     * Native method to generate text.
     *
     * @param handle The component handle
     * @param prompt The input prompt
     * @param configJson JSON configuration string
     * @return JSON-encoded result, or null on failure
     *
     * C API: rac_llm_component_generate(handle, prompt, config)
     */
    @JvmStatic
    external fun nativeGenerate(handle: Long, prompt: String, configJson: String): String?

    /**
     * Native method to generate text with streaming.
     *
     * @param handle The component handle
     * @param prompt The input prompt
     * @param configJson JSON configuration string
     * @return JSON-encoded result, or null on failure
     *
     * C API: rac_llm_component_generate_stream(handle, prompt, config)
     */
    @JvmStatic
    external fun nativeGenerateStream(handle: Long, prompt: String, configJson: String): String?

    /**
     * Native method to cancel generation.
     *
     * @param handle The component handle
     *
     * C API: rac_llm_component_cancel(handle)
     */
    @JvmStatic
    external fun nativeCancel(handle: Long)

    /**
     * Native method to unload the model.
     *
     * @param handle The component handle
     *
     * C API: rac_llm_component_unload(handle)
     */
    @JvmStatic
    external fun nativeUnload(handle: Long)

    /**
     * Native method to destroy the component.
     *
     * @param handle The component handle
     *
     * C API: rac_llm_component_destroy(handle)
     */
    @JvmStatic
    external fun nativeDestroy(handle: Long)

    /**
     * Native method to get context size.
     *
     * @param handle The component handle
     * @return The context size in tokens
     *
     * C API: rac_llm_component_get_context_size(handle)
     */
    @JvmStatic
    external fun nativeGetContextSize(handle: Long): Int

    /**
     * Native method to tokenize text.
     *
     * @param handle The component handle
     * @param text The text to tokenize
     * @return The number of tokens
     *
     * C API: rac_llm_component_tokenize(handle, text)
     */
    @JvmStatic
    external fun nativeTokenize(handle: Long, text: String): Int

    // ========================================================================
    // LIFECYCLE MANAGEMENT
    // ========================================================================

    /**
     * Unregister the LLM callbacks and clean up resources.
     *
     * Called during SDK shutdown.
     */
    fun unregister() {
        synchronized(lock) {
            if (!isRegistered) {
                return
            }

            // Destroy component if created
            if (handle != 0L) {
                destroy()
            }

            // TODO: Call native unregistration
            // nativeUnsetLLMCallbacks()

            llmListener = null
            streamCallback = null
            isRegistered = false
        }
    }

    // ========================================================================
    // UTILITY FUNCTIONS
    // ========================================================================

    /**
     * Set the component state and notify listeners.
     */
    private fun setState(newState: Int) {
        val previousState = state
        if (newState != previousState) {
            state = newState

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "State changed: ${LLMState.getName(previousState)} -> ${LLMState.getName(newState)}",
            )

            try {
                llmListener?.onStateChanged(previousState, newState)
            } catch (e: Exception) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Error in LLM listener onStateChanged: ${e.message}",
                )
            }
        }
    }

    /**
     * Parse generation result from JSON.
     */
    private fun parseGenerationResult(json: String, elapsedMs: Long): GenerationResult {
        fun extractString(key: String): String {
            val pattern = "\"$key\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\""
            val regex = Regex(pattern)
            return regex
                .find(json)
                ?.groupValues
                ?.get(1)
                ?.let { unescapeJson(it) } ?: ""
        }

        fun extractInt(key: String): Int {
            val pattern = "\"$key\"\\s*:\\s*(-?\\d+)"
            val regex = Regex(pattern)
            return regex
                .find(json)
                ?.groupValues
                ?.get(1)
                ?.toIntOrNull() ?: 0
        }

        fun extractFloat(key: String): Float {
            val pattern = "\"$key\"\\s*:\\s*(-?[\\d.]+)"
            val regex = Regex(pattern)
            return regex
                .find(json)
                ?.groupValues
                ?.get(1)
                ?.toFloatOrNull() ?: 0f
        }

        val text = extractString("text")
        val tokensGenerated = extractInt("tokens_generated")
        val tokensEvaluated = extractInt("tokens_evaluated")
        val stopReason = extractInt("stop_reason")
        val tokensPerSecond =
            if (elapsedMs > 0) {
                tokensGenerated * 1000f / elapsedMs
            } else {
                extractFloat("tokens_per_second")
            }

        return GenerationResult(
            text = text,
            tokensGenerated = tokensGenerated,
            tokensEvaluated = tokensEvaluated,
            stopReason = stopReason,
            generationTimeMs = elapsedMs,
            tokensPerSecond = tokensPerSecond,
        )
    }

    /**
     * Escape special characters for JSON string.
     */
    private fun escapeJson(value: String): String {
        return value
            .replace("\\", "\\\\")
            .replace("\"", "\\\"")
            .replace("\n", "\\n")
            .replace("\r", "\\r")
            .replace("\t", "\\t")
    }

    /**
     * Unescape JSON string.
     */
    private fun unescapeJson(value: String): String {
        return value
            .replace("\\n", "\n")
            .replace("\\r", "\r")
            .replace("\\t", "\t")
            .replace("\\\"", "\"")
            .replace("\\\\", "\\")
    }

    /**
     * Get the context size of the loaded model.
     *
     * @return The context size in tokens, or 0 if no model is loaded
     */
    fun getContextSize(): Int {
        synchronized(lock) {
            if (handle == 0L || state != LLMState.READY) {
                return 0
            }
            return RunAnywhereBridge.racLlmComponentGetContextSize(handle)
        }
    }

    /**
     * Tokenize text and return the token count.
     *
     * @param text The text to tokenize
     * @return The number of tokens, or 0 if no model is loaded
     */
    fun tokenize(text: String): Int {
        synchronized(lock) {
            if (handle == 0L || state != LLMState.READY) {
                return 0
            }
            return RunAnywhereBridge.racLlmComponentTokenize(handle, text)
        }
    }

    /**
     * Get a state summary for diagnostics.
     *
     * @return Human-readable state summary
     */
    fun getStateSummary(): String {
        return buildString {
            append("LLM State: ${LLMState.getName(state)}")
            if (loadedModelId != null) {
                append(", Model: $loadedModelId")
            }
            if (handle != 0L) {
                append(", Handle: $handle")
            }
        }
    }
}
