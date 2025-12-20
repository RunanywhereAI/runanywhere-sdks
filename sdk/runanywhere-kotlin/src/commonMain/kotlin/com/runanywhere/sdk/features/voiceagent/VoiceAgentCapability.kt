package com.runanywhere.sdk.features.voiceagent

import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.features.llm.LLMCapability
import com.runanywhere.sdk.features.llm.LLMConfiguration
import com.runanywhere.sdk.features.stt.STTCapability
import com.runanywhere.sdk.features.stt.STTConfiguration
import com.runanywhere.sdk.features.tts.TTSCapability
import com.runanywhere.sdk.features.tts.TTSConfiguration
import com.runanywhere.sdk.features.vad.VADConfiguration
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.infrastructure.events.EventPublisher
import com.runanywhere.sdk.infrastructure.events.SDKVoiceEvent
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * VoiceAgent Capability - Public API wrapper for end-to-end voice AI pipeline
 *
 * Aligned with iOS VoiceAgentCapability pattern:
 * - Composite capability that orchestrates VAD -> STT -> LLM -> TTS pipeline
 * - Three initialization patterns:
 *   1. Full configuration
 *   2. Quick init with model IDs
 *   3. Reuse already-loaded models
 * - Event tracking via EventBus
 * - Session state management
 *
 * This capability wraps VoiceAgentComponent and provides the interface expected by
 * the public RunAnywhere+VoiceAgent.kt extension functions.
 */
class VoiceAgentCapability internal constructor(
    private val getSTTCapability: () -> STTCapability?,
    private val getLLMCapability: () -> LLMCapability?,
    private val getTTSCapability: () -> TTSCapability?,
    private val getOrCreateComponent: (VoiceAgentConfiguration) -> VoiceAgentComponent,
) {
    private val logger = SDKLogger("VoiceAgentCapability")

    // Internal state
    private var isConfigured = false
    private var currentConfiguration: VoiceAgentConfiguration? = null
    private var component: VoiceAgentComponent? = null
    private val mutex = Mutex()

    // ============================================================================
    // MARK: - Public Properties (iOS VoiceAgentCapability pattern)
    // ============================================================================

    /**
     * Check if the Voice Agent is ready for use
     */
    val isReady: Boolean
        get() = isConfigured && component?.isReady == true

    /**
     * Get current pipeline state
     */
    val pipelineState: VoiceAgentPipelineState
        get() = component?.getPipelineState() ?: VoiceAgentPipelineState.IDLE

    /**
     * Check if pipeline is currently processing
     */
    val isProcessing: Boolean
        get() = component?.isProcessing() ?: false

    /**
     * Check if all sub-components are ready
     */
    val areAllComponentsReady: Boolean
        get() = component?.areAllComponentsReady() ?: false

    /**
     * Get component states for UI feedback
     */
    fun getComponentStates(): VoiceAgentComponentStates {
        val stt = getSTTCapability()
        val llm = getLLMCapability()
        val tts = getTTSCapability()

        return VoiceAgentComponentStates(
            stt =
                if (stt?.isModelLoaded ==
                    true
                ) {
                    ComponentLoadState.Loaded(stt.currentModelId ?: "unknown")
                } else {
                    ComponentLoadState.NotLoaded
                },
            llm =
                if (llm?.isModelLoaded ==
                    true
                ) {
                    ComponentLoadState.Loaded(llm.currentModelId ?: "unknown")
                } else {
                    ComponentLoadState.NotLoaded
                },
            tts =
                if (tts?.isVoiceLoaded ==
                    true
                ) {
                    ComponentLoadState.Loaded(tts.currentVoiceId ?: "unknown")
                } else {
                    ComponentLoadState.NotLoaded
                },
        )
    }

    // ============================================================================
    // MARK: - Initialization (iOS VoiceAgentCapability pattern)
    // ============================================================================

    /**
     * Initialize Voice Agent with full configuration
     *
     * @param config VoiceAgentConfiguration with all sub-component configs
     * @throws SDKError if initialization fails
     */
    suspend fun initialize(config: VoiceAgentConfiguration) =
        mutex.withLock {
            logger.info("Initializing Voice Agent with full configuration")

            try {
                EventPublisher.track(SDKVoiceEvent.PipelineStarted)

                // Create and initialize the component
                component = getOrCreateComponent(config)
                component?.initialize()

                currentConfiguration = config
                isConfigured = true

                logger.info("✅ Voice Agent initialized successfully")
                EventPublisher.track(SDKVoiceEvent.PipelineCompleted)
            } catch (e: Exception) {
                logger.error("Failed to initialize Voice Agent", e)
                isConfigured = false
                component = null
                EventPublisher.track(SDKVoiceEvent.PipelineError(e))
                throw SDKError.InitializationFailed("Voice Agent initialization failed: ${e.message}")
            }
        }

    /**
     * Quick initialization with model IDs
     * Matches iOS initializeVoiceAgent(sttModelId:llmModelId:ttsVoice:)
     *
     * @param sttModelId STT model ID (empty string = use already loaded or skip)
     * @param llmModelId LLM model ID (empty string = use already loaded or skip)
     * @param ttsVoice TTS voice ID (empty string = use already loaded or skip)
     */
    suspend fun initialize(
        sttModelId: String,
        llmModelId: String,
        ttsVoice: String,
    ) {
        logger.info("Initializing Voice Agent with model IDs: STT=$sttModelId, LLM=$llmModelId, TTS=$ttsVoice")

        val config =
            VoiceAgentConfiguration(
                vadConfig = VADConfiguration(),
                sttConfig = STTConfiguration(modelId = sttModelId.ifEmpty { "whisper-base" }),
                llmConfig = LLMConfiguration(modelId = llmModelId.ifEmpty { "llama-2-7b-chat" }),
                ttsConfig = TTSConfiguration(voice = ttsVoice.ifEmpty { "default" }),
            )

        initialize(config)
    }

    /**
     * Initialize Voice Agent with already-loaded models
     * Matches iOS initializeVoiceAgentWithLoadedModels()
     *
     * Uses whatever models are already loaded in STT, LLM, and TTS capabilities
     */
    suspend fun initializeWithLoadedModels() {
        logger.info("Initializing Voice Agent with already-loaded models")

        // Verify components are loaded
        val stt = getSTTCapability()
        val llm = getLLMCapability()
        val tts = getTTSCapability()

        if (stt?.isModelLoaded != true) {
            logger.warning("No STT model loaded - will use default")
        }
        if (llm?.isModelLoaded != true) {
            logger.warning("No LLM model loaded - will use default")
        }
        if (tts?.isVoiceLoaded != true) {
            logger.warning("No TTS voice loaded - will use default")
        }

        // Use empty strings to indicate "use already loaded"
        initialize(
            sttModelId = stt?.currentModelId ?: "",
            llmModelId = llm?.currentModelId ?: "",
            ttsVoice = tts?.currentVoiceId ?: "",
        )
    }

    // ============================================================================
    // MARK: - Voice Processing (iOS VoiceAgentCapability pattern)
    // ============================================================================

    /**
     * Process a complete voice turn through the full pipeline
     * Matches iOS processVoiceTurn(_ audioData: Data) -> VoiceAgentResult
     *
     * @param audioData Raw audio data (PCM format expected)
     * @return VoiceAgentResult with transcription, response, and synthesized audio
     */
    suspend fun processVoiceTurn(audioData: ByteArray): VoiceAgentResult {
        ensureReady()

        val comp = component ?: throw SDKError.ComponentNotReady("Voice Agent component not initialized")

        return try {
            comp.processAudio(audioData)
        } catch (e: Exception) {
            logger.error("Voice turn processing failed", e)
            throw SDKError.ProcessingFailed("Voice turn processing failed: ${e.message}")
        }
    }

    /**
     * Process a stream of audio through the pipeline
     * Matches iOS processStream(_ audioStream: AsyncStream<Data>) -> AsyncThrowingStream<VoiceAgentEvent, Error>
     *
     * @param audioStream Flow of audio data chunks
     * @return Flow of VoiceAgentEvent for reactive consumption
     */
    fun processStream(audioStream: Flow<ByteArray>): Flow<VoiceAgentEvent> {
        ensureReady()

        val comp = component ?: throw SDKError.ComponentNotReady("Voice Agent component not initialized")
        return comp.processStream(audioStream)
    }

    // ============================================================================
    // MARK: - Individual Component Access (iOS VoiceAgentCapability pattern)
    // ============================================================================

    /**
     * Transcribe audio to text (STT only)
     * Matches iOS voiceAgentTranscribe(_ audioData: Data) -> String
     *
     * @param audioData Raw audio data
     * @return Transcribed text
     */
    suspend fun transcribe(audioData: ByteArray): String {
        ensureReady()

        val comp = component ?: throw SDKError.ComponentNotReady("Voice Agent component not initialized")
        return comp.transcribe(audioData) ?: throw SDKError.ProcessingFailed("Transcription returned empty result")
    }

    /**
     * Generate response from text (LLM only)
     * Matches iOS voiceAgentGenerateResponse(_ prompt: String) -> String
     *
     * @param prompt Text prompt
     * @return Generated response
     */
    suspend fun generateResponse(prompt: String): String {
        ensureReady()

        val comp = component ?: throw SDKError.ComponentNotReady("Voice Agent component not initialized")
        return comp.generateResponse(prompt) ?: throw SDKError.ProcessingFailed("Response generation returned empty result")
    }

    /**
     * Synthesize speech from text (TTS only)
     * Matches iOS voiceAgentSynthesizeSpeech(_ text: String) -> Data
     *
     * @param text Text to synthesize
     * @return Synthesized audio data
     */
    suspend fun synthesizeSpeech(text: String): ByteArray {
        ensureReady()

        val comp = component ?: throw SDKError.ComponentNotReady("Voice Agent component not initialized")
        return comp.synthesizeSpeech(text) ?: throw SDKError.ProcessingFailed("Speech synthesis returned empty result")
    }

    /**
     * Detect speech in audio samples (VAD only)
     *
     * @param samples Float audio samples
     * @return true if speech is detected
     */
    fun detectSpeech(samples: FloatArray): Boolean {
        ensureReady()

        val comp = component ?: throw SDKError.ComponentNotReady("Voice Agent component not initialized")
        return comp.detectVoiceActivity(samples)
    }

    // ============================================================================
    // MARK: - Cleanup
    // ============================================================================

    /**
     * Cleanup Voice Agent and release resources
     */
    suspend fun cleanup() =
        mutex.withLock {
            logger.info("Cleaning up Voice Agent")

            try {
                component?.cleanup()
            } catch (e: Exception) {
                logger.warn("Error during Voice Agent cleanup: ${e.message}")
            }

            component = null
            isConfigured = false
            currentConfiguration = null

            logger.info("✅ Voice Agent cleaned up")
        }

    // ============================================================================
    // MARK: - Private Helpers
    // ============================================================================

    private fun ensureReady() {
        if (!isReady) {
            throw SDKError.ComponentNotReady("Voice Agent not initialized. Call initializeVoiceAgent() first.")
        }
    }
}

// ============================================================================
// MARK: - Supporting Types (iOS VoiceAgentCapability aligned)
// ============================================================================

/**
 * State of individual component loading
 * Matches iOS ComponentLoadState
 */
sealed class ComponentLoadState {
    object NotLoaded : ComponentLoadState()

    object Loading : ComponentLoadState()

    data class Loaded(
        val modelId: String,
    ) : ComponentLoadState()

    data class Error(
        val message: String,
    ) : ComponentLoadState()

    val isLoaded: Boolean
        get() = this is Loaded

    val isLoading: Boolean
        get() = this is Loading
}

/**
 * Aggregate state of all Voice Agent components
 * Matches iOS VoiceAgentComponentStates
 */
data class VoiceAgentComponentStates(
    val stt: ComponentLoadState,
    val llm: ComponentLoadState,
    val tts: ComponentLoadState,
) {
    /**
     * Check if all components are fully ready
     */
    val isFullyReady: Boolean
        get() = stt.isLoaded && llm.isLoaded && tts.isLoaded

    /**
     * Check if any component is currently loading
     */
    val isAnyLoading: Boolean
        get() = stt.isLoading || llm.isLoading || tts.isLoading

    /**
     * Get list of missing (not loaded) component names
     */
    val missingComponents: List<String>
        get() =
            buildList {
                if (!stt.isLoaded) add("STT")
                if (!llm.isLoaded) add("LLM")
                if (!tts.isLoaded) add("TTS")
            }
}

/**
 * Audio pipeline state machine
 * Matches iOS AudioPipelineState
 */
enum class AudioPipelineState {
    /** Ready to start */
    IDLE,

    /** Listening for speech */
    LISTENING,

    /** Processing STT */
    PROCESSING_SPEECH,

    /** Running LLM */
    GENERATING_RESPONSE,

    /** Playing TTS output */
    PLAYING_TTS,

    /** Cooldown after TTS (feedback prevention) */
    COOLDOWN,

    /** Error state */
    ERROR,
}
