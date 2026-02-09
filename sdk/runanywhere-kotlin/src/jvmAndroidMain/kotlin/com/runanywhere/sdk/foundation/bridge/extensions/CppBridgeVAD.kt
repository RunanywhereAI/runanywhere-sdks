/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * VAD extension for CppBridge.
 * Provides Voice Activity Detection component lifecycle management for C++ core.
 *
 * Follows iOS CppBridge+VAD.swift architecture.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import com.runanywhere.sdk.foundation.bridge.CppBridge
import com.runanywhere.sdk.foundation.errors.SDKError
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge

/**
 * VAD bridge that provides Voice Activity Detection component lifecycle management for C++ core.
 *
 * The C++ core needs VAD component management for:
 * - Creating and destroying VAD instances
 * - Loading and unloading models
 * - Audio processing for speech detection
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
object CppBridgeVAD {
    /**
     * VAD component state constants matching C++ RAC_VAD_STATE_* values.
     */
    object VADState {
        /** Component not created */
        const val NOT_CREATED = 0

        /** Component created but no model loaded */
        const val CREATED = 1

        /** Model is loading */
        const val LOADING = 2

        /** Model loaded and ready for detection */
        const val READY = 3

        /** Detection in progress */
        const val DETECTING = 4

        /** Model is unloading */
        const val UNLOADING = 5

        /** Component in error state */
        const val ERROR = 6

        /**
         * Get a human-readable name for the VAD state.
         */
        fun getName(state: Int): String =
            when (state) {
                NOT_CREATED -> "NOT_CREATED"
                CREATED -> "CREATED"
                LOADING -> "LOADING"
                READY -> "READY"
                DETECTING -> "DETECTING"
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
     * Audio format constants for VAD input.
     */
    object AudioFormat {
        /** 16-bit PCM audio */
        const val PCM_16 = 0

        /** 32-bit float audio */
        const val PCM_FLOAT = 1

        /**
         * Get a human-readable name for the audio format.
         */
        fun getName(format: Int): String =
            when (format) {
                PCM_16 -> "PCM_16"
                PCM_FLOAT -> "PCM_FLOAT"
                else -> "UNKNOWN($format)"
            }
    }

    /**
     * Detection mode constants.
     */
    object DetectionMode {
        /** Frame-by-frame detection */
        const val FRAME = 0

        /** Continuous streaming detection */
        const val STREAM = 1

        /** Segment-based detection (returns speech segments) */
        const val SEGMENT = 2

        /**
         * Get a human-readable name for the detection mode.
         */
        fun getName(mode: Int): String =
            when (mode) {
                FRAME -> "FRAME"
                STREAM -> "STREAM"
                SEGMENT -> "SEGMENT"
                else -> "UNKNOWN($mode)"
            }
    }

    /**
     * Detection event type constants.
     */
    object EventType {
        /** No speech detected */
        const val SILENCE = 0

        /** Speech started */
        const val SPEECH_START = 1

        /** Speech ongoing */
        const val SPEECH_ONGOING = 2

        /** Speech ended */
        const val SPEECH_END = 3

        /**
         * Get a human-readable name for the event type.
         */
        fun getName(type: Int): String =
            when (type) {
                SILENCE -> "SILENCE"
                SPEECH_START -> "SPEECH_START"
                SPEECH_ONGOING -> "SPEECH_ONGOING"
                SPEECH_END -> "SPEECH_END"
                else -> "UNKNOWN($type)"
            }
    }

    @Volatile
    private var isRegistered: Boolean = false

    @Volatile
    private var state: Int = VADState.NOT_CREATED

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
    private const val TAG = "CppBridgeVAD"

    /**
     * Singleton shared instance for accessing the VAD component.
     * Matches iOS CppBridge.VAD.shared pattern.
     */
    val shared: CppBridgeVAD = this

    /**
     * Optional listener for VAD events.
     * Set this before calling [register] to receive events.
     */
    @Volatile
    var vadListener: VADListener? = null

    /**
     * Optional streaming callback for real-time detection results.
     * This is invoked for each detection event during streaming.
     */
    @Volatile
    var streamCallback: StreamCallback? = null

    /**
     * VAD detection configuration.
     *
     * @param sampleRate Audio sample rate in Hz (default: 16000)
     * @param channels Number of audio channels (default: 1 = mono)
     * @param audioFormat Audio format type
     * @param frameLength Frame length in milliseconds (default: 30)
     * @param threshold Detection threshold (0.0 to 1.0, default: 0.5)
     * @param minSpeechDurationMs Minimum speech duration in milliseconds
     * @param minSilenceDurationMs Minimum silence duration to consider speech ended
     * @param padding Padding in milliseconds to add around speech segments
     * @param mode Detection mode (frame, stream, or segment)
     */
    data class DetectionConfig(
        val sampleRate: Int = 16000,
        val channels: Int = 1,
        val audioFormat: Int = AudioFormat.PCM_16,
        val frameLength: Int = 30,
        val threshold: Float = 0.5f,
        val minSpeechDurationMs: Int = 250,
        val minSilenceDurationMs: Int = 300,
        val padding: Int = 100,
        val mode: Int = DetectionMode.STREAM,
    ) {
        /**
         * Convert to JSON string for C++ interop.
         */
        fun toJson(): String {
            return buildString {
                append("{")
                append("\"sample_rate\":$sampleRate,")
                append("\"channels\":$channels,")
                append("\"audio_format\":$audioFormat,")
                append("\"frame_length\":$frameLength,")
                append("\"threshold\":$threshold,")
                append("\"min_speech_duration_ms\":$minSpeechDurationMs,")
                append("\"min_silence_duration_ms\":$minSilenceDurationMs,")
                append("\"padding\":$padding,")
                append("\"mode\":$mode")
                append("}")
            }
        }

        companion object {
            /** Default configuration */
            val DEFAULT = DetectionConfig()
        }
    }

    /**
     * VAD model configuration.
     *
     * @param threads Number of threads for inference (-1 for auto)
     * @param gpuEnabled Whether to use GPU acceleration
     */
    data class ModelConfig(
        val threads: Int = -1,
        val gpuEnabled: Boolean = false,
    ) {
        /**
         * Convert to JSON string for C++ interop.
         */
        fun toJson(): String {
            return buildString {
                append("{")
                append("\"threads\":$threads,")
                append("\"gpu_enabled\":$gpuEnabled")
                append("}")
            }
        }

        companion object {
            /** Default configuration */
            val DEFAULT = ModelConfig()
        }
    }

    /**
     * Speech segment information.
     *
     * @param startMs Start time in milliseconds
     * @param endMs End time in milliseconds
     * @param confidence Confidence score (0.0 to 1.0)
     */
    data class SpeechSegment(
        val startMs: Long,
        val endMs: Long,
        val confidence: Float,
    ) {
        /**
         * Get the duration of the segment in milliseconds.
         */
        fun getDurationMs(): Long = endMs - startMs
    }

    /**
     * VAD detection result for a single frame.
     *
     * @param isSpeech Whether speech is detected
     * @param probability Speech probability (0.0 to 1.0)
     * @param eventType Event type (see [EventType])
     * @param timestampMs Timestamp in milliseconds
     */
    data class FrameResult(
        val isSpeech: Boolean,
        val probability: Float,
        val eventType: Int,
        val timestampMs: Long,
    ) {
        /**
         * Get the event type name.
         */
        fun getEventTypeName(): String = EventType.getName(eventType)
    }

    /**
     * VAD detection result containing speech segments.
     *
     * @param segments List of detected speech segments
     * @param audioDurationMs Total audio duration in milliseconds
     * @param processingTimeMs Time spent processing in milliseconds
     * @param hasSpeech Whether any speech was detected
     */
    data class DetectionResult(
        val segments: List<SpeechSegment>,
        val audioDurationMs: Long,
        val processingTimeMs: Long,
        val hasSpeech: Boolean,
    ) {
        /**
         * Get the total speech duration in milliseconds.
         */
        fun getTotalSpeechDurationMs(): Long = segments.sumOf { it.getDurationMs() }

        /**
         * Get the speech ratio (speech time / total time).
         */
        fun getSpeechRatio(): Float {
            if (audioDurationMs == 0L) return 0f
            return getTotalSpeechDurationMs().toFloat() / audioDurationMs
        }
    }

    /**
     * Listener interface for VAD events.
     */
    interface VADListener {
        /**
         * Called when the VAD component state changes.
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
         * Called when detection starts.
         */
        fun onDetectionStarted()

        /**
         * Called when detection completes.
         *
         * @param result The detection result
         */
        fun onDetectionCompleted(result: DetectionResult)

        /**
         * Called when a frame is processed during streaming.
         *
         * @param frameResult The frame result
         */
        fun onFrameResult(frameResult: FrameResult)

        /**
         * Called when speech starts during streaming.
         *
         * @param timestampMs Timestamp in milliseconds
         */
        fun onSpeechStart(timestampMs: Long)

        /**
         * Called when speech ends during streaming.
         *
         * @param timestampMs Timestamp in milliseconds
         * @param segment The detected speech segment
         */
        fun onSpeechEnd(timestampMs: Long, segment: SpeechSegment)

        /**
         * Called when an error occurs.
         *
         * @param errorCode The error code
         * @param errorMessage The error message
         */
        fun onError(errorCode: Int, errorMessage: String)
    }

    /**
     * Callback interface for streaming detection.
     */
    fun interface StreamCallback {
        /**
         * Called for each detection frame.
         *
         * @param isSpeech Whether speech is detected
         * @param probability Speech probability
         * @param eventType Event type (see [EventType])
         * @return true to continue detection, false to stop
         */
        fun onFrame(isSpeech: Boolean, probability: Float, eventType: Int): Boolean
    }

    /**
     * Register the VAD callbacks with C++ core.
     *
     * This must be called during SDK initialization, after [CppBridgePlatformAdapter.register].
     * It is safe to call multiple times; subsequent calls are no-ops.
     */
    fun register() {
        synchronized(lock) {
            if (isRegistered) {
                return
            }

            RunAnywhereBridge.racVadSetCallbacks(
                this,
                this,
                this,
                this,
            )

            isRegistered = true

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "VAD callbacks registered",
            )
        }
    }

    /**
     * Check if the VAD callbacks are registered.
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
                throw SDKError.notInitialized("VAD component not created")
            }
            return handle
        }
    }

    /**
     * Check if a model is loaded.
     */
    val isLoaded: Boolean
        get() = synchronized(lock) { state == VADState.READY && loadedModelId != null }

    /**
     * Check if the component is ready for detection.
     */
    val isReady: Boolean
        get() = VADState.isReady(state)

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
     * Create the VAD component.
     *
     * @return 0 on success, error code on failure
     */
    fun create(): Int {
        synchronized(lock) {
            if (handle != 0L) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "VAD component already created",
                )
                return 0
            }

            // Check if native commons library is loaded
            if (!CppBridge.isNativeLibraryLoaded) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.ERROR,
                    TAG,
                    "Native library not loaded. VAD inference requires native libraries to be bundled.",
                )
                throw SDKError.notInitialized("Native library not available. Please ensure the native libraries are bundled in your APK.")
            }

            // Create VAD component via RunAnywhereBridge
            val result =
                try {
                    RunAnywhereBridge.racVadComponentCreate()
                } catch (e: UnsatisfiedLinkError) {
                    CppBridgePlatformAdapter.logCallback(
                        CppBridgePlatformAdapter.LogLevel.ERROR,
                        TAG,
                        "VAD component creation failed. Native method not available: ${e.message}",
                    )
                    throw SDKError.notInitialized("VAD native library not available. Please ensure the VAD backend is bundled in your APK.")
                }

            if (result == 0L) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.ERROR,
                    TAG,
                    "Failed to create VAD component",
                )
                return -1
            }

            handle = result
            setState(VADState.CREATED)

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.INFO,
                TAG,
                "VAD component created",
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
                    "Unloading current model before loading new one: $loadedModelId",
                )
                unload()
            }

            setState(VADState.LOADING)

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.INFO,
                TAG,
                "Loading model: $modelId from $modelPath",
            )

            val result = RunAnywhereBridge.racVadComponentLoadModel(handle, modelPath, config.toJson())
            if (result != 0) {
                setState(VADState.ERROR)
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.ERROR,
                    TAG,
                    "Failed to load model: $modelId (error: $result)",
                )

                try {
                    vadListener?.onError(result, "Failed to load model: $modelId")
                } catch (e: Exception) {
                    // Ignore listener errors
                }

                return result
            }

            loadedModelId = modelId
            loadedModelPath = modelPath
            setState(VADState.READY)

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.INFO,
                TAG,
                "Model loaded successfully: $modelId",
            )

            // Update model assignment status
            CppBridgeModelAssignment.setAssignmentStatusCallback(
                CppBridgeModelRegistry.ModelType.VAD,
                CppBridgeModelAssignment.AssignmentStatus.READY,
                CppBridgeModelAssignment.FailureReason.NONE,
            )

            // Update component state
            CppBridgeState.setComponentStateCallback(
                CppBridgeState.ComponentType.VAD,
                CppBridgeState.ComponentState.READY,
            )

            try {
                vadListener?.onModelLoaded(modelId, modelPath)
            } catch (e: Exception) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Error in VAD listener onModelLoaded: ${e.message}",
                )
            }

            return 0
        }
    }

    /**
     * Process audio data for voice activity detection.
     *
     * @param audioData Raw audio data bytes
     * @param config Detection configuration (optional)
     * @return The detection result
     * @throws SDKError if detection fails
     */
    @Throws(SDKError::class)
    fun process(audioData: ByteArray, config: DetectionConfig = DetectionConfig.DEFAULT): DetectionResult {
        synchronized(lock) {
            if (handle == 0L || state != VADState.READY) {
                throw SDKError.vad("VAD component not ready for detection")
            }

            isCancelled = false
            setState(VADState.DETECTING)

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Starting detection (audio size: ${audioData.size} bytes)",
            )

            try {
                vadListener?.onDetectionStarted()
            } catch (e: Exception) {
                // Ignore listener errors
            }

            val startTime = System.currentTimeMillis()

            try {
                val resultJson =
                    RunAnywhereBridge.racVadComponentProcess(handle, audioData, config.toJson())
                        ?: throw SDKError.vad("Detection failed: null result")

                val result = parseDetectionResult(resultJson, System.currentTimeMillis() - startTime)

                setState(VADState.READY)

                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.DEBUG,
                    TAG,
                    "Detection completed: ${result.segments.size} segments, ${result.processingTimeMs}ms",
                )

                try {
                    vadListener?.onDetectionCompleted(result)
                } catch (e: Exception) {
                    // Ignore listener errors
                }

                return result
            } catch (e: Exception) {
                setState(VADState.READY) // Reset to ready, not error
                throw if (e is SDKError) e else SDKError.vad("Detection failed: ${e.message}")
            }
        }
    }

    /**
     * Process audio with streaming output.
     *
     * @param audioData Raw audio data bytes
     * @param config Detection configuration (optional)
     * @param callback Callback for frame results
     * @return The final detection result
     * @throws SDKError if detection fails
     */
    @Throws(SDKError::class)
    fun processStream(
        audioData: ByteArray,
        config: DetectionConfig = DetectionConfig.DEFAULT,
        callback: StreamCallback,
    ): DetectionResult {
        synchronized(lock) {
            if (handle == 0L || state != VADState.READY) {
                throw SDKError.vad("VAD component not ready for detection")
            }

            isCancelled = false
            streamCallback = callback
            setState(VADState.DETECTING)

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Starting streaming detection (audio size: ${audioData.size} bytes)",
            )

            try {
                vadListener?.onDetectionStarted()
            } catch (e: Exception) {
                // Ignore listener errors
            }

            val startTime = System.currentTimeMillis()

            try {
                val resultJson =
                    RunAnywhereBridge.racVadComponentProcessStream(handle, audioData, config.toJson())
                        ?: throw SDKError.vad("Streaming detection failed: null result")

                val result = parseDetectionResult(resultJson, System.currentTimeMillis() - startTime)

                setState(VADState.READY)
                streamCallback = null

                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.DEBUG,
                    TAG,
                    "Streaming detection completed: ${result.segments.size} segments",
                )

                try {
                    vadListener?.onDetectionCompleted(result)
                } catch (e: Exception) {
                    // Ignore listener errors
                }

                return result
            } catch (e: Exception) {
                setState(VADState.READY) // Reset to ready, not error
                streamCallback = null
                throw if (e is SDKError) e else SDKError.vad("Streaming detection failed: ${e.message}")
            }
        }
    }

    /**
     * Process a single audio frame for real-time detection.
     *
     * @param audioData Raw audio data bytes for the frame
     * @param config Detection configuration (optional)
     * @return The frame result
     * @throws SDKError if processing fails
     */
    @Throws(SDKError::class)
    fun processFrame(audioData: ByteArray, config: DetectionConfig = DetectionConfig.DEFAULT): FrameResult {
        synchronized(lock) {
            if (handle == 0L || state != VADState.READY) {
                throw SDKError.vad("VAD component not ready for detection")
            }

            try {
                val resultJson =
                    RunAnywhereBridge.racVadComponentProcessFrame(handle, audioData, config.toJson())
                        ?: throw SDKError.vad("Frame processing failed: null result")

                return parseFrameResult(resultJson)
            } catch (e: Exception) {
                throw if (e is SDKError) e else SDKError.vad("Frame processing failed: ${e.message}")
            }
        }
    }

    /**
     * Cancel an ongoing detection.
     */
    fun cancel() {
        synchronized(lock) {
            if (state != VADState.DETECTING) {
                return
            }

            isCancelled = true

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Cancelling detection",
            )

            RunAnywhereBridge.racVadComponentCancel(handle)
        }
    }

    /**
     * Reset the VAD state for a new stream.
     *
     * Call this when starting a new audio stream to clear internal buffers.
     */
    fun reset() {
        synchronized(lock) {
            if (handle == 0L) {
                return
            }

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Resetting VAD state",
            )

            RunAnywhereBridge.racVadComponentReset(handle)
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

            setState(VADState.UNLOADING)

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.INFO,
                TAG,
                "Unloading model: $previousModelId",
            )

            RunAnywhereBridge.racVadComponentUnload(handle)

            loadedModelId = null
            loadedModelPath = null
            setState(VADState.CREATED)

            // Update model assignment status
            CppBridgeModelAssignment.setAssignmentStatusCallback(
                CppBridgeModelRegistry.ModelType.VAD,
                CppBridgeModelAssignment.AssignmentStatus.NOT_ASSIGNED,
                CppBridgeModelAssignment.FailureReason.NONE,
            )

            // Update component state
            CppBridgeState.setComponentStateCallback(
                CppBridgeState.ComponentType.VAD,
                CppBridgeState.ComponentState.CREATED,
            )

            try {
                vadListener?.onModelUnloaded(previousModelId)
            } catch (e: Exception) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Error in VAD listener onModelUnloaded: ${e.message}",
                )
            }
        }
    }

    /**
     * Destroy the VAD component and release resources.
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
                "Destroying VAD component",
            )

            RunAnywhereBridge.racVadComponentDestroy(handle)

            handle = 0
            setState(VADState.NOT_CREATED)

            // Update component state
            CppBridgeState.setComponentStateCallback(
                CppBridgeState.ComponentType.VAD,
                CppBridgeState.ComponentState.NOT_CREATED,
            )
        }
    }

    // ========================================================================
    // JNI CALLBACKS
    // ========================================================================

    /**
     * Streaming frame callback.
     *
     * Called from C++ for each processed frame during streaming.
     *
     * @param isSpeech Whether speech is detected
     * @param probability Speech probability
     * @param eventType Event type (see [EventType])
     * @return true to continue detection, false to stop
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun streamFrameCallback(isSpeech: Boolean, probability: Float, eventType: Int): Boolean {
        if (isCancelled) {
            return false
        }

        val callback = streamCallback ?: return true

        // Create frame result for listener
        val frameResult =
            FrameResult(
                isSpeech = isSpeech,
                probability = probability,
                eventType = eventType,
                timestampMs = System.currentTimeMillis(),
            )

        // Notify listener
        try {
            vadListener?.onFrameResult(frameResult)
        } catch (e: Exception) {
            // Ignore listener errors
        }

        return try {
            callback.onFrame(isSpeech, probability, eventType)
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
     * Speech start callback.
     *
     * Called from C++ when speech is detected starting.
     *
     * @param timestampMs Timestamp in milliseconds
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun speechStartCallback(timestampMs: Long) {
        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.DEBUG,
            TAG,
            "Speech started at ${timestampMs}ms",
        )

        try {
            vadListener?.onSpeechStart(timestampMs)
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.WARN,
                TAG,
                "Error in VAD listener onSpeechStart: ${e.message}",
            )
        }
    }

    /**
     * Speech end callback.
     *
     * Called from C++ when speech is detected ending.
     *
     * @param startMs Segment start timestamp in milliseconds
     * @param endMs Segment end timestamp in milliseconds
     * @param confidence Confidence score
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun speechEndCallback(startMs: Long, endMs: Long, confidence: Float) {
        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.DEBUG,
            TAG,
            "Speech ended: ${startMs}ms - ${endMs}ms (confidence: $confidence)",
        )

        val segment = SpeechSegment(startMs, endMs, confidence)

        try {
            vadListener?.onSpeechEnd(endMs, segment)
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.WARN,
                TAG,
                "Error in VAD listener onSpeechEnd: ${e.message}",
            )
        }
    }

    /**
     * Progress callback.
     *
     * Called from C++ to report model loading progress.
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
            "Progress: ${(progress * 100).toInt()}%",
        )
    }

    /**
     * Get state callback.
     *
     * @return The current VAD component state
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
        return loadedModelId != null && state == VADState.READY
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
     * Native method to set the VAD callbacks with C++ core.
     *
     * Registers [streamFrameCallback], [speechStartCallback],
     * [speechEndCallback], [progressCallback], etc. with C++ core.
     * Reserved for future native callback integration.
     *
     * C API: rac_vad_set_callbacks(...)
     */
    @Suppress("unused")
    @JvmStatic
    private external fun nativeSetVADCallbacks()

    /**
     * Native method to unset the VAD callbacks.
     *
     * Called during shutdown to clean up native resources.
     * Reserved for future native callback integration.
     *
     * C API: rac_vad_set_callbacks(nullptr)
     */
    @Suppress("unused")
    @JvmStatic
    private external fun nativeUnsetVADCallbacks()

    /**
     * Native method to create the VAD component.
     *
     * @return Handle to the created component, or 0 on failure
     *
     * C API: rac_vad_component_create()
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
     * C API: rac_vad_component_load_model(handle, model_path, config)
     */
    @JvmStatic
    external fun nativeLoadModel(handle: Long, modelPath: String, configJson: String): Int

    /**
     * Native method to process audio data.
     *
     * @param handle The component handle
     * @param audioData Raw audio bytes
     * @param configJson JSON configuration string
     * @return JSON-encoded result, or null on failure
     *
     * C API: rac_vad_component_process(handle, audio_data, audio_size, config)
     */
    @JvmStatic
    external fun nativeProcess(handle: Long, audioData: ByteArray, configJson: String): String?

    /**
     * Native method to process audio with streaming.
     *
     * @param handle The component handle
     * @param audioData Raw audio bytes
     * @param configJson JSON configuration string
     * @return JSON-encoded result, or null on failure
     *
     * C API: rac_vad_component_process_stream(handle, audio_data, audio_size, config)
     */
    @JvmStatic
    external fun nativeProcessStream(handle: Long, audioData: ByteArray, configJson: String): String?

    /**
     * Native method to process a single audio frame.
     *
     * @param handle The component handle
     * @param audioData Raw audio bytes for the frame
     * @param configJson JSON configuration string
     * @return JSON-encoded result, or null on failure
     *
     * C API: rac_vad_component_process_frame(handle, audio_data, audio_size, config)
     */
    @JvmStatic
    external fun nativeProcessFrame(handle: Long, audioData: ByteArray, configJson: String): String?

    /**
     * Native method to cancel detection.
     *
     * @param handle The component handle
     *
     * C API: rac_vad_component_cancel(handle)
     */
    @JvmStatic
    external fun nativeCancel(handle: Long)

    /**
     * Native method to reset the VAD state.
     *
     * @param handle The component handle
     *
     * C API: rac_vad_component_reset(handle)
     */
    @JvmStatic
    external fun nativeReset(handle: Long)

    /**
     * Native method to unload the model.
     *
     * @param handle The component handle
     *
     * C API: rac_vad_component_unload(handle)
     */
    @JvmStatic
    external fun nativeUnload(handle: Long)

    /**
     * Native method to destroy the component.
     *
     * @param handle The component handle
     *
     * C API: rac_vad_component_destroy(handle)
     */
    @JvmStatic
    external fun nativeDestroy(handle: Long)

    /**
     * Native method to get the minimum frame size.
     *
     * @param handle The component handle
     * @return The minimum frame size in samples
     *
     * C API: rac_vad_component_get_min_frame_size(handle)
     */
    @JvmStatic
    external fun nativeGetMinFrameSize(handle: Long): Int

    /**
     * Native method to get the supported sample rates.
     *
     * @param handle The component handle
     * @return JSON array of supported sample rates
     *
     * C API: rac_vad_component_get_sample_rates(handle)
     */
    @JvmStatic
    external fun nativeGetSampleRates(handle: Long): String?

    // ========================================================================
    // LIFECYCLE MANAGEMENT
    // ========================================================================

    /**
     * Unregister the VAD callbacks and clean up resources.
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

            RunAnywhereBridge.racVadSetCallbacks(
                null,
                null,
                null,
                null,
            )

            vadListener = null
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
                "State changed: ${VADState.getName(previousState)} -> ${VADState.getName(newState)}",
            )

            try {
                vadListener?.onStateChanged(previousState, newState)
            } catch (e: Exception) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Error in VAD listener onStateChanged: ${e.message}",
                )
            }
        }
    }

    /**
     * Parse detection result from JSON.
     */
    private fun parseDetectionResult(json: String, elapsedMs: Long): DetectionResult {
        fun extractLong(key: String): Long {
            val pattern = "\"$key\"\\s*:\\s*(-?\\d+)"
            val regex = Regex(pattern)
            return regex
                .find(json)
                ?.groupValues
                ?.get(1)
                ?.toLongOrNull() ?: 0L
        }

        fun extractBoolean(key: String): Boolean {
            val pattern = "\"$key\"\\s*:\\s*(true|false)"
            val regex = Regex(pattern)
            return regex
                .find(json)
                ?.groupValues
                ?.get(1)
                ?.toBooleanStrictOrNull() ?: false
        }

        // Parse segments array
        val segments = mutableListOf<SpeechSegment>()
        val segmentsPattern = "\"segments\"\\s*:\\s*\\[([^\\]]*)]"
        val segmentsMatch = Regex(segmentsPattern).find(json)
        if (segmentsMatch != null) {
            val segmentsContent = segmentsMatch.groupValues[1]
            val segmentPattern = "\\{[^}]+\\}"
            Regex(segmentPattern).findAll(segmentsContent).forEach { match ->
                val segmentJson = match.value

                fun extractFromSegment(key: String): String? {
                    val p = "\"$key\"\\s*:\\s*(-?[\\d.]+)"
                    return Regex(p).find(segmentJson)?.groupValues?.get(1)
                }
                val startMs = extractFromSegment("start_ms")?.toLongOrNull() ?: 0L
                val endMs = extractFromSegment("end_ms")?.toLongOrNull() ?: 0L
                val confidence = extractFromSegment("confidence")?.toFloatOrNull() ?: 0f
                segments.add(SpeechSegment(startMs, endMs, confidence))
            }
        }

        val audioDurationMs = extractLong("audio_duration_ms")
        val hasSpeech = extractBoolean("has_speech")

        return DetectionResult(
            segments = segments,
            audioDurationMs = audioDurationMs,
            processingTimeMs = elapsedMs,
            hasSpeech = hasSpeech,
        )
    }

    /**
     * Parse frame result from JSON.
     */
    private fun parseFrameResult(json: String): FrameResult {
        fun extractBoolean(key: String): Boolean {
            val pattern = "\"$key\"\\s*:\\s*(true|false)"
            val regex = Regex(pattern)
            return regex
                .find(json)
                ?.groupValues
                ?.get(1)
                ?.toBooleanStrictOrNull() ?: false
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

        return FrameResult(
            isSpeech = extractBoolean("is_speech"),
            probability = extractFloat("probability"),
            eventType = extractInt("event_type"),
            timestampMs = extractLong("timestamp_ms"),
        )
    }

    /**
     * Get the minimum frame size for processing.
     *
     * @return The minimum frame size in samples, or 0 if model not loaded
     */
    fun getMinFrameSize(): Int {
        synchronized(lock) {
            if (handle == 0L || state != VADState.READY) {
                return 0
            }
            return RunAnywhereBridge.racVadComponentGetMinFrameSize(handle)
        }
    }

    /**
     * Get supported sample rates.
     *
     * @return List of supported sample rates, or empty list if model not loaded
     */
    fun getSupportedSampleRates(): List<Int> {
        synchronized(lock) {
            if (handle == 0L || state != VADState.READY) {
                return emptyList()
            }
            val json = RunAnywhereBridge.racVadComponentGetSampleRates(handle) ?: return emptyList()
            // Parse JSON array of integers
            val pattern = "\\d+"
            return Regex(pattern).findAll(json).map { it.value.toInt() }.toList()
        }
    }

    /**
     * Get a state summary for diagnostics.
     *
     * @return Human-readable state summary
     */
    fun getStateSummary(): String {
        return buildString {
            append("VAD State: ${VADState.getName(state)}")
            if (loadedModelId != null) {
                append(", Model: $loadedModelId")
            }
            if (handle != 0L) {
                append(", Handle: $handle")
            }
        }
    }
}
