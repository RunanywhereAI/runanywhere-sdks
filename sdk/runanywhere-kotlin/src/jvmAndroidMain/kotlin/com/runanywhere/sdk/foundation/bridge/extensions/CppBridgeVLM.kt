/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * VLM extension for CppBridge.
 * Provides VLM component lifecycle management for C++ core.
 *
 * Follows iOS CppBridge+VLM.swift architecture.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import com.runanywhere.sdk.foundation.bridge.CppBridge
import com.runanywhere.sdk.foundation.errors.SDKError
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.extensions.VLM.VLMResult

/**
 * VLM bridge that provides Vision Language Model component lifecycle management for C++ core.
 *
 * The C++ core needs VLM component management for:
 * - Creating and destroying VLM instances
 * - Loading and unloading models (model + mmproj)
 * - Image processing (standard and streaming)
 * - Canceling ongoing operations
 * - Component state tracking
 *
 * Thread Safety:
 * - State transitions are protected by synchronized(lock) blocks
 * - Long-running native JNI calls (process, processStream, loadModel,
 *   loadModelById) release the lock before the native call and re-acquire
 *   it afterward for state restore.  This prevents cancel() from deadlocking.
 * - cancel() reads volatile fields directly without acquiring the lock.
 * - Short-lived lifecycle operations (create, unload, destroy, unregister)
 *   remain fully synchronized.
 */
object CppBridgeVLM {
    /**
     * VLM component state constants matching C++ lifecycle states.
     */
    object VLMState {
        const val NOT_CREATED = 0
        const val CREATED = 1
        const val LOADING = 2
        const val READY = 3
        const val PROCESSING = 4
        const val UNLOADING = 5
        const val ERROR = 6

        fun getName(state: Int): String =
            when (state) {
                NOT_CREATED -> "NOT_CREATED"
                CREATED -> "CREATED"
                LOADING -> "LOADING"
                READY -> "READY"
                PROCESSING -> "PROCESSING"
                UNLOADING -> "UNLOADING"
                ERROR -> "ERROR"
                else -> "UNKNOWN($state)"
            }

        fun isReady(state: Int): Boolean = state == READY
    }

    @Volatile
    private var isRegistered: Boolean = false

    @Volatile
    private var state: Int = VLMState.NOT_CREATED

    @Volatile
    private var handle: Long = 0

    @Volatile
    private var loadedModelId: String? = null

    @Volatile
    private var loadedModelPath: String? = null

    @Volatile
    private var loadedMmprojPath: String? = null

    @Volatile
    private var isCancelled: Boolean = false

    @Volatile
    private var isNativeLibraryLoaded: Boolean = false

    private val lock = Any()

    private const val TAG = "CppBridgeVLM"

    val isNativeAvailable: Boolean
        get() = isNativeLibraryLoaded

    /**
     * Singleton shared instance.
     * Matches iOS CppBridge.VLM.shared pattern.
     */
    val shared: CppBridgeVLM = this

    /**
     * Optional streaming callback for token-by-token generation.
     */
    @Volatile
    var streamCallback: StreamCallback? = null

    /**
     * Callback interface for streaming token generation.
     */
    fun interface StreamCallback {
        fun onToken(token: String): Boolean
    }

    /**
     * VLM processing result from C++ layer.
     */
    data class ProcessingResult(
        val text: String,
        val promptTokens: Int,
        val imageTokens: Int,
        val completionTokens: Int,
        val totalTokens: Int,
        val timeToFirstTokenMs: Long,
        val imageEncodeTimeMs: Long,
        val totalTimeMs: Long,
        val tokensPerSecond: Float,
    )

    fun register() {
        synchronized(lock) {
            if (isRegistered) return
            isRegistered = true

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "VLM callbacks registered",
            )
        }
    }

    fun isRegistered(): Boolean = isRegistered

    val isLoaded: Boolean
        get() = synchronized(lock) { state == VLMState.READY && loadedModelId != null }

    val isReady: Boolean
        get() = VLMState.isReady(state)

    fun getLoadedModelId(): String? = loadedModelId

    fun getLoadedModelPath(): String? = loadedModelPath

    fun getLoadedMmprojPath(): String? = loadedMmprojPath

    fun getState(): Int = state

    // ========================================================================
    // LIFECYCLE OPERATIONS
    // ========================================================================

    fun create(): Int {
        synchronized(lock) {
            if (handle != 0L) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "VLM component already created",
                )
                return 0
            }

            if (!CppBridge.isNativeLibraryLoaded) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.ERROR,
                    TAG,
                    "Native library not loaded. VLM inference requires native libraries to be bundled.",
                )
                throw SDKError.notInitialized("Native library not available. Please ensure the native libraries are bundled in your APK.")
            }

            val result =
                try {
                    RunAnywhereBridge.racVlmComponentCreate()
                } catch (e: UnsatisfiedLinkError) {
                    isNativeLibraryLoaded = false
                    CppBridgePlatformAdapter.logCallback(
                        CppBridgePlatformAdapter.LogLevel.ERROR,
                        TAG,
                        "VLM component creation failed. Native method not available: ${e.message}",
                    )
                    throw SDKError.notInitialized("VLM native library not available. Please ensure the VLM backend is bundled in your APK.")
                }

            if (result == 0L) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.ERROR,
                    TAG,
                    "Failed to create VLM component",
                )
                return -1
            }

            handle = result
            isNativeLibraryLoaded = true
            setState(VLMState.CREATED)

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.INFO,
                TAG,
                "VLM component created",
            )

            return 0
        }
    }

    /**
     * Load a VLM model with separate model and mmproj paths.
     *
     * Lock is only held for state transitions, NOT during the blocking native
     * JNI load call, so that [cancel] and other short operations are not
     * blocked for the entire model-load duration.
     */
    fun loadModel(
        modelPath: String,
        mmprojPath: String?,
        modelId: String,
        modelName: String? = null,
    ): Int {
        // 1. Acquire lock for pre-load state transitions (create / unload if needed)
        synchronized(lock) {
            if (handle == 0L) {
                val createResult = create()
                if (createResult != 0) return createResult
            }

            if (loadedModelId != null) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Unloading current model before loading new one: $loadedModelId",
                )
                unload()
            }

            setState(VLMState.LOADING)
        }

        // 2. Capture volatile handle for thread-safe access outside lock
        val currentHandle = handle

        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.INFO,
            TAG,
            "Loading VLM model: $modelId from $modelPath (mmproj: ${mmprojPath ?: "none"})",
        )

        // 3. Native call runs outside lock
        val result = RunAnywhereBridge.racVlmComponentLoadModel(
            currentHandle, modelPath, mmprojPath, modelId, modelName,
        )

        // 4. Re-acquire lock for state updates
        if (result != 0) {
            synchronized(lock) {
                setState(VLMState.ERROR)
            }
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.ERROR,
                TAG,
                "Failed to load VLM model: $modelId (error: $result)",
            )
            return result
        }

        synchronized(lock) {
            loadedModelId = modelId
            loadedModelPath = modelPath
            loadedMmprojPath = mmprojPath
            setState(VLMState.READY)
        }

        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.INFO,
            TAG,
            "VLM model loaded successfully: $modelId",
        )

        return 0
    }

    /**
     * Load a VLM model by ID using the C++ model registry for path resolution.
     * The C++ layer handles finding the main model and mmproj files automatically.
     *
     * Lock is only held for state transitions, NOT during the blocking native
     * JNI load call, so that [cancel] and other short operations are not
     * blocked for the entire model-load duration.
     */
    fun loadModelById(modelId: String): Int {
        // 1. Acquire lock for pre-load state transitions (create / unload if needed)
        synchronized(lock) {
            if (handle == 0L) {
                val createResult = create()
                if (createResult != 0) return createResult
            }

            if (loadedModelId != null) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Unloading current model before loading new one: $loadedModelId",
                )
                unload()
            }

            setState(VLMState.LOADING)
        }

        // 2. Capture volatile handle for thread-safe access outside lock
        val currentHandle = handle

        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.INFO,
            TAG,
            "Loading VLM model by ID: $modelId",
        )

        // 3. Native call runs outside lock
        val result = RunAnywhereBridge.racVlmComponentLoadModelById(currentHandle, modelId)

        // 4. Re-acquire lock for state updates
        if (result != 0) {
            synchronized(lock) {
                setState(VLMState.ERROR)
            }
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.ERROR,
                TAG,
                "Failed to load VLM model by ID: $modelId (error: $result)",
            )
            return result
        }

        synchronized(lock) {
            loadedModelId = modelId
            setState(VLMState.READY)
        }

        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.INFO,
            TAG,
            "VLM model loaded successfully by ID: $modelId",
        )

        return 0
    }

    /**
     * Process an image (non-streaming).
     *
     * Lock is only held for state transitions, NOT during the blocking native
     * JNI call, so that [cancel] (which reads volatile fields directly) can
     * set the cancellation flag without waiting for processing to finish.
     */
    @Throws(SDKError::class)
    fun process(
        imageFormat: Int,
        imagePath: String?,
        imageData: ByteArray?,
        imageBase64: String?,
        imageWidth: Int,
        imageHeight: Int,
        prompt: String,
        optionsJson: String?,
    ): ProcessingResult {
        // 1. Acquire lock for state check + transition
        synchronized(lock) {
            if (handle == 0L || state != VLMState.READY) {
                throw SDKError.vlm("VLM component not ready for processing")
            }
            isCancelled = false
            setState(VLMState.PROCESSING)
        }

        // 2. Capture volatile handle for thread-safe access outside lock
        val currentHandle = handle

        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.DEBUG,
            TAG,
            "Starting VLM processing (prompt length: ${prompt.length})",
        )

        val startTime = System.currentTimeMillis()

        // 3. Native call runs outside lock so cancel() is not blocked
        try {
            val resultJson =
                RunAnywhereBridge.racVlmComponentProcess(
                    currentHandle, imageFormat, imagePath, imageData, imageBase64,
                    imageWidth, imageHeight, prompt, optionsJson,
                ) ?: throw SDKError.vlm("VLM processing failed: null result")

            val result = parseProcessingResult(resultJson, System.currentTimeMillis() - startTime)

            // 4. Re-acquire lock for state restore
            synchronized(lock) {
                setState(VLMState.READY)
            }

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "VLM processing completed: ${result.completionTokens} tokens, ${result.tokensPerSecond} tok/s",
            )

            return result
        } catch (e: Exception) {
            synchronized(lock) {
                setState(VLMState.READY)
            }
            throw if (e is SDKError) e else SDKError.vlm("VLM processing failed: ${e.message}")
        }
    }

    /**
     * Process an image with streaming output.
     *
     * Lock is only held for state transitions, NOT during the blocking native
     * JNI call, so that [cancel] (which reads volatile fields directly) can
     * set the cancellation flag without waiting for processing to finish.
     */
    @Throws(SDKError::class)
    fun processStream(
        imageFormat: Int,
        imagePath: String?,
        imageData: ByteArray?,
        imageBase64: String?,
        imageWidth: Int,
        imageHeight: Int,
        prompt: String,
        optionsJson: String?,
        callback: StreamCallback,
    ): ProcessingResult {
        // 1. Acquire lock for state check + transition; set streamCallback while locked
        synchronized(lock) {
            if (handle == 0L || state != VLMState.READY) {
                throw SDKError.vlm("VLM component not ready for processing")
            }
            isCancelled = false
            streamCallback = callback
            setState(VLMState.PROCESSING)
        }

        // 2. Capture volatile handle for thread-safe access outside lock
        val currentHandle = handle

        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.DEBUG,
            TAG,
            "Starting VLM streaming processing (prompt length: ${prompt.length})",
        )

        val startTime = System.currentTimeMillis()

        // 3. Native call runs outside lock so cancel() is not blocked
        try {
            val jniCallback =
                RunAnywhereBridge.TokenCallback { token ->
                    try {
                        callback.onToken(token.decodeToString())
                    } catch (e: Exception) {
                        CppBridgePlatformAdapter.logCallback(
                            CppBridgePlatformAdapter.LogLevel.WARN,
                            TAG,
                            "Error in VLM stream callback: ${e.message}",
                        )
                        true
                    }
                }

            val resultJson =
                RunAnywhereBridge.racVlmComponentProcessStream(
                    currentHandle, imageFormat, imagePath, imageData, imageBase64,
                    imageWidth, imageHeight, prompt, optionsJson, jniCallback,
                ) ?: throw SDKError.vlm("VLM streaming processing failed: null result")

            val result = parseProcessingResult(resultJson, System.currentTimeMillis() - startTime)

            // 4. Re-acquire lock for state restore
            synchronized(lock) {
                setState(VLMState.READY)
                streamCallback = null
            }

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "VLM streaming processing completed: ${result.completionTokens} tokens",
            )

            return result
        } catch (e: Exception) {
            synchronized(lock) {
                setState(VLMState.READY)
                streamCallback = null
            }
            throw if (e is SDKError) e else SDKError.vlm("VLM streaming processing failed: ${e.message}")
        }
    }

    fun cancel() {
        // Cancel must NOT acquire `lock` — processStream holds it for the
        // entire JNI call, so acquiring here would deadlock and defeat the
        // purpose of cancellation.  Reading volatile fields is safe.
        if (state != VLMState.PROCESSING) return

        isCancelled = true

        val currentHandle = handle
        if (currentHandle == 0L) return

        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.DEBUG,
            TAG,
            "Cancelling VLM generation",
        )

        // The C++ cancel sets an atomic flag checked by the generation loop
        RunAnywhereBridge.racVlmComponentCancel(currentHandle)
    }

    fun unload() {
        synchronized(lock) {
            if (loadedModelId == null) return

            val previousModelId = loadedModelId ?: return

            setState(VLMState.UNLOADING)

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.INFO,
                TAG,
                "Unloading VLM model: $previousModelId",
            )

            RunAnywhereBridge.racVlmComponentUnload(handle)

            loadedModelId = null
            loadedModelPath = null
            loadedMmprojPath = null
            setState(VLMState.CREATED)
        }
    }

    fun destroy() {
        synchronized(lock) {
            if (handle == 0L) return

            if (loadedModelId != null) {
                unload()
            }

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.INFO,
                TAG,
                "Destroying VLM component",
            )

            RunAnywhereBridge.racVlmComponentDestroy(handle)

            handle = 0
            setState(VLMState.NOT_CREATED)
        }
    }

    fun unregister() {
        synchronized(lock) {
            if (!isRegistered) return

            if (handle != 0L) {
                destroy()
            }

            streamCallback = null
            isRegistered = false
        }
    }

    // ========================================================================
    // JNI CALLBACKS
    // ========================================================================

    @JvmStatic
    fun streamTokenCallback(token: String): Boolean {
        if (isCancelled) return false
        val callback = streamCallback ?: return true
        return try {
            callback.onToken(token)
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.WARN,
                TAG,
                "Error in VLM stream callback: ${e.message}",
            )
            true
        }
    }

    // ========================================================================
    // UTILITY FUNCTIONS
    // ========================================================================

    private fun setState(newState: Int) {
        val previousState = state
        if (newState != previousState) {
            state = newState

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "State changed: ${VLMState.getName(previousState)} -> ${VLMState.getName(newState)}",
            )
        }
    }

    private fun parseProcessingResult(json: String, elapsedMs: Long): ProcessingResult {
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

        fun extractLong(key: String): Long {
            val pattern = "\"$key\"\\s*:\\s*(-?\\d+)"
            val regex = Regex(pattern)
            return regex
                .find(json)
                ?.groupValues
                ?.get(1)
                ?.toLongOrNull() ?: 0L
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
        val promptTokens = extractInt("prompt_tokens")
        val imageTokens = extractInt("image_tokens")
        val completionTokens = extractInt("completion_tokens")
        val totalTokens = extractInt("total_tokens")
        val timeToFirstTokenMs = extractLong("time_to_first_token_ms")
        val imageEncodeTimeMs = extractLong("image_encode_time_ms")
        val tokensPerSecond =
            if (elapsedMs > 0 && completionTokens > 0) {
                completionTokens * 1000f / elapsedMs
            } else {
                extractFloat("tokens_per_second")
            }

        return ProcessingResult(
            text = text,
            promptTokens = promptTokens,
            imageTokens = imageTokens,
            completionTokens = completionTokens,
            totalTokens = totalTokens,
            timeToFirstTokenMs = timeToFirstTokenMs,
            imageEncodeTimeMs = imageEncodeTimeMs,
            totalTimeMs = elapsedMs,
            tokensPerSecond = tokensPerSecond,
        )
    }

    private fun unescapeJson(value: String): String {
        return value
            .replace("\\\\", "\\")
            .replace("\\n", "\n")
            .replace("\\r", "\r")
            .replace("\\t", "\t")
            .replace("\\\"", "\"")
    }

    fun getStateSummary(): String {
        return buildString {
            append("VLM State: ${VLMState.getName(state)}")
            if (loadedModelId != null) {
                append(", Model: $loadedModelId")
            }
            if (handle != 0L) {
                append(", Handle: $handle")
            }
        }
    }
}
