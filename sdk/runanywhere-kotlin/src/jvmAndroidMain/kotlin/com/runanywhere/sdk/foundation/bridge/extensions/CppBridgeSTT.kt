/*
 * Copyright 2024 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * STT extension for CppBridge.
 * Provides Speech-to-Text component lifecycle management for C++ core.
 *
 * Follows iOS CppBridge+STT.swift architecture.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import com.runanywhere.sdk.foundation.errors.SDKError

/**
 * STT bridge that provides Speech-to-Text component lifecycle management for C++ core.
 *
 * The C++ core needs STT component management for:
 * - Creating and destroying STT instances
 * - Loading and unloading models
 * - Audio transcription (standard and streaming)
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
object CppBridgeSTT {

    /**
     * STT component state constants matching C++ RAC_STT_STATE_* values.
     */
    object STTState {
        /** Component not created */
        const val NOT_CREATED = 0

        /** Component created but no model loaded */
        const val CREATED = 1

        /** Model is loading */
        const val LOADING = 2

        /** Model loaded and ready for transcription */
        const val READY = 3

        /** Transcription in progress */
        const val TRANSCRIBING = 4

        /** Model is unloading */
        const val UNLOADING = 5

        /** Component in error state */
        const val ERROR = 6

        /**
         * Get a human-readable name for the STT state.
         */
        fun getName(state: Int): String = when (state) {
            NOT_CREATED -> "NOT_CREATED"
            CREATED -> "CREATED"
            LOADING -> "LOADING"
            READY -> "READY"
            TRANSCRIBING -> "TRANSCRIBING"
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
     * Audio format constants for STT input.
     */
    object AudioFormat {
        /** 16-bit PCM audio */
        const val PCM_16 = 0

        /** 32-bit float audio */
        const val PCM_FLOAT = 1

        /** WAV file format */
        const val WAV = 2

        /** MP3 file format */
        const val MP3 = 3

        /** FLAC file format */
        const val FLAC = 4

        /** Opus/OGG format */
        const val OPUS = 5
    }

    /**
     * Language code constants.
     */
    object Language {
        const val AUTO = "auto"
        const val ENGLISH = "en"
        const val SPANISH = "es"
        const val FRENCH = "fr"
        const val GERMAN = "de"
        const val ITALIAN = "it"
        const val PORTUGUESE = "pt"
        const val JAPANESE = "ja"
        const val CHINESE = "zh"
        const val KOREAN = "ko"
        const val RUSSIAN = "ru"
        const val ARABIC = "ar"
        const val HINDI = "hi"
    }

    /**
     * Transcription completion reason constants.
     */
    object CompletionReason {
        /** Transcription still in progress */
        const val NOT_COMPLETED = 0

        /** End of audio reached */
        const val END_OF_AUDIO = 1

        /** Silence detected */
        const val SILENCE_DETECTED = 2

        /** Transcription was cancelled */
        const val CANCELLED = 3

        /** Maximum duration reached */
        const val MAX_DURATION = 4

        /** Transcription failed */
        const val ERROR = 5

        /**
         * Get a human-readable name for the completion reason.
         */
        fun getName(reason: Int): String = when (reason) {
            NOT_COMPLETED -> "NOT_COMPLETED"
            END_OF_AUDIO -> "END_OF_AUDIO"
            SILENCE_DETECTED -> "SILENCE_DETECTED"
            CANCELLED -> "CANCELLED"
            MAX_DURATION -> "MAX_DURATION"
            ERROR -> "ERROR"
            else -> "UNKNOWN($reason)"
        }
    }

    @Volatile
    private var isRegistered: Boolean = false

    @Volatile
    private var state: Int = STTState.NOT_CREATED

    @Volatile
    private var handle: Long = 0

    @Volatile
    private var loadedModelId: String? = null

    @Volatile
    private var loadedModelPath: String? = null

    @Volatile
    private var isCancelled: Boolean = false

    private val lock = Any()

    /**
     * Tag for logging.
     */
    private const val TAG = "CppBridgeSTT"

    /**
     * Singleton shared instance for accessing the STT component.
     * Matches iOS CppBridge.STT.shared pattern.
     */
    val shared: CppBridgeSTT = this

    /**
     * Optional listener for STT events.
     * Set this before calling [register] to receive events.
     */
    @Volatile
    var sttListener: STTListener? = null

    /**
     * Optional streaming callback for partial transcription results.
     * This is invoked for each partial transcription during streaming.
     */
    @Volatile
    var streamCallback: StreamCallback? = null

    /**
     * STT transcription configuration.
     *
     * @param language Language code (e.g., "en", "es", "auto")
     * @param sampleRate Audio sample rate in Hz (default: 16000)
     * @param channels Number of audio channels (default: 1 = mono)
     * @param audioFormat Audio format type
     * @param enableTimestamps Whether to include word timestamps
     * @param enablePunctuation Whether to add punctuation
     * @param maxDurationMs Maximum transcription duration in milliseconds (0 = unlimited)
     * @param vadEnabled Whether to use voice activity detection
     * @param vadSilenceMs Milliseconds of silence to detect end of speech
     */
    data class TranscriptionConfig(
        val language: String = Language.AUTO,
        val sampleRate: Int = 16000,
        val channels: Int = 1,
        val audioFormat: Int = AudioFormat.PCM_16,
        val enableTimestamps: Boolean = false,
        val enablePunctuation: Boolean = true,
        val maxDurationMs: Long = 0,
        val vadEnabled: Boolean = true,
        val vadSilenceMs: Int = 1000
    ) {
        /**
         * Convert to JSON string for C++ interop.
         */
        fun toJson(): String {
            return buildString {
                append("{")
                append("\"language\":\"${escapeJson(language)}\",")
                append("\"sample_rate\":$sampleRate,")
                append("\"channels\":$channels,")
                append("\"audio_format\":$audioFormat,")
                append("\"enable_timestamps\":$enableTimestamps,")
                append("\"enable_punctuation\":$enablePunctuation,")
                append("\"max_duration_ms\":$maxDurationMs,")
                append("\"vad_enabled\":$vadEnabled,")
                append("\"vad_silence_ms\":$vadSilenceMs")
                append("}")
            }
        }

        companion object {
            /** Default configuration */
            val DEFAULT = TranscriptionConfig()
        }
    }

    /**
     * STT model configuration.
     *
     * @param threads Number of threads for inference (-1 for auto)
     * @param gpuEnabled Whether to use GPU acceleration
     * @param beamSize Beam search size (larger = more accurate but slower)
     * @param useFlashAttention Whether to use flash attention optimization
     */
    data class ModelConfig(
        val threads: Int = -1,
        val gpuEnabled: Boolean = false,
        val beamSize: Int = 5,
        val useFlashAttention: Boolean = true
    ) {
        /**
         * Convert to JSON string for C++ interop.
         */
        fun toJson(): String {
            return buildString {
                append("{")
                append("\"threads\":$threads,")
                append("\"gpu_enabled\":$gpuEnabled,")
                append("\"beam_size\":$beamSize,")
                append("\"use_flash_attention\":$useFlashAttention")
                append("}")
            }
        }

        companion object {
            /** Default configuration */
            val DEFAULT = ModelConfig()
        }
    }

    /**
     * Word-level timestamp information.
     *
     * @param word The transcribed word
     * @param startMs Start time in milliseconds
     * @param endMs End time in milliseconds
     * @param confidence Confidence score (0.0 to 1.0)
     */
    data class WordTimestamp(
        val word: String,
        val startMs: Long,
        val endMs: Long,
        val confidence: Float
    )

    /**
     * STT transcription result.
     *
     * @param text Transcribed text
     * @param language Detected or specified language
     * @param durationMs Audio duration in milliseconds
     * @param completionReason Reason for transcription completion
     * @param confidence Overall confidence score (0.0 to 1.0)
     * @param processingTimeMs Time spent processing in milliseconds
     * @param wordTimestamps Word-level timestamps (if enabled)
     */
    data class TranscriptionResult(
        val text: String,
        val language: String,
        val durationMs: Long,
        val completionReason: Int,
        val confidence: Float,
        val processingTimeMs: Long,
        val wordTimestamps: List<WordTimestamp> = emptyList()
    ) {
        /**
         * Get the completion reason name.
         */
        fun getCompletionReasonName(): String = CompletionReason.getName(completionReason)

        /**
         * Check if transcription completed successfully.
         */
        fun isComplete(): Boolean = completionReason == CompletionReason.END_OF_AUDIO ||
                completionReason == CompletionReason.SILENCE_DETECTED

        /**
         * Check if transcription was cancelled.
         */
        fun wasCancelled(): Boolean = completionReason == CompletionReason.CANCELLED
    }

    /**
     * Partial transcription result for streaming.
     *
     * @param text Current partial transcription text
     * @param isFinal Whether this is a finalized segment
     * @param confidence Confidence score for this segment
     */
    data class PartialResult(
        val text: String,
        val isFinal: Boolean,
        val confidence: Float
    )

    /**
     * Listener interface for STT events.
     */
    interface STTListener {
        /**
         * Called when the STT component state changes.
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
         * Called when transcription starts.
         */
        fun onTranscriptionStarted()

        /**
         * Called when transcription completes.
         *
         * @param result The transcription result
         */
        fun onTranscriptionCompleted(result: TranscriptionResult)

        /**
         * Called when partial transcription is available during streaming.
         *
         * @param partial The partial result
         */
        fun onPartialResult(partial: PartialResult)

        /**
         * Called when an error occurs.
         *
         * @param errorCode The error code
         * @param errorMessage The error message
         */
        fun onError(errorCode: Int, errorMessage: String)
    }

    /**
     * Callback interface for streaming transcription.
     */
    fun interface StreamCallback {
        /**
         * Called for each partial transcription result.
         *
         * @param text The partial transcription text
         * @param isFinal Whether this is a finalized segment
         * @return true to continue transcription, false to stop
         */
        fun onPartialResult(text: String, isFinal: Boolean): Boolean
    }

    /**
     * Register the STT callbacks with C++ core.
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
            // nativeSetSTTCallbacks()

            isRegistered = true

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "STT callbacks registered"
            )
        }
    }

    /**
     * Check if the STT callbacks are registered.
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
                throw SDKError.notInitialized("STT component not created")
            }
            return handle
        }
    }

    /**
     * Check if a model is loaded.
     */
    val isLoaded: Boolean
        get() = synchronized(lock) { state == STTState.READY && loadedModelId != null }

    /**
     * Check if the component is ready for transcription.
     */
    val isReady: Boolean
        get() = STTState.isReady(state)

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
     * Create the STT component.
     *
     * @return 0 on success, error code on failure
     */
    fun create(): Int {
        synchronized(lock) {
            if (handle != 0L) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "STT component already created"
                )
                return 0
            }

            val result = nativeCreate()
            if (result == 0L) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.ERROR,
                    TAG,
                    "Failed to create STT component"
                )
                return -1
            }

            handle = result
            setState(STTState.CREATED)

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.INFO,
                TAG,
                "STT component created"
            )

            return 0
        }
    }

    /**
     * Load a model.
     *
     * @param modelPath Path to the model file
     * @param modelId Unique identifier for the model
     * @param config Model configuration (optional)
     * @return 0 on success, error code on failure
     */
    fun loadModel(modelPath: String, modelId: String, config: ModelConfig = ModelConfig.DEFAULT): Int {
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
                    "Unloading current model before loading new one: $loadedModelId"
                )
                unload()
            }

            setState(STTState.LOADING)

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.INFO,
                TAG,
                "Loading model: $modelId from $modelPath"
            )

            val result = nativeLoadModel(handle, modelPath, config.toJson())
            if (result != 0) {
                setState(STTState.ERROR)
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.ERROR,
                    TAG,
                    "Failed to load model: $modelId (error: $result)"
                )

                try {
                    sttListener?.onError(result, "Failed to load model: $modelId")
                } catch (e: Exception) {
                    // Ignore listener errors
                }

                return result
            }

            loadedModelId = modelId
            loadedModelPath = modelPath
            setState(STTState.READY)

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.INFO,
                TAG,
                "Model loaded successfully: $modelId"
            )

            // Update model assignment status
            CppBridgeModelAssignment.setAssignmentStatusCallback(
                CppBridgeModelRegistry.ModelType.STT,
                CppBridgeModelAssignment.AssignmentStatus.READY,
                CppBridgeModelAssignment.FailureReason.NONE
            )

            // Update component state
            CppBridgeState.setComponentStateCallback(
                CppBridgeState.ComponentType.STT,
                CppBridgeState.ComponentState.READY
            )

            try {
                sttListener?.onModelLoaded(modelId, modelPath)
            } catch (e: Exception) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Error in STT listener onModelLoaded: ${e.message}"
                )
            }

            return 0
        }
    }

    /**
     * Transcribe audio data.
     *
     * @param audioData Raw audio data bytes
     * @param config Transcription configuration (optional)
     * @return The transcription result
     * @throws SDKError if transcription fails
     */
    @Throws(SDKError::class)
    fun transcribe(audioData: ByteArray, config: TranscriptionConfig = TranscriptionConfig.DEFAULT): TranscriptionResult {
        synchronized(lock) {
            if (handle == 0L || state != STTState.READY) {
                throw SDKError.stt("STT component not ready for transcription")
            }

            isCancelled = false
            setState(STTState.TRANSCRIBING)

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Starting transcription (audio size: ${audioData.size} bytes)"
            )

            try {
                sttListener?.onTranscriptionStarted()
            } catch (e: Exception) {
                // Ignore listener errors
            }

            val startTime = System.currentTimeMillis()

            try {
                val resultJson = nativeTranscribe(handle, audioData, config.toJson())
                    ?: throw SDKError.stt("Transcription failed: null result")

                val result = parseTranscriptionResult(resultJson, System.currentTimeMillis() - startTime)

                setState(STTState.READY)

                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.DEBUG,
                    TAG,
                    "Transcription completed: ${result.text.length} chars, ${result.processingTimeMs}ms"
                )

                try {
                    sttListener?.onTranscriptionCompleted(result)
                } catch (e: Exception) {
                    // Ignore listener errors
                }

                return result

            } catch (e: Exception) {
                setState(STTState.READY) // Reset to ready, not error
                throw if (e is SDKError) e else SDKError.stt("Transcription failed: ${e.message}")
            }
        }
    }

    /**
     * Transcribe audio file.
     *
     * @param audioPath Path to the audio file
     * @param config Transcription configuration (optional)
     * @return The transcription result
     * @throws SDKError if transcription fails
     */
    @Throws(SDKError::class)
    fun transcribeFile(audioPath: String, config: TranscriptionConfig = TranscriptionConfig.DEFAULT): TranscriptionResult {
        synchronized(lock) {
            if (handle == 0L || state != STTState.READY) {
                throw SDKError.stt("STT component not ready for transcription")
            }

            isCancelled = false
            setState(STTState.TRANSCRIBING)

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Starting file transcription: $audioPath"
            )

            try {
                sttListener?.onTranscriptionStarted()
            } catch (e: Exception) {
                // Ignore listener errors
            }

            val startTime = System.currentTimeMillis()

            try {
                val resultJson = nativeTranscribeFile(handle, audioPath, config.toJson())
                    ?: throw SDKError.stt("Transcription failed: null result")

                val result = parseTranscriptionResult(resultJson, System.currentTimeMillis() - startTime)

                setState(STTState.READY)

                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.DEBUG,
                    TAG,
                    "File transcription completed: ${result.text.length} chars"
                )

                try {
                    sttListener?.onTranscriptionCompleted(result)
                } catch (e: Exception) {
                    // Ignore listener errors
                }

                return result

            } catch (e: Exception) {
                setState(STTState.READY) // Reset to ready, not error
                throw if (e is SDKError) e else SDKError.stt("File transcription failed: ${e.message}")
            }
        }
    }

    /**
     * Transcribe audio with streaming output.
     *
     * @param audioData Raw audio data bytes
     * @param config Transcription configuration (optional)
     * @param callback Callback for partial results
     * @return The final transcription result
     * @throws SDKError if transcription fails
     */
    @Throws(SDKError::class)
    fun transcribeStream(
        audioData: ByteArray,
        config: TranscriptionConfig = TranscriptionConfig.DEFAULT,
        callback: StreamCallback
    ): TranscriptionResult {
        synchronized(lock) {
            if (handle == 0L || state != STTState.READY) {
                throw SDKError.stt("STT component not ready for transcription")
            }

            isCancelled = false
            streamCallback = callback
            setState(STTState.TRANSCRIBING)

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Starting streaming transcription (audio size: ${audioData.size} bytes)"
            )

            try {
                sttListener?.onTranscriptionStarted()
            } catch (e: Exception) {
                // Ignore listener errors
            }

            val startTime = System.currentTimeMillis()

            try {
                val resultJson = nativeTranscribeStream(handle, audioData, config.toJson())
                    ?: throw SDKError.stt("Streaming transcription failed: null result")

                val result = parseTranscriptionResult(resultJson, System.currentTimeMillis() - startTime)

                setState(STTState.READY)
                streamCallback = null

                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.DEBUG,
                    TAG,
                    "Streaming transcription completed: ${result.text.length} chars"
                )

                try {
                    sttListener?.onTranscriptionCompleted(result)
                } catch (e: Exception) {
                    // Ignore listener errors
                }

                return result

            } catch (e: Exception) {
                setState(STTState.READY) // Reset to ready, not error
                streamCallback = null
                throw if (e is SDKError) e else SDKError.stt("Streaming transcription failed: ${e.message}")
            }
        }
    }

    /**
     * Cancel an ongoing transcription.
     */
    fun cancel() {
        synchronized(lock) {
            if (state != STTState.TRANSCRIBING) {
                return
            }

            isCancelled = true

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Cancelling transcription"
            )

            nativeCancel(handle)
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

            setState(STTState.UNLOADING)

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.INFO,
                TAG,
                "Unloading model: $previousModelId"
            )

            nativeUnload(handle)

            loadedModelId = null
            loadedModelPath = null
            setState(STTState.CREATED)

            // Update model assignment status
            CppBridgeModelAssignment.setAssignmentStatusCallback(
                CppBridgeModelRegistry.ModelType.STT,
                CppBridgeModelAssignment.AssignmentStatus.NOT_ASSIGNED,
                CppBridgeModelAssignment.FailureReason.NONE
            )

            // Update component state
            CppBridgeState.setComponentStateCallback(
                CppBridgeState.ComponentType.STT,
                CppBridgeState.ComponentState.CREATED
            )

            try {
                sttListener?.onModelUnloaded(previousModelId)
            } catch (e: Exception) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Error in STT listener onModelUnloaded: ${e.message}"
                )
            }
        }
    }

    /**
     * Destroy the STT component and release resources.
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
                "Destroying STT component"
            )

            nativeDestroy(handle)

            handle = 0
            setState(STTState.NOT_CREATED)

            // Update component state
            CppBridgeState.setComponentStateCallback(
                CppBridgeState.ComponentType.STT,
                CppBridgeState.ComponentState.NOT_CREATED
            )
        }
    }

    // ========================================================================
    // JNI CALLBACKS
    // ========================================================================

    /**
     * Streaming partial result callback.
     *
     * Called from C++ for each partial transcription result during streaming.
     *
     * @param text The partial transcription text
     * @param isFinal Whether this is a finalized segment
     * @return true to continue transcription, false to stop
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun streamPartialCallback(text: String, isFinal: Boolean): Boolean {
        if (isCancelled) {
            return false
        }

        val callback = streamCallback ?: return true

        // Notify listener
        try {
            sttListener?.onPartialResult(PartialResult(text, isFinal, 1.0f))
        } catch (e: Exception) {
            // Ignore listener errors
        }

        return try {
            callback.onPartialResult(text, isFinal)
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.WARN,
                TAG,
                "Error in stream callback: ${e.message}"
            )
            true // Continue on error
        }
    }

    /**
     * Progress callback.
     *
     * Called from C++ to report model loading or transcription progress.
     *
     * @param progress Progress (0.0 to 1.0)
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun progressCallback(progress: Float) {
        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.DEBUG,
            TAG,
            "Progress: ${(progress * 100).toInt()}%"
        )
    }

    /**
     * Get state callback.
     *
     * @return The current STT component state
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
        return loadedModelId != null && state == STTState.READY
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
     * Native method to set the STT callbacks with C++ core.
     *
     * Registers [streamPartialCallback], [progressCallback], etc. with C++ core.
     *
     * C API: rac_stt_set_callbacks(...)
     */
    @JvmStatic
    private external fun nativeSetSTTCallbacks()

    /**
     * Native method to unset the STT callbacks.
     *
     * Called during shutdown to clean up native resources.
     *
     * C API: rac_stt_set_callbacks(nullptr)
     */
    @JvmStatic
    private external fun nativeUnsetSTTCallbacks()

    /**
     * Native method to create the STT component.
     *
     * @return Handle to the created component, or 0 on failure
     *
     * C API: rac_stt_component_create()
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
     * C API: rac_stt_component_load_model(handle, model_path, config)
     */
    @JvmStatic
    external fun nativeLoadModel(handle: Long, modelPath: String, configJson: String): Int

    /**
     * Native method to transcribe audio data.
     *
     * @param handle The component handle
     * @param audioData Raw audio bytes
     * @param configJson JSON configuration string
     * @return JSON-encoded result, or null on failure
     *
     * C API: rac_stt_component_transcribe(handle, audio_data, audio_size, config)
     */
    @JvmStatic
    external fun nativeTranscribe(handle: Long, audioData: ByteArray, configJson: String): String?

    /**
     * Native method to transcribe audio file.
     *
     * @param handle The component handle
     * @param audioPath Path to the audio file
     * @param configJson JSON configuration string
     * @return JSON-encoded result, or null on failure
     *
     * C API: rac_stt_component_transcribe_file(handle, audio_path, config)
     */
    @JvmStatic
    external fun nativeTranscribeFile(handle: Long, audioPath: String, configJson: String): String?

    /**
     * Native method to transcribe audio with streaming.
     *
     * @param handle The component handle
     * @param audioData Raw audio bytes
     * @param configJson JSON configuration string
     * @return JSON-encoded result, or null on failure
     *
     * C API: rac_stt_component_transcribe_stream(handle, audio_data, audio_size, config)
     */
    @JvmStatic
    external fun nativeTranscribeStream(handle: Long, audioData: ByteArray, configJson: String): String?

    /**
     * Native method to cancel transcription.
     *
     * @param handle The component handle
     *
     * C API: rac_stt_component_cancel(handle)
     */
    @JvmStatic
    external fun nativeCancel(handle: Long)

    /**
     * Native method to unload the model.
     *
     * @param handle The component handle
     *
     * C API: rac_stt_component_unload(handle)
     */
    @JvmStatic
    external fun nativeUnload(handle: Long)

    /**
     * Native method to destroy the component.
     *
     * @param handle The component handle
     *
     * C API: rac_stt_component_destroy(handle)
     */
    @JvmStatic
    external fun nativeDestroy(handle: Long)

    /**
     * Native method to get supported languages.
     *
     * @param handle The component handle
     * @return JSON array of supported language codes
     *
     * C API: rac_stt_component_get_languages(handle)
     */
    @JvmStatic
    external fun nativeGetLanguages(handle: Long): String?

    /**
     * Native method to detect language from audio.
     *
     * @param handle The component handle
     * @param audioData Raw audio bytes
     * @return Detected language code
     *
     * C API: rac_stt_component_detect_language(handle, audio_data, audio_size)
     */
    @JvmStatic
    external fun nativeDetectLanguage(handle: Long, audioData: ByteArray): String?

    // ========================================================================
    // LIFECYCLE MANAGEMENT
    // ========================================================================

    /**
     * Unregister the STT callbacks and clean up resources.
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
            // nativeUnsetSTTCallbacks()

            sttListener = null
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
                "State changed: ${STTState.getName(previousState)} -> ${STTState.getName(newState)}"
            )

            try {
                sttListener?.onStateChanged(previousState, newState)
            } catch (e: Exception) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Error in STT listener onStateChanged: ${e.message}"
                )
            }
        }
    }

    /**
     * Parse transcription result from JSON.
     */
    private fun parseTranscriptionResult(json: String, elapsedMs: Long): TranscriptionResult {
        fun extractString(key: String): String {
            val pattern = "\"$key\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\""
            val regex = Regex(pattern)
            return regex.find(json)?.groupValues?.get(1)?.let { unescapeJson(it) } ?: ""
        }

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

        fun extractFloat(key: String): Float {
            val pattern = "\"$key\"\\s*:\\s*(-?[\\d.]+)"
            val regex = Regex(pattern)
            return regex.find(json)?.groupValues?.get(1)?.toFloatOrNull() ?: 0f
        }

        val text = extractString("text")
        val language = extractString("language").ifEmpty { Language.AUTO }
        val durationMs = extractLong("duration_ms")
        val completionReason = extractInt("completion_reason")
        val confidence = extractFloat("confidence")

        return TranscriptionResult(
            text = text,
            language = language,
            durationMs = durationMs,
            completionReason = completionReason,
            confidence = confidence,
            processingTimeMs = elapsedMs,
            wordTimestamps = emptyList() // TODO: Parse word timestamps if present
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
     * Get supported languages.
     *
     * @return List of supported language codes, or empty list if model not loaded
     */
    fun getSupportedLanguages(): List<String> {
        synchronized(lock) {
            if (handle == 0L || state != STTState.READY) {
                return emptyList()
            }
            val json = nativeGetLanguages(handle) ?: return emptyList()
            // Parse JSON array
            val pattern = "\"([^\"]+)\""
            return Regex(pattern).findAll(json).map { it.groupValues[1] }.toList()
        }
    }

    /**
     * Detect language from audio sample.
     *
     * @param audioData Raw audio data bytes
     * @return Detected language code, or Language.AUTO if detection fails
     */
    fun detectLanguage(audioData: ByteArray): String {
        synchronized(lock) {
            if (handle == 0L || state != STTState.READY) {
                return Language.AUTO
            }
            return nativeDetectLanguage(handle, audioData) ?: Language.AUTO
        }
    }

    /**
     * Get a state summary for diagnostics.
     *
     * @return Human-readable state summary
     */
    fun getStateSummary(): String {
        return buildString {
            append("STT State: ${STTState.getName(state)}")
            if (loadedModelId != null) {
                append(", Model: $loadedModelId")
            }
            if (handle != 0L) {
                append(", Handle: $handle")
            }
        }
    }
}
