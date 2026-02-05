/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Voice Agent extension for CppBridge.
 * Provides Voice Agent pipeline management for C++ core.
 *
 * Follows iOS CppBridge+VoiceAgent.swift architecture.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import com.runanywhere.sdk.foundation.errors.SDKError
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge

/**
 * Voice Agent bridge that provides conversational AI pipeline management for C++ core.
 *
 * The Voice Agent orchestrates:
 * - Voice Activity Detection (VAD) for speech detection
 * - Speech-to-Text (STT) for transcription
 * - Large Language Model (LLM) for response generation
 * - Text-to-Speech (TTS) for audio synthesis
 *
 * The C++ core needs Voice Agent management for:
 * - Creating and destroying Voice Agent instances
 * - Initializing the voice pipeline with component models
 * - Processing voice turns (full conversation loop)
 * - Individual pipeline operations (detect, transcribe, generate, synthesize)
 * - Canceling ongoing operations
 * - Component state tracking
 *
 * Usage:
 * - Called during Phase 2 initialization in [CppBridge.initializeServices]
 * - Must be registered after AI component bridges (LLM, STT, TTS, VAD) are registered
 *
 * Thread Safety:
 * - This object is thread-safe via synchronized blocks
 * - All callbacks are thread-safe
 * - Matches iOS Actor-based pattern using Kotlin synchronized
 */
object CppBridgeVoiceAgent {
    /**
     * Voice Agent state constants matching C++ RAC_VOICE_AGENT_STATE_* values.
     */
    object VoiceAgentState {
        /** Agent not created */
        const val NOT_CREATED = 0

        /** Agent created but not initialized */
        const val CREATED = 1

        /** Agent is initializing (loading models) */
        const val INITIALIZING = 2

        /** Agent initialized and ready */
        const val READY = 3

        /** Agent is listening for speech */
        const val LISTENING = 4

        /** Agent is processing speech (STT) */
        const val TRANSCRIBING = 5

        /** Agent is generating response (LLM) */
        const val GENERATING = 6

        /** Agent is speaking (TTS) */
        const val SPEAKING = 7

        /** Agent is processing a complete turn */
        const val PROCESSING_TURN = 8

        /** Agent in error state */
        const val ERROR = 9

        /**
         * Get a human-readable name for the Voice Agent state.
         */
        fun getName(state: Int): String =
            when (state) {
                NOT_CREATED -> "NOT_CREATED"
                CREATED -> "CREATED"
                INITIALIZING -> "INITIALIZING"
                READY -> "READY"
                LISTENING -> "LISTENING"
                TRANSCRIBING -> "TRANSCRIBING"
                GENERATING -> "GENERATING"
                SPEAKING -> "SPEAKING"
                PROCESSING_TURN -> "PROCESSING_TURN"
                ERROR -> "ERROR"
                else -> "UNKNOWN($state)"
            }

        /**
         * Check if the state indicates the agent is ready.
         */
        fun isReady(state: Int): Boolean = state == READY

        /**
         * Check if the state indicates the agent is processing.
         */
        fun isProcessing(state: Int): Boolean = state in LISTENING..PROCESSING_TURN
    }

    /**
     * Turn phase constants for tracking conversation flow.
     */
    object TurnPhase {
        /** No active turn */
        const val IDLE = 0

        /** Detecting speech activity */
        const val SPEECH_DETECTION = 1

        /** Transcribing speech to text */
        const val TRANSCRIPTION = 2

        /** Generating LLM response */
        const val RESPONSE_GENERATION = 3

        /** Synthesizing speech from response */
        const val SPEECH_SYNTHESIS = 4

        /** Turn completed */
        const val COMPLETED = 5

        /** Turn cancelled */
        const val CANCELLED = 6

        /** Turn failed */
        const val FAILED = 7

        /**
         * Get a human-readable name for the turn phase.
         */
        fun getName(phase: Int): String =
            when (phase) {
                IDLE -> "IDLE"
                SPEECH_DETECTION -> "SPEECH_DETECTION"
                TRANSCRIPTION -> "TRANSCRIPTION"
                RESPONSE_GENERATION -> "RESPONSE_GENERATION"
                SPEECH_SYNTHESIS -> "SPEECH_SYNTHESIS"
                COMPLETED -> "COMPLETED"
                CANCELLED -> "CANCELLED"
                FAILED -> "FAILED"
                else -> "UNKNOWN($phase)"
            }
    }

    /**
     * Turn completion reason constants.
     */
    object CompletionReason {
        /** Turn completed successfully */
        const val SUCCESS = 0

        /** Turn was cancelled by user */
        const val CANCELLED = 1

        /** No speech detected */
        const val NO_SPEECH = 2

        /** Transcription failed */
        const val TRANSCRIPTION_FAILED = 3

        /** Response generation failed */
        const val GENERATION_FAILED = 4

        /** Speech synthesis failed */
        const val SYNTHESIS_FAILED = 5

        /** Turn timed out */
        const val TIMEOUT = 6

        /** Generic error */
        const val ERROR = 7

        /**
         * Get a human-readable name for the completion reason.
         */
        fun getName(reason: Int): String =
            when (reason) {
                SUCCESS -> "SUCCESS"
                CANCELLED -> "CANCELLED"
                NO_SPEECH -> "NO_SPEECH"
                TRANSCRIPTION_FAILED -> "TRANSCRIPTION_FAILED"
                GENERATION_FAILED -> "GENERATION_FAILED"
                SYNTHESIS_FAILED -> "SYNTHESIS_FAILED"
                TIMEOUT -> "TIMEOUT"
                ERROR -> "ERROR"
                else -> "UNKNOWN($reason)"
            }

        /**
         * Check if the reason indicates success.
         */
        fun isSuccess(reason: Int): Boolean = reason == SUCCESS
    }

    /**
     * Interrupt mode constants for handling interruptions.
     */
    object InterruptMode {
        /** No interruption allowed */
        const val NONE = 0

        /** Interrupt immediately when speech detected */
        const val IMMEDIATE = 1

        /** Wait for end of phrase before interrupting */
        const val END_OF_PHRASE = 2

        /**
         * Get a human-readable name for the interrupt mode.
         */
        fun getName(mode: Int): String =
            when (mode) {
                NONE -> "NONE"
                IMMEDIATE -> "IMMEDIATE"
                END_OF_PHRASE -> "END_OF_PHRASE"
                else -> "UNKNOWN($mode)"
            }
    }

    @Volatile
    private var isRegistered: Boolean = false

    @Volatile
    private var state: Int = VoiceAgentState.NOT_CREATED

    @Volatile
    private var currentPhase: Int = TurnPhase.IDLE

    @Volatile
    private var handle: Long = 0

    @Volatile
    private var isInitialized: Boolean = false

    @Volatile
    private var isCancelled: Boolean = false

    private val lock = Any()

    /**
     * Tag for logging.
     */
    private const val TAG = "CppBridgeVoiceAgent"

    /**
     * Singleton shared instance for accessing the Voice Agent.
     * Matches iOS CppBridge.VoiceAgent.shared pattern.
     */
    val shared: CppBridgeVoiceAgent = this

    /**
     * Optional listener for Voice Agent events.
     * Set this before calling [register] to receive events.
     */
    @Volatile
    var voiceAgentListener: VoiceAgentListener? = null

    /**
     * Optional callback for streaming audio output.
     * This is invoked for each audio chunk during synthesis.
     */
    @Volatile
    var audioStreamCallback: AudioStreamCallback? = null

    /**
     * Optional callback for streaming LLM response.
     * This is invoked for each token during response generation.
     */
    @Volatile
    var responseStreamCallback: ResponseStreamCallback? = null

    /**
     * Voice Agent configuration.
     *
     * @param vadModelPath Path to VAD model
     * @param sttModelPath Path to STT model
     * @param llmModelPath Path to LLM model
     * @param ttsModelPath Path to TTS model
     * @param vadModelId Optional VAD model ID for registry
     * @param sttModelId Optional STT model ID for registry
     * @param llmModelId Optional LLM model ID for registry
     * @param ttsModelId Optional TTS model ID for registry
     * @param systemPrompt System prompt for LLM
     * @param voiceId Voice ID for TTS
     * @param language Language code for STT/TTS
     * @param sampleRate Audio sample rate in Hz
     * @param interruptMode Interrupt mode for handling user interruptions
     * @param maxTurnDurationMs Maximum turn duration in milliseconds (0 = no limit)
     * @param silenceTimeoutMs Silence timeout for end of speech detection
     * @param enableVad Whether to enable VAD for speech detection
     * @param enableStreaming Whether to enable streaming for LLM and TTS
     */
    data class VoiceAgentConfig(
        val vadModelPath: String? = null,
        val sttModelPath: String? = null,
        val llmModelPath: String? = null,
        val ttsModelPath: String? = null,
        val vadModelId: String? = null,
        val sttModelId: String? = null,
        val llmModelId: String? = null,
        val ttsModelId: String? = null,
        val systemPrompt: String = "You are a helpful voice assistant.",
        val voiceId: String? = null,
        val language: String = "en",
        val sampleRate: Int = 16000,
        val interruptMode: Int = InterruptMode.IMMEDIATE,
        val maxTurnDurationMs: Long = 60000,
        val silenceTimeoutMs: Long = 1500,
        val enableVad: Boolean = true,
        val enableStreaming: Boolean = true,
    ) {
        /**
         * Convert to JSON string for C++ interop.
         */
        fun toJson(): String {
            return buildString {
                append("{")
                vadModelPath?.let { append("\"vad_model_path\":\"${escapeJsonString(it)}\",") }
                sttModelPath?.let { append("\"stt_model_path\":\"${escapeJsonString(it)}\",") }
                llmModelPath?.let { append("\"llm_model_path\":\"${escapeJsonString(it)}\",") }
                ttsModelPath?.let { append("\"tts_model_path\":\"${escapeJsonString(it)}\",") }
                vadModelId?.let { append("\"vad_model_id\":\"${escapeJsonString(it)}\",") }
                sttModelId?.let { append("\"stt_model_id\":\"${escapeJsonString(it)}\",") }
                llmModelId?.let { append("\"llm_model_id\":\"${escapeJsonString(it)}\",") }
                ttsModelId?.let { append("\"tts_model_id\":\"${escapeJsonString(it)}\",") }
                append("\"system_prompt\":\"${escapeJsonString(systemPrompt)}\",")
                voiceId?.let { append("\"voice_id\":\"${escapeJsonString(it)}\",") }
                append("\"language\":\"$language\",")
                append("\"sample_rate\":$sampleRate,")
                append("\"interrupt_mode\":$interruptMode,")
                append("\"max_turn_duration_ms\":$maxTurnDurationMs,")
                append("\"silence_timeout_ms\":$silenceTimeoutMs,")
                append("\"enable_vad\":$enableVad,")
                append("\"enable_streaming\":$enableStreaming")
                append("}")
            }
        }

        companion object {
            /** Default configuration */
            val DEFAULT = VoiceAgentConfig()
        }
    }

    /**
     * Turn configuration for individual turns.
     *
     * @param context Conversation context/history
     * @param maxResponseTokens Maximum tokens for LLM response
     * @param temperature LLM temperature (0.0 to 2.0)
     * @param skipVad Skip VAD and assume speech is present
     * @param skipTts Skip TTS and only return text response
     * @param audioFormat Output audio format
     */
    data class TurnConfig(
        val context: String? = null,
        val maxResponseTokens: Int = 512,
        val temperature: Float = 0.7f,
        val skipVad: Boolean = false,
        val skipTts: Boolean = false,
        val audioFormat: Int = 0, // PCM_16
    ) {
        /**
         * Convert to JSON string for C++ interop.
         */
        fun toJson(): String {
            return buildString {
                append("{")
                context?.let { append("\"context\":\"${escapeJsonString(it)}\",") }
                append("\"max_response_tokens\":$maxResponseTokens,")
                append("\"temperature\":$temperature,")
                append("\"skip_vad\":$skipVad,")
                append("\"skip_tts\":$skipTts,")
                append("\"audio_format\":$audioFormat")
                append("}")
            }
        }

        companion object {
            /** Default configuration */
            val DEFAULT = TurnConfig()
        }
    }

    /**
     * Turn result containing conversation turn output.
     *
     * @param userText Transcribed user speech
     * @param assistantText Generated assistant response
     * @param audioData Synthesized audio bytes (null if skipTts)
     * @param audioDurationMs Duration of synthesized audio
     * @param completionReason Reason for turn completion
     * @param processingTimeMs Total processing time
     * @param transcriptionTimeMs Time spent on transcription
     * @param generationTimeMs Time spent on LLM generation
     * @param synthesisTimeMs Time spent on TTS synthesis
     */
    data class TurnResult(
        val userText: String?,
        val assistantText: String?,
        val audioData: ByteArray?,
        val audioDurationMs: Long,
        val completionReason: Int,
        val processingTimeMs: Long,
        val transcriptionTimeMs: Long,
        val generationTimeMs: Long,
        val synthesisTimeMs: Long,
    ) {
        /**
         * Check if the turn was successful.
         */
        fun isSuccess(): Boolean = CompletionReason.isSuccess(completionReason)

        /**
         * Get completion reason name.
         */
        fun getCompletionReasonName(): String = CompletionReason.getName(completionReason)

        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (other !is TurnResult) return false

            if (userText != other.userText) return false
            if (assistantText != other.assistantText) return false
            if (audioData != null) {
                if (other.audioData == null) return false
                if (!audioData.contentEquals(other.audioData)) return false
            } else if (other.audioData != null) {
                return false
            }
            if (audioDurationMs != other.audioDurationMs) return false
            if (completionReason != other.completionReason) return false
            if (processingTimeMs != other.processingTimeMs) return false

            return true
        }

        override fun hashCode(): Int {
            var result = userText?.hashCode() ?: 0
            result = 31 * result + (assistantText?.hashCode() ?: 0)
            result = 31 * result + (audioData?.contentHashCode() ?: 0)
            result = 31 * result + audioDurationMs.hashCode()
            result = 31 * result + completionReason
            result = 31 * result + processingTimeMs.hashCode()
            return result
        }
    }

    /**
     * Speech detection result.
     *
     * @param hasSpeech Whether speech was detected
     * @param speechStartMs Start time of speech in milliseconds
     * @param speechEndMs End time of speech in milliseconds
     * @param confidence Detection confidence (0.0 to 1.0)
     */
    data class SpeechDetectionResult(
        val hasSpeech: Boolean,
        val speechStartMs: Long,
        val speechEndMs: Long,
        val confidence: Float,
    )

    /**
     * Transcription result.
     *
     * @param text Transcribed text
     * @param language Detected language code
     * @param confidence Transcription confidence
     * @param durationMs Duration of the audio transcribed
     */
    data class TranscriptionResult(
        val text: String,
        val language: String,
        val confidence: Float,
        val durationMs: Long,
    )

    /**
     * Response generation result.
     *
     * @param text Generated response text
     * @param tokenCount Number of tokens generated
     * @param stopReason Reason for stopping generation
     */
    data class ResponseResult(
        val text: String,
        val tokenCount: Int,
        val stopReason: Int,
    )

    /**
     * Audio synthesis result.
     *
     * @param audioData Synthesized audio bytes
     * @param durationMs Audio duration in milliseconds
     * @param sampleRate Sample rate of the audio
     */
    data class SynthesisResult(
        val audioData: ByteArray,
        val durationMs: Long,
        val sampleRate: Int,
    ) {
        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (other !is SynthesisResult) return false

            if (!audioData.contentEquals(other.audioData)) return false
            if (durationMs != other.durationMs) return false
            if (sampleRate != other.sampleRate) return false

            return true
        }

        override fun hashCode(): Int {
            var result = audioData.contentHashCode()
            result = 31 * result + durationMs.hashCode()
            result = 31 * result + sampleRate
            return result
        }
    }

    /**
     * Listener interface for Voice Agent events.
     */
    interface VoiceAgentListener {
        /**
         * Called when the Voice Agent state changes.
         *
         * @param previousState The previous state
         * @param newState The new state
         */
        fun onStateChanged(previousState: Int, newState: Int)

        /**
         * Called when the Voice Agent is initialized.
         */
        fun onInitialized()

        /**
         * Called when a turn phase changes.
         *
         * @param phase The new turn phase (see [TurnPhase])
         */
        fun onTurnPhaseChanged(phase: Int)

        /**
         * Called when speech is detected.
         *
         * @param result The speech detection result
         */
        fun onSpeechDetected(result: SpeechDetectionResult)

        /**
         * Called when transcription is complete.
         *
         * @param result The transcription result
         */
        fun onTranscriptionComplete(result: TranscriptionResult)

        /**
         * Called when partial transcription is available during streaming.
         *
         * @param partialText The partial transcription
         */
        fun onPartialTranscription(partialText: String)

        /**
         * Called when response generation is complete.
         *
         * @param result The response result
         */
        fun onResponseComplete(result: ResponseResult)

        /**
         * Called when a response token is generated during streaming.
         *
         * @param token The generated token
         */
        fun onResponseToken(token: String)

        /**
         * Called when audio synthesis is complete.
         *
         * @param result The synthesis result
         */
        fun onSynthesisComplete(result: SynthesisResult)

        /**
         * Called when an audio chunk is ready during streaming synthesis.
         *
         * @param audioChunk The audio chunk bytes
         */
        fun onAudioChunk(audioChunk: ByteArray)

        /**
         * Called when a turn is complete.
         *
         * @param result The turn result
         */
        fun onTurnComplete(result: TurnResult)

        /**
         * Called when the user interrupts the agent.
         */
        fun onUserInterrupt()

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
    fun interface AudioStreamCallback {
        /**
         * Called for each audio chunk during synthesis.
         *
         * @param audioChunk The audio chunk bytes
         * @param isFinal Whether this is the final chunk
         * @return true to continue streaming, false to stop
         */
        fun onAudioChunk(audioChunk: ByteArray, isFinal: Boolean): Boolean
    }

    /**
     * Callback interface for streaming response tokens.
     */
    fun interface ResponseStreamCallback {
        /**
         * Called for each token during response generation.
         *
         * @param token The generated token
         * @param isFinal Whether this is the final token
         * @return true to continue streaming, false to stop
         */
        fun onToken(token: String, isFinal: Boolean): Boolean
    }

    /**
     * Register the Voice Agent callbacks with C++ core.
     *
     * This must be called during SDK initialization, after AI component bridges are registered.
     * It is safe to call multiple times; subsequent calls are no-ops.
     */
    fun register() {
        synchronized(lock) {
            if (isRegistered) {
                return
            }

            RunAnywhereBridge.racVoiceAgentSetCallbacks(
                this,
                this,
                this,
                this,
                this,
                this,
                this,
            )

            isRegistered = true

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Voice Agent callbacks registered",
            )
        }
    }

    /**
     * Check if the Voice Agent callbacks are registered.
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
                throw SDKError.notInitialized("Voice Agent not created")
            }
            return handle
        }
    }

    /**
     * Check if the Voice Agent is initialized.
     */
    val isAgentInitialized: Boolean
        get() = synchronized(lock) { isInitialized && state == VoiceAgentState.READY }

    /**
     * Check if the Voice Agent is ready for use.
     */
    val isReady: Boolean
        get() = VoiceAgentState.isReady(state)

    /**
     * Check if the Voice Agent is currently processing.
     */
    val isProcessing: Boolean
        get() = VoiceAgentState.isProcessing(state)

    /**
     * Get the current Voice Agent state.
     */
    fun getState(): Int = state

    /**
     * Get the current turn phase.
     */
    fun getCurrentPhase(): Int = currentPhase

    // ========================================================================
    // LIFECYCLE OPERATIONS
    // ========================================================================

    /**
     * Create the Voice Agent component.
     *
     * @return 0 on success, error code on failure
     */
    fun create(): Int {
        synchronized(lock) {
            if (handle != 0L) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Voice Agent already created",
                )
                return 0
            }

            val result = nativeCreate()
            if (result == 0L) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.ERROR,
                    TAG,
                    "Failed to create Voice Agent",
                )
                return -1
            }

            handle = result
            setState(VoiceAgentState.CREATED)

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.INFO,
                TAG,
                "Voice Agent created",
            )

            return 0
        }
    }

    /**
     * Initialize the Voice Agent with component models.
     *
     * @param config Voice Agent configuration
     * @return 0 on success, error code on failure
     */
    fun initialize(config: VoiceAgentConfig = VoiceAgentConfig.DEFAULT): Int {
        synchronized(lock) {
            if (handle == 0L) {
                // Auto-create if needed
                val createResult = create()
                if (createResult != 0) {
                    return createResult
                }
            }

            if (isInitialized) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Voice Agent already initialized",
                )
                return 0
            }

            setState(VoiceAgentState.INITIALIZING)

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.INFO,
                TAG,
                "Initializing Voice Agent",
            )

            val result = nativeInitialize(handle, config.toJson())
            if (result != 0) {
                setState(VoiceAgentState.ERROR)
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.ERROR,
                    TAG,
                    "Failed to initialize Voice Agent (error: $result)",
                )

                try {
                    voiceAgentListener?.onError(result, "Failed to initialize Voice Agent")
                } catch (e: Exception) {
                    // Ignore listener errors
                }

                return result
            }

            isInitialized = true
            setState(VoiceAgentState.READY)

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.INFO,
                TAG,
                "Voice Agent initialized successfully",
            )

            // Update component state
            CppBridgeState.setComponentStateCallback(
                CppBridgeState.ComponentType.VOICE_AGENT,
                CppBridgeState.ComponentState.READY,
            )

            try {
                voiceAgentListener?.onInitialized()
            } catch (e: Exception) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Error in Voice Agent listener onInitialized: ${e.message}",
                )
            }

            return 0
        }
    }

    /**
     * Process a complete voice turn.
     *
     * This orchestrates the full pipeline: VAD -> STT -> LLM -> TTS
     *
     * @param audioData Raw audio data bytes
     * @param config Turn configuration
     * @return The turn result
     * @throws SDKError if processing fails
     */
    @Throws(SDKError::class)
    fun processVoiceTurn(audioData: ByteArray, config: TurnConfig = TurnConfig.DEFAULT): TurnResult {
        synchronized(lock) {
            if (handle == 0L || !isInitialized) {
                throw SDKError.voiceAgent("Voice Agent not initialized")
            }

            if (state != VoiceAgentState.READY) {
                throw SDKError.voiceAgent("Voice Agent not ready (state: ${VoiceAgentState.getName(state)})")
            }

            isCancelled = false
            setState(VoiceAgentState.PROCESSING_TURN)
            setPhase(TurnPhase.SPEECH_DETECTION)

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.INFO,
                TAG,
                "Starting voice turn (audio size: ${audioData.size} bytes)",
            )

            val startTime = System.currentTimeMillis()

            try {
                val resultJson =
                    nativeProcessVoiceTurn(handle, audioData, config.toJson())
                        ?: throw SDKError.voiceAgent("Voice turn processing failed: null result")

                val result = parseTurnResult(resultJson, System.currentTimeMillis() - startTime)

                setState(VoiceAgentState.READY)
                setPhase(TurnPhase.COMPLETED)

                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.INFO,
                    TAG,
                    "Voice turn completed: ${result.getCompletionReasonName()}, ${result.processingTimeMs}ms",
                )

                try {
                    voiceAgentListener?.onTurnComplete(result)
                } catch (e: Exception) {
                    // Ignore listener errors
                }

                return result
            } catch (e: Exception) {
                setState(VoiceAgentState.READY)
                setPhase(TurnPhase.FAILED)
                throw if (e is SDKError) e else SDKError.voiceAgent("Voice turn failed: ${e.message}")
            }
        }
    }

    /**
     * Detect speech in audio data.
     *
     * @param audioData Raw audio data bytes
     * @return The speech detection result
     * @throws SDKError if detection fails
     */
    @Throws(SDKError::class)
    fun detectSpeech(audioData: ByteArray): SpeechDetectionResult {
        synchronized(lock) {
            if (handle == 0L || !isInitialized) {
                throw SDKError.voiceAgent("Voice Agent not initialized")
            }

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Detecting speech (audio size: ${audioData.size} bytes)",
            )

            try {
                val resultJson =
                    nativeDetectSpeech(handle, audioData)
                        ?: throw SDKError.voiceAgent("Speech detection failed: null result")

                val result = parseSpeechDetectionResult(resultJson)

                try {
                    voiceAgentListener?.onSpeechDetected(result)
                } catch (e: Exception) {
                    // Ignore listener errors
                }

                return result
            } catch (e: Exception) {
                throw if (e is SDKError) e else SDKError.voiceAgent("Speech detection failed: ${e.message}")
            }
        }
    }

    /**
     * Transcribe audio to text.
     *
     * @param audioData Raw audio data bytes
     * @return The transcription result
     * @throws SDKError if transcription fails
     */
    @Throws(SDKError::class)
    fun transcribe(audioData: ByteArray): TranscriptionResult {
        synchronized(lock) {
            if (handle == 0L || !isInitialized) {
                throw SDKError.voiceAgent("Voice Agent not initialized")
            }

            setState(VoiceAgentState.TRANSCRIBING)
            setPhase(TurnPhase.TRANSCRIPTION)

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Transcribing audio (size: ${audioData.size} bytes)",
            )

            try {
                val resultJson =
                    nativeTranscribe(handle, audioData)
                        ?: throw SDKError.voiceAgent("Transcription failed: null result")

                val result = parseTranscriptionResult(resultJson)

                setState(VoiceAgentState.READY)

                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.DEBUG,
                    TAG,
                    "Transcription complete: \"${result.text.take(50)}...\"",
                )

                try {
                    voiceAgentListener?.onTranscriptionComplete(result)
                } catch (e: Exception) {
                    // Ignore listener errors
                }

                return result
            } catch (e: Exception) {
                setState(VoiceAgentState.READY)
                throw if (e is SDKError) e else SDKError.voiceAgent("Transcription failed: ${e.message}")
            }
        }
    }

    /**
     * Generate a response from the LLM.
     *
     * @param prompt The user prompt/input
     * @param context Optional conversation context
     * @return The response result
     * @throws SDKError if generation fails
     */
    @Throws(SDKError::class)
    fun generateResponse(prompt: String, context: String? = null): ResponseResult {
        synchronized(lock) {
            if (handle == 0L || !isInitialized) {
                throw SDKError.voiceAgent("Voice Agent not initialized")
            }

            setState(VoiceAgentState.GENERATING)
            setPhase(TurnPhase.RESPONSE_GENERATION)

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Generating response for: \"${prompt.take(50)}...\"",
            )

            try {
                val resultJson =
                    nativeGenerateResponse(handle, prompt, context)
                        ?: throw SDKError.voiceAgent("Response generation failed: null result")

                val result = parseResponseResult(resultJson)

                setState(VoiceAgentState.READY)

                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.DEBUG,
                    TAG,
                    "Response generated: ${result.tokenCount} tokens",
                )

                try {
                    voiceAgentListener?.onResponseComplete(result)
                } catch (e: Exception) {
                    // Ignore listener errors
                }

                return result
            } catch (e: Exception) {
                setState(VoiceAgentState.READY)
                throw if (e is SDKError) e else SDKError.voiceAgent("Response generation failed: ${e.message}")
            }
        }
    }

    /**
     * Synthesize speech from text.
     *
     * @param text The text to synthesize
     * @return The synthesis result
     * @throws SDKError if synthesis fails
     */
    @Throws(SDKError::class)
    fun synthesizeSpeech(text: String): SynthesisResult {
        synchronized(lock) {
            if (handle == 0L || !isInitialized) {
                throw SDKError.voiceAgent("Voice Agent not initialized")
            }

            setState(VoiceAgentState.SPEAKING)
            setPhase(TurnPhase.SPEECH_SYNTHESIS)

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Synthesizing speech: \"${text.take(50)}...\"",
            )

            try {
                val audioData =
                    nativeSynthesizeSpeech(handle, text)
                        ?: throw SDKError.voiceAgent("Speech synthesis failed: null result")

                // Parse duration from native result or estimate
                val durationMs = estimateAudioDuration(audioData.size)
                val result = SynthesisResult(audioData, durationMs, 16000)

                setState(VoiceAgentState.READY)

                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.DEBUG,
                    TAG,
                    "Speech synthesized: ${audioData.size} bytes, ${durationMs}ms",
                )

                try {
                    voiceAgentListener?.onSynthesisComplete(result)
                } catch (e: Exception) {
                    // Ignore listener errors
                }

                return result
            } catch (e: Exception) {
                setState(VoiceAgentState.READY)
                throw if (e is SDKError) e else SDKError.voiceAgent("Speech synthesis failed: ${e.message}")
            }
        }
    }

    /**
     * Cancel an ongoing operation.
     */
    fun cancel() {
        synchronized(lock) {
            if (!VoiceAgentState.isProcessing(state)) {
                return
            }

            isCancelled = true

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.INFO,
                TAG,
                "Cancelling Voice Agent operation",
            )

            nativeCancel(handle)

            setPhase(TurnPhase.CANCELLED)
        }
    }

    /**
     * Reset the Voice Agent for a new conversation.
     */
    fun reset() {
        synchronized(lock) {
            if (handle == 0L) {
                return
            }

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Resetting Voice Agent",
            )

            nativeReset(handle)
            setPhase(TurnPhase.IDLE)
        }
    }

    /**
     * Destroy the Voice Agent and release resources.
     */
    fun destroy() {
        synchronized(lock) {
            if (handle == 0L) {
                return
            }

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.INFO,
                TAG,
                "Destroying Voice Agent",
            )

            nativeDestroy(handle)

            handle = 0
            isInitialized = false
            setState(VoiceAgentState.NOT_CREATED)
            setPhase(TurnPhase.IDLE)

            // Update component state
            CppBridgeState.setComponentStateCallback(
                CppBridgeState.ComponentType.VOICE_AGENT,
                CppBridgeState.ComponentState.NOT_CREATED,
            )
        }
    }

    // ========================================================================
    // JNI CALLBACKS
    // ========================================================================

    /**
     * State change callback.
     *
     * Called from C++ when the Voice Agent state changes.
     *
     * @param newState The new state
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun stateChangeCallback(newState: Int) {
        setState(newState)
    }

    /**
     * Turn phase callback.
     *
     * Called from C++ when the turn phase changes.
     *
     * @param phase The new turn phase
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun turnPhaseCallback(phase: Int) {
        setPhase(phase)
    }

    /**
     * Partial transcription callback.
     *
     * Called from C++ for streaming partial transcription results.
     *
     * @param partialText The partial transcription
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun partialTranscriptionCallback(partialText: String) {
        try {
            voiceAgentListener?.onPartialTranscription(partialText)
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.WARN,
                TAG,
                "Error in Voice Agent listener onPartialTranscription: ${e.message}",
            )
        }
    }

    /**
     * Response token callback.
     *
     * Called from C++ for each token during streaming response generation.
     *
     * @param token The generated token
     * @param isFinal Whether this is the final token
     * @return true to continue streaming, false to stop
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun responseTokenCallback(token: String, isFinal: Boolean): Boolean {
        if (isCancelled) {
            return false
        }

        try {
            voiceAgentListener?.onResponseToken(token)
        } catch (e: Exception) {
            // Ignore listener errors
        }

        return try {
            responseStreamCallback?.onToken(token, isFinal) ?: true
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.WARN,
                TAG,
                "Error in response stream callback: ${e.message}",
            )
            true // Continue on error
        }
    }

    /**
     * Audio chunk callback.
     *
     * Called from C++ for each audio chunk during streaming synthesis.
     *
     * @param audioChunk The audio chunk bytes
     * @param isFinal Whether this is the final chunk
     * @return true to continue streaming, false to stop
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun audioChunkCallback(audioChunk: ByteArray, isFinal: Boolean): Boolean {
        if (isCancelled) {
            return false
        }

        try {
            voiceAgentListener?.onAudioChunk(audioChunk)
        } catch (e: Exception) {
            // Ignore listener errors
        }

        return try {
            audioStreamCallback?.onAudioChunk(audioChunk, isFinal) ?: true
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.WARN,
                TAG,
                "Error in audio stream callback: ${e.message}",
            )
            true // Continue on error
        }
    }

    /**
     * User interrupt callback.
     *
     * Called from C++ when the user interrupts the agent.
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun userInterruptCallback() {
        CppBridgePlatformAdapter.logCallback(
            CppBridgePlatformAdapter.LogLevel.DEBUG,
            TAG,
            "User interrupt detected",
        )

        try {
            voiceAgentListener?.onUserInterrupt()
        } catch (e: Exception) {
            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.WARN,
                TAG,
                "Error in Voice Agent listener onUserInterrupt: ${e.message}",
            )
        }
    }

    /**
     * Progress callback.
     *
     * Called from C++ to report progress.
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
     * @return The current Voice Agent state
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun getStateCallback(): Int {
        return state
    }

    /**
     * Is initialized callback.
     *
     * @return true if the Voice Agent is initialized
     *
     * NOTE: This function is called from JNI. Do not capture any state.
     */
    @JvmStatic
    fun isInitializedCallback(): Boolean {
        return isInitialized && state == VoiceAgentState.READY
    }

    // ========================================================================
    // JNI NATIVE DECLARATIONS
    // ========================================================================

    /**
     * Native method to set the Voice Agent callbacks with C++ core.
     * Reserved for future native callback integration.
     *
     * C API: rac_voice_agent_set_callbacks(...)
     */
    @Suppress("unused")
    @JvmStatic
    private external fun nativeSetVoiceAgentCallbacks()

    /**
     * Native method to unset the Voice Agent callbacks.
     * Reserved for future native callback integration.
     *
     * C API: rac_voice_agent_set_callbacks(nullptr)
     */
    @Suppress("unused")
    @JvmStatic
    private external fun nativeUnsetVoiceAgentCallbacks()

    /**
     * Native method to create the Voice Agent.
     *
     * @return Handle to the created component, or 0 on failure
     *
     * C API: rac_voice_agent_create()
     */
    @JvmStatic
    external fun nativeCreate(): Long

    /**
     * Native method to initialize the Voice Agent.
     *
     * @param handle The component handle
     * @param configJson JSON configuration string
     * @return 0 on success, error code on failure
     *
     * C API: rac_voice_agent_initialize(handle, config)
     */
    @JvmStatic
    external fun nativeInitialize(handle: Long, configJson: String): Int

    /**
     * Native method to process a complete voice turn.
     *
     * @param handle The component handle
     * @param audioData Raw audio bytes
     * @param configJson JSON configuration string
     * @return JSON-encoded result, or null on failure
     *
     * C API: rac_voice_agent_process_voice_turn(handle, audio_data, audio_size, config)
     */
    @JvmStatic
    external fun nativeProcessVoiceTurn(handle: Long, audioData: ByteArray, configJson: String): String?

    /**
     * Native method to detect speech in audio.
     *
     * @param handle The component handle
     * @param audioData Raw audio bytes
     * @return JSON-encoded result, or null on failure
     *
     * C API: rac_voice_agent_detect_speech(handle, audio_data, audio_size)
     */
    @JvmStatic
    external fun nativeDetectSpeech(handle: Long, audioData: ByteArray): String?

    /**
     * Native method to transcribe audio.
     *
     * @param handle The component handle
     * @param audioData Raw audio bytes
     * @return JSON-encoded result, or null on failure
     *
     * C API: rac_voice_agent_transcribe(handle, audio_data, audio_size)
     */
    @JvmStatic
    external fun nativeTranscribe(handle: Long, audioData: ByteArray): String?

    /**
     * Native method to generate a response.
     *
     * @param handle The component handle
     * @param prompt The user prompt
     * @param context Optional conversation context
     * @return JSON-encoded result, or null on failure
     *
     * C API: rac_voice_agent_generate_response(handle, prompt, context)
     */
    @JvmStatic
    external fun nativeGenerateResponse(handle: Long, prompt: String, context: String?): String?

    /**
     * Native method to synthesize speech.
     *
     * @param handle The component handle
     * @param text The text to synthesize
     * @return Audio bytes, or null on failure
     *
     * C API: rac_voice_agent_synthesize_speech(handle, text)
     */
    @JvmStatic
    external fun nativeSynthesizeSpeech(handle: Long, text: String): ByteArray?

    /**
     * Native method to cancel an operation.
     *
     * @param handle The component handle
     *
     * C API: rac_voice_agent_cancel(handle)
     */
    @JvmStatic
    external fun nativeCancel(handle: Long)

    /**
     * Native method to reset the Voice Agent.
     *
     * @param handle The component handle
     *
     * C API: rac_voice_agent_reset(handle)
     */
    @JvmStatic
    external fun nativeReset(handle: Long)

    /**
     * Native method to destroy the Voice Agent.
     *
     * @param handle The component handle
     *
     * C API: rac_voice_agent_destroy(handle)
     */
    @JvmStatic
    external fun nativeDestroy(handle: Long)

    /**
     * Native method to get component states.
     *
     * @param handle The component handle
     * @return JSON with component states
     *
     * C API: rac_voice_agent_get_component_states(handle)
     */
    @JvmStatic
    external fun nativeGetComponentStates(handle: Long): String?

    // ========================================================================
    // LIFECYCLE MANAGEMENT
    // ========================================================================

    /**
     * Unregister the Voice Agent callbacks and clean up resources.
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

            RunAnywhereBridge.racVoiceAgentSetCallbacks(
                null,
                null,
                null,
                null,
                null,
                null,
                null,
            )

            voiceAgentListener = null
            audioStreamCallback = null
            responseStreamCallback = null
            isRegistered = false
        }
    }

    // ========================================================================
    // UTILITY FUNCTIONS
    // ========================================================================

    /**
     * Set the Voice Agent state and notify listeners.
     */
    private fun setState(newState: Int) {
        val previousState = state
        if (newState != previousState) {
            state = newState

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "State changed: ${VoiceAgentState.getName(previousState)} -> ${VoiceAgentState.getName(newState)}",
            )

            try {
                voiceAgentListener?.onStateChanged(previousState, newState)
            } catch (e: Exception) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Error in Voice Agent listener onStateChanged: ${e.message}",
                )
            }
        }
    }

    /**
     * Set the current turn phase and notify listeners.
     */
    private fun setPhase(newPhase: Int) {
        val previousPhase = currentPhase
        if (newPhase != previousPhase) {
            currentPhase = newPhase

            CppBridgePlatformAdapter.logCallback(
                CppBridgePlatformAdapter.LogLevel.DEBUG,
                TAG,
                "Phase changed: ${TurnPhase.getName(previousPhase)} -> ${TurnPhase.getName(newPhase)}",
            )

            try {
                voiceAgentListener?.onTurnPhaseChanged(newPhase)
            } catch (e: Exception) {
                CppBridgePlatformAdapter.logCallback(
                    CppBridgePlatformAdapter.LogLevel.WARN,
                    TAG,
                    "Error in Voice Agent listener onTurnPhaseChanged: ${e.message}",
                )
            }
        }
    }

    /**
     * Escape a string for JSON encoding.
     */
    private fun escapeJsonString(str: String): String {
        return str
            .replace("\\", "\\\\")
            .replace("\"", "\\\"")
            .replace("\n", "\\n")
            .replace("\r", "\\r")
            .replace("\t", "\\t")
    }

    /**
     * Estimate audio duration from byte size.
     * Assumes 16-bit PCM at 16kHz mono.
     */
    private fun estimateAudioDuration(byteSize: Int): Long {
        // 16-bit = 2 bytes per sample, 16kHz = 16000 samples per second
        // Duration (ms) = (bytes / 2) / 16000 * 1000 = bytes / 32
        return (byteSize / 32).toLong()
    }

    /**
     * Parse turn result from JSON.
     */
    private fun parseTurnResult(json: String, elapsedMs: Long): TurnResult {
        fun extractString(key: String): String? {
            val pattern = "\"$key\"\\s*:\\s*\"([^\"]*)\""
            val regex = Regex(pattern)
            return regex.find(json)?.groupValues?.get(1)
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

        fun extractInt(key: String): Int {
            val pattern = "\"$key\"\\s*:\\s*(-?\\d+)"
            val regex = Regex(pattern)
            return regex
                .find(json)
                ?.groupValues
                ?.get(1)
                ?.toIntOrNull() ?: 0
        }

        return TurnResult(
            userText = extractString("user_text"),
            assistantText = extractString("assistant_text"),
            audioData = null, // Would need base64 decoding from JSON
            audioDurationMs = extractLong("audio_duration_ms"),
            completionReason = extractInt("completion_reason"),
            processingTimeMs = elapsedMs,
            transcriptionTimeMs = extractLong("transcription_time_ms"),
            generationTimeMs = extractLong("generation_time_ms"),
            synthesisTimeMs = extractLong("synthesis_time_ms"),
        )
    }

    /**
     * Parse speech detection result from JSON.
     */
    private fun parseSpeechDetectionResult(json: String): SpeechDetectionResult {
        fun extractBoolean(key: String): Boolean {
            val pattern = "\"$key\"\\s*:\\s*(true|false)"
            val regex = Regex(pattern)
            return regex
                .find(json)
                ?.groupValues
                ?.get(1)
                ?.toBooleanStrictOrNull() ?: false
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

        return SpeechDetectionResult(
            hasSpeech = extractBoolean("has_speech"),
            speechStartMs = extractLong("speech_start_ms"),
            speechEndMs = extractLong("speech_end_ms"),
            confidence = extractFloat("confidence"),
        )
    }

    /**
     * Parse transcription result from JSON.
     */
    private fun parseTranscriptionResult(json: String): TranscriptionResult {
        fun extractString(key: String): String {
            val pattern = "\"$key\"\\s*:\\s*\"([^\"]*)\""
            val regex = Regex(pattern)
            return regex.find(json)?.groupValues?.get(1) ?: ""
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

        fun extractLong(key: String): Long {
            val pattern = "\"$key\"\\s*:\\s*(-?\\d+)"
            val regex = Regex(pattern)
            return regex
                .find(json)
                ?.groupValues
                ?.get(1)
                ?.toLongOrNull() ?: 0L
        }

        return TranscriptionResult(
            text = extractString("text"),
            language = extractString("language"),
            confidence = extractFloat("confidence"),
            durationMs = extractLong("duration_ms"),
        )
    }

    /**
     * Parse response result from JSON.
     */
    private fun parseResponseResult(json: String): ResponseResult {
        fun extractString(key: String): String {
            val pattern = "\"$key\"\\s*:\\s*\"([^\"]*)\""
            val regex = Regex(pattern)
            return regex.find(json)?.groupValues?.get(1) ?: ""
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

        return ResponseResult(
            text = extractString("text"),
            tokenCount = extractInt("token_count"),
            stopReason = extractInt("stop_reason"),
        )
    }

    /**
     * Get a state summary for diagnostics.
     *
     * @return Human-readable state summary
     */
    fun getStateSummary(): String {
        return buildString {
            append("Voice Agent State: ${VoiceAgentState.getName(state)}")
            append(", Phase: ${TurnPhase.getName(currentPhase)}")
            append(", Initialized: $isInitialized")
            if (handle != 0L) {
                append(", Handle: $handle")
            }
        }
    }

    /**
     * Get component states for diagnostics.
     *
     * @return Map of component type names to their states
     */
    fun getComponentStates(): Map<String, String> {
        synchronized(lock) {
            if (handle == 0L) {
                return emptyMap()
            }

            val json = nativeGetComponentStates(handle) ?: return emptyMap()

            // Simple parsing for diagnostic purposes
            val states = mutableMapOf<String, String>()
            val pattern = "\"(\\w+)\"\\s*:\\s*\"?(\\w+)\"?"
            Regex(pattern).findAll(json).forEach { match ->
                val (key, value) = match.destructured
                states[key] = value
            }
            return states
        }
    }
}
