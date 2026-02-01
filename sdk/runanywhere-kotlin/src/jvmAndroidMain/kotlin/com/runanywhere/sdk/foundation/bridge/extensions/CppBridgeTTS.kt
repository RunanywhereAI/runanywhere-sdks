/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * TTS extension for CppBridge.
 * Provides Text-to-Speech component lifecycle management for C++ core.
 *
 * Follows iOS CppBridge+TTS.swift architecture.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import com.runanywhere.sdk.foundation.bridge.CppBridge
import com.runanywhere.sdk.foundation.errors.SDKError
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge

/**
 * TTS bridge that provides Text-to-Speech component lifecycle management for C++ core.
 *
 * The C++ core needs TTS component management for:
 * - Creating and destroying TTS instances
 * - Loading and unloading models
 * - Text synthesis (standard and streaming)
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
object CppBridgeTTS {
    /**
     * TTS component state constants matching C++ RAC_TTS_STATE_* values.
     */
    object TTSState {
        /** Component not created */
        const val NOT_CREATED = 0

        /** Component created but no model loaded */
        const val CREATED = 1

        /** Model is loading */
        const val LOADING = 2

        /** Model loaded and ready for synthesis */
        const val READY = 3

        /** Synthesis in progress */
        const val SYNTHESIZING = 4

        /** Model is unloading */
        const val UNLOADING = 5

        /** Component in error state */
        const val ERROR = 6

        /**
         * Get a human-readable name for the TTS state.
         */
        fun getName(state: Int): String =
            when (state) {
                NOT_CREATED -> "NOT_CREATED"
                CREATED -> "CREATED"
                LOADING -> "LOADING"
                READY -> "READY"
                SYNTHESIZING -> "SYNTHESIZING"
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
     * Audio output format constants for TTS.
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

        /** Opus/OGG format */
        const val OPUS = 4

        /** AAC format */
        const val AAC = 5

        /**
         * Get a human-readable name for the audio format.
         */
        fun getName(format: Int): String =
            when (format) {
                PCM_16 -> "PCM_16"
                PCM_FLOAT -> "PCM_FLOAT"
                WAV -> "WAV"
                MP3 -> "MP3"
                OPUS -> "OPUS"
                AAC -> "AAC"
                else -> "UNKNOWN($format)"
            }
    }

    /**
     * Language code constants.
     */
    object Language {
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
     * Synthesis completion reason constants.
     */
    object CompletionReason {
        /** Synthesis still in progress */
        const val NOT_COMPLETED = 0

        /** End of text reached */
        const val END_OF_TEXT = 1

        /** Synthesis was cancelled */
        const val CANCELLED = 2

        /** Maximum duration reached */
        const val MAX_DURATION = 3

        /** Synthesis failed */
        const val ERROR = 4

        /**
         * Get a human-readable name for the completion reason.
         */
        fun getName(reason: Int): String =
            when (reason) {
                NOT_COMPLETED -> "NOT_COMPLETED"
                END_OF_TEXT -> "END_OF_TEXT"
                CANCELLED -> "CANCELLED"
                MAX_DURATION -> "MAX_DURATION"
                ERROR -> "ERROR"
                else -> "UNKNOWN($reason)"
            }
    }

    @Volatile
    private var isRegistered: Boolean = false

    @Volatile
    private var state: Int = TTSState.NOT_CREATED

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
    private const val TAG = "CppBridgeTTS"

    /**
     * Singleton shared instance for accessing the TTS component.
     * Matches iOS CppBridge.TTS.shared pattern.
     */
    val shared: CppBridgeTTS = this

    /**
     * Optional listener for TTS events.
     * Set this before calling [register] to receive events.
     */
    @Volatile
    var ttsListener: TTSListener? = null

    /**
     * Optional streaming callback for audio chunk output.
     * This is invoked for each audio chunk during streaming synthesis.
     */
    @Volatile
    var streamCallback: StreamCallback? = null

    /**
     * TTS synthesis configuration.
     *
     * @param language Language code (e.g., "en", "es")
     * @param voiceId Voice identifier (model-specific)
     * @param speed Speaking rate multiplier (0.5 to 2.0, 1.0 = normal)
     * @param pitch Pitch adjustment (-1.0 to 1.0, 0.0 = normal)
     * @param volume Volume level (0.0 to 1.0)
     * @param sampleRate Output audio sample rate in Hz (default: 22050)
     * @param audioFormat Output audio format
     * @param maxDurationMs Maximum synthesis duration in milliseconds (0 = unlimited)
     */
    data class SynthesisConfig(
        val language: String = Language.ENGLISH,
        val voiceId: String = "",
        val speed: Float = 1.0f,
        val pitch: Float = 0.0f,
        val volume: Float = 1.0f,
        val sampleRate: Int = 22050,
        val audioFormat: Int = AudioFormat.PCM_16,
        val maxDurationMs: Long = 0,
    ) {
        /**
         * Convert to JSON string for C++ interop.
         */
        fun toJson(): String {
            return buildString {
                append("{")
                append("\"language\":\"${escapeJson(language)}\",")
                append("\"voice_id\":\"${escapeJson(voiceId)}\",")
                append("\"speed\":$speed,")
                append("\"pitch\":$pitch,")
                append("\"volume\":$volume,")
                append("\"sample_rate\":$sampleRate,")
                append("\"audio_format\":$audioFormat,")
                append("\"max_duration_ms\":$maxDurationMs")
                append("}")
            }
        }

        companion object {
            /** Default configuration */
            val DEFAULT = SynthesisConfig()
        }
    }

    /**
     * TTS model configuration.
     *
     * @param threads Number of threads for inference (-1 for auto)
     * @param gpuEnabled Whether to use GPU acceleration
     * @param useFlashAttention Whether to use flash attention optimization
     */
    data class ModelConfig(
        val threads: Int = -1,
        val gpuEnabled: Boolean = false,
        val useFlashAttention: Boolean = true,
    ) {
        /**
         * Convert to JSON string for C++ interop.
         */
        fun toJson(): String {
            return buildString {
                append("{")
                append("\"threads\":$threads,")
                append("\"gpu_enabled\":$gpuEnabled,")
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
     * Voice information data class.
     *
     * @param voiceId Unique voice identifier
     * @param name Human-readable voice name
     * @param language Language code this voice supports
     * @param gender Voice gender ("male", "female", "neutral")
     * @param quality Voice quality tier ("standard", "premium", "neural")
     */
    data class VoiceInfo(
        val voiceId: String,
        val name: String,
        val language: String,
        val gender: String,
        val quality: String,
    )

    /**
     * TTS synthesis result.
     *
     * @param audioData Synthesized audio data bytes
     * @param text Original input text
     * @param durationMs Audio duration in milliseconds
     * @param completionReason Reason for synthesis completion
     * @param sampleRate Audio sample rate in Hz
     * @param audioFormat Audio format used
     * @param processingTimeMs Time spent processing in milliseconds
     */
    data class SynthesisResult(
        val audioData: ByteArray,
        val text: String,
        val durationMs: Long,
        val completionReason: Int,
        val sampleRate: Int,
        val audioFormat: Int,
        val processingTimeMs: Long,
    ) {
        /**
         * Get the completion reason name.
         */
        fun getCompletionReasonName(): String = CompletionReason.getName(completionReason)

        /**
         * Check if synthesis completed successfully.
         */
        fun isComplete(): Boolean = completionReason == CompletionReason.END_OF_TEXT

        /**
         * Check if synthesis was cancelled.
         */
        fun wasCancelled(): Boolean = completionReason == CompletionReason.CANCELLED

        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (other !is SynthesisResult) return false
            if (!audioData.contentEquals(other.audioData)) return false
            if (text != other.text) return false
            if (durationMs != other.durationMs) return false
            if (completionReason != other.completionReason) return false
            if (sampleRate != other.sampleRate) return false
            if (audioFormat != other.audioFormat) return false
            if (processingTimeMs != other.processingTimeMs) return false
            return true
        }

        override fun hashCode(): Int {
            var result = audioData.contentHashCode()
            result = 31 * result + text.hashCode()
            result = 31 * result + durationMs.hashCode()
            result = 31 * result + completionReason
            result = 31 * result + sampleRate
            result = 31 * result + audioFormat
            result = 31 * result + processingTimeMs.hashCode()
            return result
        }
    }

    /**
     * Audio chunk for streaming synthesis.
     *
     * @param audioData Audio data bytes for this chunk
     * @param isFinal Whether this is the final chunk
     * @param chunkIndex Index of this chunk in the sequence
     */
    data class AudioChunk(
        val audioData: ByteArray,
        val isFinal: Boolean,
        val chunkIndex: Int,
    ) {
        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (other !is AudioChunk) return false
            if (!audioData.contentEquals(other.audioData)) return false
            if (isFinal != other.isFinal) return false
            if (chunkIndex != other.chunkIndex) return false
            return true
        }

        override fun hashCode(): Int {
            var result = audioData.contentHashCode()
            result = 31 * result + isFinal.hashCode()
            result = 31 * result + chunkIndex
            return result
        }
    }

    /**
     * Listener interface for TTS events.
     */
    interface TTSListener {
        /**
         * Called when the TTS component state changes.
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
         * Called when synthesis starts.
         *
         * @param text The input text
         */
        fun onSynthesisStarted(text: String)

        /**
         * Called when synthesis completes.
         *
         * @param result The synthesis result
         */
        fun onSynthesisCompleted(result: SynthesisResult)

        /**
         * Called when an audio chunk is available during streaming.
         *
         * @param chunk The audio chunk
         */
        fun onAudioChunk(chunk: AudioChunk)

        /**
         * Called when an error occurs.
         *
         * @param errorCode The error code
         * @param errorMessage The error message
         */
        fun onError(errorCode: Int, errorMessage: String)
    }

    /**
     * Callback interface for streaming audio output.
     */
    fun interface StreamCallback {
        /**
         * Called for each audio chunk.
         *
         * @param audioData The audio data bytes
         * @param isFinal Whether this is the final chunk
         * @return true to continue synthesis, false to stop
         */
        fun onAudioChunk(audioData: ByteArray, isFinal: Boolean): Boolean
    }

    /**
     * Register the TTS callbacks with C++ core.
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
            // nativeSetTTSCallbacks()

            isRegistered = true

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "TTS callbacks registered",
            )
        }
    }

    /**
     * Check if the TTS callbacks are registered.
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
                throw SDKError.notInitialized("TTS component not created")
            }
            return handle
        }
    }

    /**
     * Check if a model is loaded.
     */
    val isLoaded: Boolean
        get() = synchronized(lock) { state == TTSState.READY && loadedModelId != null }

    /**
     * Check if the component is ready for synthesis.
     */
    val isReady: Boolean
        get() = TTSState.isReady(state)

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
     * Create the TTS component.
     *
     * @return 0 on success, error code on failure
     */
    fun create(): Int {
        synchronized(lock) {
            if (handle != 0L) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "TTS component already created",
                )
                return 0
            }

            // Check if native commons library is loaded
            if (!CppBridge.isNativeLibraryLoaded) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.ERROR,
                    TAG,
                    "Native library not loaded. TTS inference requires native libraries to be bundled.",
                )
                throw SDKError.notInitialized("Native library not available. Please ensure the native libraries are bundled in your APK.")
            }

            // Create TTS component via RunAnywhereBridge
            val result =
                try {
                    RunAnywhereBridge.racTtsComponentCreate()
                } catch (e: UnsatisfiedLinkError) {
                    CppBridgePlatformAdapter.logCallback(
                        CppBridgePlatformAdapter.LogLevel.ERROR,
                        TAG,
                        "TTS component creation failed. Native method not available: ${e.message}",
                    )
                    throw SDKError.notInitialized("TTS native library not available. Please ensure the TTS backend is bundled in your APK.")
                }

            if (result == 0L) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.ERROR,
                    TAG,
                    "Failed to create TTS component",
                )
                return -1
            }

            handle = result
            setState(TTSState.CREATED)

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.INFO,
                TAG,
                "TTS component created",
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

            setState(TTSState.LOADING)

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.INFO,
                TAG,
                "Loading model: $modelId from $modelPath",
            )

            val result = RunAnywhereBridge.racTtsComponentLoadModel(handle, modelPath, modelId, modelName)
            if (result != 0) {
                setState(TTSState.ERROR)
                
                // Get error code meaning
                val errorMeaning = when (result) {
                    -400 -> "NULL_POINTER"
                    -401 -> "INVALID_ARGUMENT"
                    -402 -> "INVALID_HANDLE"
                    -410 -> "MODEL_NOT_FOUND"
                    -411 -> "MODEL_LOAD_FAILED"
                    -412 -> "MODEL_INVALID"
                    -420 -> "BACKEND_NOT_AVAILABLE"
                    -421 -> "BACKEND_INIT_FAILED"
                    -422 -> "NO_CAPABLE_PROVIDER"
                    -430 -> "INFERENCE_FAILED"
                    else -> "UNKNOWN"
                }
                
                val errorMsg = "Failed to load TTS model '$modelId' (error: $result = $errorMeaning). Path: $modelPath"
                
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.ERROR,
                    TAG,
                    errorMsg,
                )

                try {
                    ttsListener?.onError(result, errorMsg)
                } catch (e: Exception) {
                    // Ignore listener errors
                }

                return result
            }

            loadedModelId = modelId
            loadedModelPath = modelPath
            setState(TTSState.READY)

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.INFO,
                TAG,
                "Model loaded successfully: $modelId",
            )

            // Update model assignment status
            CppBridgeModelAssignment.setAssignmentStatusCallback(
                CppBridgeModelRegistry.ModelType.TTS,
                CppBridgeModelAssignment.AssignmentStatus.READY,
                CppBridgeModelAssignment.FailureReason.NONE,
            )

            // Update component state
            CppBridgeState.setComponentStateCallback(
                CppBridgeState.ComponentType.TTS,
                CppBridgeState.ComponentState.READY,
            )

            try {
                ttsListener?.onModelLoaded(modelId, modelPath)
            } catch (e: Exception) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Error in TTS listener onModelLoaded: ${e.message}",
                )
            }

            return 0
        }
    }

    /**
     * Synthesize audio from text.
     *
     * @param text The input text to synthesize
     * @param config Synthesis configuration (optional)
     * @return The synthesis result
     * @throws SDKError if synthesis fails
     */
    @Throws(SDKError::class)
    fun synthesize(text: String, config: SynthesisConfig = SynthesisConfig.DEFAULT): SynthesisResult {
        synchronized(lock) {
            if (handle == 0L || state != TTSState.READY) {
                throw SDKError.tts("TTS component not ready for synthesis")
            }

            isCancelled = false
            setState(TTSState.SYNTHESIZING)

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Starting synthesis (text length: ${text.length})",
            )

            try {
                ttsListener?.onSynthesisStarted(text)
            } catch (e: Exception) {
                // Ignore listener errors
            }

            val startTime = System.currentTimeMillis()

            try {
                val rawAudioData =
                    RunAnywhereBridge.racTtsComponentSynthesize(handle, text, config.toJson())
                        ?: throw SDKError.tts("Synthesis failed: null result")

                // TTS backends output Float32 PCM - convert to WAV for playback compatibility
                val audioData =
                    RunAnywhereBridge.racAudioFloat32ToWav(rawAudioData, config.sampleRate)
                        ?: throw SDKError.tts("Failed to convert audio to WAV format")

                val processingTimeMs = System.currentTimeMillis() - startTime

                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.DEBUG,
                    TAG,
                    "Converted ${rawAudioData.size} bytes Float32 PCM to ${audioData.size} bytes WAV",
                )

                // Calculate approximate duration based on WAV data size (minus 44-byte header) and sample rate
                // WAV is Int16 (2 bytes per sample) mono, so samples = (size - 44) / 2
                val durationMs = calculateWavDuration(audioData.size, config.sampleRate)

                val result =
                    SynthesisResult(
                        audioData = audioData,
                        text = text,
                        durationMs = durationMs,
                        completionReason = CompletionReason.END_OF_TEXT,
                        sampleRate = config.sampleRate,
                        audioFormat = AudioFormat.WAV, // Output is now WAV format
                        processingTimeMs = processingTimeMs,
                    )

                setState(TTSState.READY)

                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.DEBUG,
                    TAG,
                    "Synthesis completed: ${audioData.size} bytes WAV, ${result.durationMs}ms audio",
                )

                try {
                    ttsListener?.onSynthesisCompleted(result)
                } catch (e: Exception) {
                    // Ignore listener errors
                }

                return result
            } catch (e: Exception) {
                setState(TTSState.READY) // Reset to ready, not error
                throw if (e is SDKError) e else SDKError.tts("Synthesis failed: ${e.message}")
            }
        }
    }

    /**
     * Synthesize audio with streaming output.
     *
     * @param text The input text to synthesize
     * @param config Synthesis configuration (optional)
     * @param callback Callback for audio chunks
     * @return The final synthesis result
     * @throws SDKError if synthesis fails
     */
    @Throws(SDKError::class)
    fun synthesizeStream(
        text: String,
        config: SynthesisConfig = SynthesisConfig.DEFAULT,
        callback: StreamCallback,
    ): SynthesisResult {
        synchronized(lock) {
            if (handle == 0L || state != TTSState.READY) {
                throw SDKError.tts("TTS component not ready for synthesis")
            }

            isCancelled = false
            streamCallback = callback
            setState(TTSState.SYNTHESIZING)

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Starting streaming synthesis (text length: ${text.length})",
            )

            try {
                ttsListener?.onSynthesisStarted(text)
            } catch (e: Exception) {
                // Ignore listener errors
            }

            val startTime = System.currentTimeMillis()

            try {
                val rawAudioData =
                    RunAnywhereBridge.racTtsComponentSynthesizeStream(handle, text, config.toJson())
                        ?: throw SDKError.tts("Streaming synthesis failed: null result")

                // TTS backends output Float32 PCM - convert to WAV for playback compatibility
                val audioData =
                    RunAnywhereBridge.racAudioFloat32ToWav(rawAudioData, config.sampleRate)
                        ?: throw SDKError.tts("Failed to convert streaming audio to WAV format")

                val processingTimeMs = System.currentTimeMillis() - startTime

                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.DEBUG,
                    TAG,
                    "Converted ${rawAudioData.size} bytes Float32 PCM to ${audioData.size} bytes WAV (streaming)",
                )

                val durationMs = calculateWavDuration(audioData.size, config.sampleRate)

                val result =
                    SynthesisResult(
                        audioData = audioData,
                        text = text,
                        durationMs = durationMs,
                        completionReason = if (isCancelled) CompletionReason.CANCELLED else CompletionReason.END_OF_TEXT,
                        sampleRate = config.sampleRate,
                        audioFormat = AudioFormat.WAV, // Output is now WAV format
                        processingTimeMs = processingTimeMs,
                    )

                setState(TTSState.READY)
                streamCallback = null

                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.DEBUG,
                    TAG,
                    "Streaming synthesis completed: ${audioData.size} bytes WAV",
                )

                try {
                    ttsListener?.onSynthesisCompleted(result)
                } catch (e: Exception) {
                    // Ignore listener errors
                }

                return result
            } catch (e: Exception) {
                setState(TTSState.READY) // Reset to ready, not error
                streamCallback = null
                throw if (e is SDKError) e else SDKError.tts("Streaming synthesis failed: ${e.message}")
            }
        }
    }

    /**
     * Synthesize audio and save to file.
     *
     * @param text The input text to synthesize
     * @param outputPath Path to save the audio file
     * @param config Synthesis configuration (optional)
     * @return The synthesis result (with empty audioData, as it's saved to file)
     * @throws SDKError if synthesis fails
     */
    @Throws(SDKError::class)
    fun synthesizeToFile(
        text: String,
        outputPath: String,
        config: SynthesisConfig = SynthesisConfig.DEFAULT,
    ): SynthesisResult {
        synchronized(lock) {
            if (handle == 0L || state != TTSState.READY) {
                throw SDKError.tts("TTS component not ready for synthesis")
            }

            isCancelled = false
            setState(TTSState.SYNTHESIZING)

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Starting synthesis to file: $outputPath (text length: ${text.length})",
            )

            try {
                ttsListener?.onSynthesisStarted(text)
            } catch (e: Exception) {
                // Ignore listener errors
            }

            val startTime = System.currentTimeMillis()

            try {
                val durationMs = RunAnywhereBridge.racTtsComponentSynthesizeToFile(handle, text, outputPath, config.toJson())
                if (durationMs < 0) {
                    throw SDKError.tts("Synthesis to file failed: error code $durationMs")
                }

                val processingTimeMs = System.currentTimeMillis() - startTime

                val result =
                    SynthesisResult(
                        audioData = ByteArray(0), // Empty since saved to file
                        text = text,
                        durationMs = durationMs,
                        completionReason = CompletionReason.END_OF_TEXT,
                        sampleRate = config.sampleRate,
                        audioFormat = config.audioFormat,
                        processingTimeMs = processingTimeMs,
                    )

                setState(TTSState.READY)

                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.DEBUG,
                    TAG,
                    "Synthesis to file completed: $outputPath, ${durationMs}ms audio",
                )

                try {
                    ttsListener?.onSynthesisCompleted(result)
                } catch (e: Exception) {
                    // Ignore listener errors
                }

                return result
            } catch (e: Exception) {
                setState(TTSState.READY) // Reset to ready, not error
                throw if (e is SDKError) e else SDKError.tts("Synthesis to file failed: ${e.message}")
            }
        }
    }

    /**
     * Cancel an ongoing synthesis.
     */
    fun cancel() {
        synchronized(lock) {
            if (state != TTSState.SYNTHESIZING) {
                return
            }

            isCancelled = true

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Cancelling synthesis",
            )

            RunAnywhereBridge.racTtsComponentCancel(handle)
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

            setState(TTSState.UNLOADING)

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.INFO,
                TAG,
                "Unloading model: $previousModelId",
            )

            RunAnywhereBridge.racTtsComponentUnload(handle)

            loadedModelId = null
            loadedModelPath = null
            setState(TTSState.CREATED)

            // Update model assignment status
            CppBridgeModelAssignment.setAssignmentStatusCallback(
                CppBridgeModelRegistry.ModelType.TTS,
                CppBridgeModelAssignment.AssignmentStatus.NOT_ASSIGNED,
                CppBridgeModelAssignment.FailureReason.NONE,
            )

            // Update component state
            CppBridgeState.setComponentStateCallback(
                CppBridgeState.ComponentType.TTS,
                CppBridgeState.ComponentState.CREATED,
            )

            try {
                ttsListener?.onModelUnloaded(previousModelId)
            } catch (e: Exception) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Error in TTS listener onModelUnloaded: ${e.message}",
                )
            }
        }
    }

    /**
     * Destroy the TTS component and release resources.
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
                "Destroying TTS component",
            )

            RunAnywhereBridge.racTtsComponentDestroy(handle)

            handle = 0
            setState(TTSState.NOT_CREATED)

            // Update component state
            CppBridgeState.setComponentStateCallback(
                CppBridgeState.ComponentType.TTS,
                CppBridgeState.ComponentState.NOT_CREATED,
            )
        }
    }

    // ========================================================================
    // JNI CALLBACKS
    // ========================================================================

    /**
     * Streaming audio chunk callback.
     *
     * Called from C++ for each audio chunk during streaming synthesis.
     *
     * @param audioData The audio data bytes for this chunk
     * @param isFinal Whether this is the final chunk
     * @return true to continue synthesis, false to stop
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun streamAudioCallback(audioData: ByteArray, isFinal: Boolean): Boolean {
        if (isCancelled) {
            return false
        }

        val callback = streamCallback ?: return true

        // Notify listener
        try {
            ttsListener?.onAudioChunk(AudioChunk(audioData, isFinal, -1))
        } catch (e: Exception) {
            // Ignore listener errors
        }

        return try {
            callback.onAudioChunk(audioData, isFinal)
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
     * Called from C++ to report model loading or synthesis progress.
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
     * @return The current TTS component state
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
        return loadedModelId != null && state == TTSState.READY
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
     * Native method to set the TTS callbacks with C++ core.
     *
     * Registers [streamAudioCallback], [progressCallback], etc. with C++ core.
     * Reserved for future native callback integration.
     *
     * C API: rac_tts_set_callbacks(...)
     */
    @Suppress("unused")
    @JvmStatic
    private external fun nativeSetTTSCallbacks()

    /**
     * Native method to unset the TTS callbacks.
     *
     * Called during shutdown to clean up native resources.
     * Reserved for future native callback integration.
     *
     * C API: rac_tts_set_callbacks(nullptr)
     */
    @Suppress("unused")
    @JvmStatic
    private external fun nativeUnsetTTSCallbacks()

    /**
     * Native method to create the TTS component.
     *
     * @return Handle to the created component, or 0 on failure
     *
     * C API: rac_tts_component_create()
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
     * C API: rac_tts_component_load_model(handle, model_path, config)
     */
    @JvmStatic
    external fun nativeLoadModel(handle: Long, modelPath: String, configJson: String): Int

    /**
     * Native method to synthesize audio from text.
     *
     * @param handle The component handle
     * @param text The input text
     * @param configJson JSON configuration string
     * @return Audio data bytes, or null on failure
     *
     * C API: rac_tts_component_synthesize(handle, text, config)
     */
    @JvmStatic
    external fun nativeSynthesize(handle: Long, text: String, configJson: String): ByteArray?

    /**
     * Native method to synthesize audio with streaming.
     *
     * @param handle The component handle
     * @param text The input text
     * @param configJson JSON configuration string
     * @return Final audio data bytes, or null on failure
     *
     * C API: rac_tts_component_synthesize_stream(handle, text, config)
     */
    @JvmStatic
    external fun nativeSynthesizeStream(handle: Long, text: String, configJson: String): ByteArray?

    /**
     * Native method to synthesize audio to file.
     *
     * @param handle The component handle
     * @param text The input text
     * @param outputPath Path to save the audio file
     * @param configJson JSON configuration string
     * @return Audio duration in milliseconds, or negative error code on failure
     *
     * C API: rac_tts_component_synthesize_to_file(handle, text, output_path, config)
     */
    @JvmStatic
    external fun nativeSynthesizeToFile(handle: Long, text: String, outputPath: String, configJson: String): Long

    /**
     * Native method to cancel synthesis.
     *
     * @param handle The component handle
     *
     * C API: rac_tts_component_cancel(handle)
     */
    @JvmStatic
    external fun nativeCancel(handle: Long)

    /**
     * Native method to unload the model.
     *
     * @param handle The component handle
     *
     * C API: rac_tts_component_unload(handle)
     */
    @JvmStatic
    external fun nativeUnload(handle: Long)

    /**
     * Native method to destroy the component.
     *
     * @param handle The component handle
     *
     * C API: rac_tts_component_destroy(handle)
     */
    @JvmStatic
    external fun nativeDestroy(handle: Long)

    /**
     * Native method to get available voices.
     *
     * @param handle The component handle
     * @return JSON array of voice information
     *
     * C API: rac_tts_component_get_voices(handle)
     */
    @JvmStatic
    external fun nativeGetVoices(handle: Long): String?

    /**
     * Native method to set the active voice.
     *
     * @param handle The component handle
     * @param voiceId The voice ID to use
     * @return 0 on success, error code on failure
     *
     * C API: rac_tts_component_set_voice(handle, voice_id)
     */
    @JvmStatic
    external fun nativeSetVoice(handle: Long, voiceId: String): Int

    /**
     * Native method to get supported languages.
     *
     * @param handle The component handle
     * @return JSON array of supported language codes
     *
     * C API: rac_tts_component_get_languages(handle)
     */
    @JvmStatic
    external fun nativeGetLanguages(handle: Long): String?

    // ========================================================================
    // LIFECYCLE MANAGEMENT
    // ========================================================================

    /**
     * Unregister the TTS callbacks and clean up resources.
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
            // nativeUnsetTTSCallbacks()

            ttsListener = null
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
                "State changed: ${TTSState.getName(previousState)} -> ${TTSState.getName(newState)}",
            )

            try {
                ttsListener?.onStateChanged(previousState, newState)
            } catch (e: Exception) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Error in TTS listener onStateChanged: ${e.message}",
                )
            }
        }
    }

    /**
     * Calculate approximate audio duration from data size.
     * Reserved for future audio duration estimation.
     */
    @Suppress("unused")
    private fun calculateAudioDuration(dataSize: Int, sampleRate: Int, audioFormat: Int): Long {
        // Calculate based on audio format
        val bytesPerSample =
            when (audioFormat) {
                AudioFormat.PCM_16 -> 2
                AudioFormat.PCM_FLOAT -> 4
                else -> 2 // Default to 16-bit PCM
            }

        // Assuming mono audio
        val samples = dataSize / bytesPerSample
        return (samples * 1000L) / sampleRate
    }

    /**
     * Calculate audio duration from WAV file data.
     * WAV format: 44-byte header + Int16 PCM samples (2 bytes per sample, mono)
     */
    private fun calculateWavDuration(wavSize: Int, sampleRate: Int): Long {
        // WAV header is 44 bytes, data is Int16 (2 bytes per sample), mono
        val headerSize = 44
        val bytesPerSample = 2
        val pcmSize = (wavSize - headerSize).coerceAtLeast(0)
        val samples = pcmSize / bytesPerSample
        return (samples * 1000L) / sampleRate
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
     * Get available voices.
     *
     * @return List of available voice information, or empty list if model not loaded
     */
    fun getAvailableVoices(): List<VoiceInfo> {
        synchronized(lock) {
            if (handle == 0L || state != TTSState.READY) {
                return emptyList()
            }
            val json = RunAnywhereBridge.racTtsComponentGetVoices(handle) ?: return emptyList()
            return parseVoicesJson(json)
        }
    }

    /**
     * Set the active voice.
     *
     * @param voiceId The voice ID to use
     * @return true if successful
     */
    fun setVoice(voiceId: String): Boolean {
        synchronized(lock) {
            if (handle == 0L || state != TTSState.READY) {
                return false
            }
            return RunAnywhereBridge.racTtsComponentSetVoice(handle, voiceId) == 0
        }
    }

    /**
     * Get supported languages.
     *
     * @return List of supported language codes, or empty list if model not loaded
     */
    fun getSupportedLanguages(): List<String> {
        synchronized(lock) {
            if (handle == 0L || state != TTSState.READY) {
                return emptyList()
            }
            val json = RunAnywhereBridge.racTtsComponentGetLanguages(handle) ?: return emptyList()
            // Parse JSON array
            val pattern = "\"([^\"]+)\""
            return Regex(pattern).findAll(json).map { it.groupValues[1] }.toList()
        }
    }

    /**
     * Parse voices JSON to list of VoiceInfo.
     */
    private fun parseVoicesJson(json: String): List<VoiceInfo> {
        val voices = mutableListOf<VoiceInfo>()

        // Simple JSON array parsing
        val voicePattern = "\\{[^}]+\\}"
        val voiceMatches = Regex(voicePattern).findAll(json)

        for (match in voiceMatches) {
            val voiceJson = match.value

            fun extractString(key: String): String {
                val pattern = "\"$key\"\\s*:\\s*\"([^\"]*)\""
                return Regex(pattern).find(voiceJson)?.groupValues?.get(1) ?: ""
            }

            voices.add(
                VoiceInfo(
                    voiceId = extractString("voice_id").ifEmpty { extractString("id") },
                    name = extractString("name"),
                    language = extractString("language"),
                    gender = extractString("gender"),
                    quality = extractString("quality"),
                ),
            )
        }

        return voices
    }

    /**
     * Get a state summary for diagnostics.
     *
     * @return Human-readable state summary
     */
    fun getStateSummary(): String {
        return buildString {
            append("TTS State: ${TTSState.getName(state)}")
            if (loadedModelId != null) {
                append(", Model: $loadedModelId")
            }
            if (handle != 0L) {
                append(", Handle: $handle")
            }
        }
    }
}
