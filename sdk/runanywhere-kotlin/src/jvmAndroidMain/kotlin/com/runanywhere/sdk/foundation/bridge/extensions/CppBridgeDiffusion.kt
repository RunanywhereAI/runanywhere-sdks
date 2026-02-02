/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Diffusion extension for CppBridge.
 * Provides Diffusion image generation component lifecycle management for C++ core.
 *
 * Follows iOS CppBridge+Diffusion.swift architecture.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import com.runanywhere.sdk.foundation.bridge.CppBridge
import com.runanywhere.sdk.foundation.errors.SDKError
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.extensions.Diffusion.DiffusionConfiguration
import com.runanywhere.sdk.public.extensions.Diffusion.DiffusionGenerationOptions
import com.runanywhere.sdk.public.extensions.Diffusion.DiffusionProgress
import com.runanywhere.sdk.public.extensions.Diffusion.DiffusionResult

/**
 * Diffusion bridge that provides image generation component lifecycle management for C++ core.
 *
 * The C++ core needs Diffusion component management for:
 * - Creating and destroying Diffusion instances
 * - Loading and unloading models
 * - Image generation (text-to-image, img2img, inpainting)
 * - Canceling ongoing operations
 * - Component state tracking
 *
 * Thread Safety:
 * - This object is thread-safe via synchronized blocks
 * - All callbacks are thread-safe
 * - Matches iOS Actor-based pattern using Kotlin synchronized
 */
object CppBridgeDiffusion {
    /**
     * Diffusion component state constants matching C++ RAC_DIFFUSION_STATE_* values.
     */
    object DiffusionState {
        /** Component not created */
        const val NOT_CREATED = 0

        /** Component created but no model loaded */
        const val CREATED = 1

        /** Model is loading */
        const val LOADING = 2

        /** Model loaded and ready for generation */
        const val READY = 3

        /** Generation in progress */
        const val GENERATING = 4

        /** Model is unloading */
        const val UNLOADING = 5

        /** Component in error state */
        const val ERROR = 6

        /**
         * Get a human-readable name for the Diffusion state.
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

    @Volatile
    private var isRegistered: Boolean = false

    @Volatile
    private var state: Int = DiffusionState.NOT_CREATED

    @Volatile
    private var handle: Long = 0

    @Volatile
    private var loadedModelId: String? = null

    @Volatile
    private var loadedModelPath: String? = null

    @Volatile
    private var isCancelled: Boolean = false

    @Volatile
    private var currentConfig: DiffusionConfiguration? = null

    private val lock = Any()

    /**
     * Tag for logging.
     */
    private const val TAG = "CppBridgeDiffusion"

    /**
     * Singleton shared instance for accessing the Diffusion component.
     */
    val shared: CppBridgeDiffusion = this

    /**
     * Optional listener for Diffusion events.
     */
    @Volatile
    var diffusionListener: DiffusionListener? = null

    /**
     * Optional progress callback for generation progress.
     */
    @Volatile
    var progressCallback: ProgressCallback? = null

    /**
     * Listener interface for Diffusion events.
     */
    interface DiffusionListener {
        fun onStateChanged(previousState: Int, newState: Int)
        fun onModelLoaded(modelId: String, modelPath: String)
        fun onModelUnloaded(modelId: String)
        fun onGenerationStarted()
        fun onGenerationProgress(progress: DiffusionProgress)
        fun onGenerationCompleted(result: DiffusionResult)
        fun onError(errorCode: Int, errorMessage: String)
    }

    /**
     * Callback interface for generation progress.
     */
    fun interface ProgressCallback {
        /**
         * Called for each progress update during generation.
         *
         * @param progress The progress update
         * @return true to continue generation, false to cancel
         */
        fun onProgress(progress: DiffusionProgress): Boolean
    }

    /**
     * Register the Diffusion callbacks with C++ core.
     */
    fun register() {
        synchronized(lock) {
            if (isRegistered) {
                return
            }

            isRegistered = true

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Diffusion callbacks registered",
            )
        }
    }

    /**
     * Check if the Diffusion callbacks are registered.
     */
    fun isRegistered(): Boolean = isRegistered

    /**
     * Get the current component handle.
     */
    @Throws(SDKError::class)
    fun getHandle(): Long {
        synchronized(lock) {
            if (handle == 0L) {
                throw SDKError.notInitialized("Diffusion component not created")
            }
            return handle
        }
    }

    /**
     * Check if a model is loaded.
     */
    val isLoaded: Boolean
        get() = synchronized(lock) { state == DiffusionState.READY && loadedModelId != null }

    /**
     * Check if the component is ready for generation.
     */
    val isReady: Boolean
        get() = DiffusionState.isReady(state)

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
     * Create the Diffusion component.
     *
     * @return 0 on success, error code on failure
     */
    fun create(): Int {
        synchronized(lock) {
            if (handle != 0L) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Diffusion component already created",
                )
                return 0
            }

            // Check if native commons library is loaded
            if (!CppBridge.isNativeLibraryLoaded) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.ERROR,
                    TAG,
                    "Native library not loaded. Diffusion requires native libraries to be bundled.",
                )
                throw SDKError.notInitialized("Native library not available. Please ensure the native libraries are bundled in your APK.")
            }

            // Create Diffusion component via RunAnywhereBridge
            val result =
                try {
                    RunAnywhereBridge.racDiffusionComponentCreate()
                } catch (e: UnsatisfiedLinkError) {
                    CppBridgePlatformAdapter.logCallback(
                        CppBridgePlatformAdapter.LogLevel.ERROR,
                        TAG,
                        "Diffusion component creation failed. Native method not available: ${e.message}",
                    )
                    throw SDKError.notInitialized("Diffusion native library not available. Please ensure the Diffusion backend is bundled in your APK.")
                }

            if (result == 0L) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.ERROR,
                    TAG,
                    "Failed to create Diffusion component",
                )
                return -1
            }

            handle = result
            setState(DiffusionState.CREATED)

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.INFO,
                TAG,
                "Diffusion component created",
            )

            return 0
        }
    }

    /**
     * Configure the Diffusion component.
     *
     * @param config Diffusion configuration
     * @return 0 on success, error code on failure
     */
    fun configure(config: DiffusionConfiguration): Int {
        synchronized(lock) {
            if (handle == 0L) {
                val createResult = create()
                if (createResult != 0) {
                    return createResult
                }
            }

            val configJson = buildString {
                append("{")
                append("\"model_variant\":${config.modelVariant.cValue},")
                append("\"enable_safety_checker\":${config.enableSafetyChecker},")
                append("\"reduce_memory\":${config.reduceMemory},")
                append("\"tokenizer_source\":${config.effectiveTokenizerSource.cValue}")
                config.effectiveTokenizerSource.customURL?.let { url ->
                    append(",\"tokenizer_custom_url\":\"${escapeJson(url)}\"")
                }
                append("}")
            }

            val result = RunAnywhereBridge.racDiffusionComponentConfigure(handle, configJson)
            if (result != 0) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.ERROR,
                    TAG,
                    "Failed to configure Diffusion component: $result",
                )
                return result
            }

            currentConfig = config

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.INFO,
                TAG,
                "Diffusion component configured with model variant: ${config.modelVariant}",
            )

            return 0
        }
    }

    /**
     * Load a model.
     *
     * @param modelPath Path to the model directory
     * @param modelId Unique identifier for the model
     * @param modelName Human-readable name for the model
     * @return 0 on success, error code on failure
     */
    fun loadModel(modelPath: String, modelId: String, modelName: String? = null): Int {
        synchronized(lock) {
            if (handle == 0L) {
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

            setState(DiffusionState.LOADING)

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.INFO,
                TAG,
                "Loading model: $modelId from $modelPath",
            )

            val result = RunAnywhereBridge.racDiffusionComponentLoadModel(handle, modelPath, modelId, modelName)
            if (result != 0) {
                setState(DiffusionState.ERROR)
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.ERROR,
                    TAG,
                    "Failed to load model: $modelId (error: $result)",
                )

                try {
                    diffusionListener?.onError(result, "Failed to load model: $modelId")
                } catch (e: Exception) {
                    // Ignore listener errors
                }

                return result
            }

            loadedModelId = modelId
            loadedModelPath = modelPath
            setState(DiffusionState.READY)

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.INFO,
                TAG,
                "Model loaded successfully: $modelId",
            )

            try {
                diffusionListener?.onModelLoaded(modelId, modelPath)
            } catch (e: Exception) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Error in Diffusion listener onModelLoaded: ${e.message}",
                )
            }

            return 0
        }
    }

    /**
     * Generate an image.
     *
     * @param options Generation options
     * @param callback Progress callback (optional)
     * @return The generation result
     * @throws SDKError if generation fails
     */
    @Throws(SDKError::class)
    fun generate(options: DiffusionGenerationOptions, callback: ProgressCallback? = null): DiffusionResult {
        synchronized(lock) {
            if (handle == 0L || state != DiffusionState.READY) {
                throw SDKError.diffusion("Diffusion component not ready for generation")
            }

            isCancelled = false
            progressCallback = callback
            setState(DiffusionState.GENERATING)

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Starting image generation: ${options.prompt.take(50)}...",
            )

            try {
                diffusionListener?.onGenerationStarted()
            } catch (e: Exception) {
                // Ignore listener errors
            }

            val startTime = System.currentTimeMillis()

            try {
                val optionsJson = buildString {
                    append("{")
                    append("\"prompt\":\"${escapeJson(options.prompt)}\",")
                    append("\"negative_prompt\":\"${escapeJson(options.negativePrompt)}\",")
                    append("\"width\":${options.width},")
                    append("\"height\":${options.height},")
                    append("\"steps\":${options.steps},")
                    append("\"guidance_scale\":${options.guidanceScale},")
                    append("\"seed\":${options.seed},")
                    append("\"scheduler\":${options.scheduler.cValue},")
                    append("\"mode\":${options.mode.cValue},")
                    append("\"denoise_strength\":${options.denoiseStrength},")
                    append("\"report_intermediate_images\":${options.reportIntermediateImages},")
                    append("\"progress_stride\":${options.progressStride}")
                    append("}")
                }

                val resultJson =
                    RunAnywhereBridge.racDiffusionComponentGenerate(
                        handle,
                        optionsJson,
                        options.inputImage,
                        options.maskImage,
                    ) ?: throw SDKError.diffusion("Generation failed: null result")

                val result = parseGenerationResult(resultJson, System.currentTimeMillis() - startTime)

                setState(DiffusionState.READY)
                progressCallback = null

                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.DEBUG,
                    TAG,
                    "Generation completed: ${result.width}x${result.height}, ${result.generationTimeMs}ms",
                )

                try {
                    diffusionListener?.onGenerationCompleted(result)
                } catch (e: Exception) {
                    // Ignore listener errors
                }

                return result
            } catch (e: Exception) {
                setState(DiffusionState.READY)
                progressCallback = null
                throw if (e is SDKError) e else SDKError.diffusion("Generation failed: ${e.message}")
            }
        }
    }

    /**
     * Cancel ongoing generation.
     */
    fun cancel() {
        synchronized(lock) {
            if (state != DiffusionState.GENERATING) {
                return
            }

            isCancelled = true

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Cancelling generation",
            )

            RunAnywhereBridge.racDiffusionComponentCancel(handle)
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

            setState(DiffusionState.UNLOADING)

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.INFO,
                TAG,
                "Unloading model: $previousModelId",
            )

            RunAnywhereBridge.racDiffusionComponentUnload(handle)

            loadedModelId = null
            loadedModelPath = null
            setState(DiffusionState.CREATED)

            try {
                diffusionListener?.onModelUnloaded(previousModelId)
            } catch (e: Exception) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Error in Diffusion listener onModelUnloaded: ${e.message}",
                )
            }
        }
    }

    /**
     * Destroy the Diffusion component and release resources.
     */
    fun destroy() {
        synchronized(lock) {
            if (handle == 0L) {
                return
            }

            if (loadedModelId != null) {
                unload()
            }

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.INFO,
                TAG,
                "Destroying Diffusion component",
            )

            RunAnywhereBridge.racDiffusionComponentDestroy(handle)

            handle = 0
            setState(DiffusionState.NOT_CREATED)
        }
    }

    // ========================================================================
    // JNI CALLBACKS
    // ========================================================================

    /**
     * Progress callback from C++.
     */
    @JvmStatic
    fun progressCallbackFromNative(
        progress: Float,
        currentStep: Int,
        totalSteps: Int,
        stage: String,
        intermediateImage: ByteArray?,
    ): Boolean {
        if (isCancelled) {
            return false
        }

        val diffusionProgress = DiffusionProgress(
            progress = progress,
            currentStep = currentStep,
            totalSteps = totalSteps,
            stage = stage,
            intermediateImage = intermediateImage,
        )

        try {
            diffusionListener?.onGenerationProgress(diffusionProgress)
        } catch (e: Exception) {
            // Ignore listener errors
        }

        return try {
            progressCallback?.onProgress(diffusionProgress) ?: true
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.WARN,
                TAG,
                "Error in progress callback: ${e.message}",
            )
            true
        }
    }

    // ========================================================================
    // LIFECYCLE MANAGEMENT
    // ========================================================================

    /**
     * Unregister the Diffusion callbacks and clean up resources.
     */
    fun unregister() {
        synchronized(lock) {
            if (!isRegistered) {
                return
            }

            if (handle != 0L) {
                destroy()
            }

            diffusionListener = null
            progressCallback = null
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
                "State changed: ${DiffusionState.getName(previousState)} -> ${DiffusionState.getName(newState)}",
            )

            try {
                diffusionListener?.onStateChanged(previousState, newState)
            } catch (e: Exception) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Error in Diffusion listener onStateChanged: ${e.message}",
                )
            }
        }
    }

    /**
     * Parse generation result from JSON.
     */
    private fun parseGenerationResult(json: String, elapsedMs: Long): DiffusionResult {
        fun extractInt(key: String): Int {
            val pattern = "\"$key\"\\s*:\\s*(-?\\d+)"
            val regex = Regex(pattern)
            return regex.find(json)?.groupValues?.get(1)?.toIntOrNull() ?: 0
        }

        fun extractLong(key: String): Long {
            val pattern = "\"$key\"\\s*:\\s*(-?\\d+)"
            val regex = Regex(pattern)
            return regex.find(json)?.groupValues?.get(1)?.toLongOrNull() ?: 0L
        }

        fun extractBoolean(key: String): Boolean {
            val pattern = "\"$key\"\\s*:\\s*(true|false)"
            val regex = Regex(pattern)
            return regex.find(json)?.groupValues?.get(1)?.toBooleanStrictOrNull() ?: false
        }

        fun extractBase64(key: String): ByteArray? {
            val pattern = "\"$key\"\\s*:\\s*\"([A-Za-z0-9+/=]*)\""
            val regex = Regex(pattern)
            val base64 = regex.find(json)?.groupValues?.get(1)
            return if (base64.isNullOrEmpty()) null else {
                try {
                    java.util.Base64.getDecoder().decode(base64)
                } catch (e: Exception) {
                    null
                }
            }
        }

        val imageData = extractBase64("image_data") ?: ByteArray(0)
        val width = extractInt("width")
        val height = extractInt("height")
        val seedUsed = extractLong("seed_used")
        val generationTimeMs = extractLong("generation_time_ms").let { if (it == 0L) elapsedMs else it }
        val safetyFlagged = extractBoolean("safety_flagged")

        return DiffusionResult(
            imageData = imageData,
            width = width,
            height = height,
            seedUsed = seedUsed,
            generationTimeMs = generationTimeMs,
            safetyFlagged = safetyFlagged,
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
     * Get a state summary for diagnostics.
     */
    fun getStateSummary(): String {
        return buildString {
            append("Diffusion State: ${DiffusionState.getName(state)}")
            if (loadedModelId != null) {
                append(", Model: $loadedModelId")
            }
            if (handle != 0L) {
                append(", Handle: $handle")
            }
        }
    }
}
