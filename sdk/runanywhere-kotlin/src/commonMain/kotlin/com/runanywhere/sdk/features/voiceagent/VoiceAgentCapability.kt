package com.runanywhere.sdk.features.voiceagent

import com.runanywhere.sdk.core.capabilities.CapabilityError
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.features.llm.LLMCapability
import com.runanywhere.sdk.features.llm.LLMConfiguration
import com.runanywhere.sdk.features.stt.STTCapability
import com.runanywhere.sdk.features.stt.STTConfiguration
import com.runanywhere.sdk.features.stt.STTOptions
import com.runanywhere.sdk.features.tts.TTSCapability
import com.runanywhere.sdk.features.tts.TTSConfiguration
import com.runanywhere.sdk.features.tts.TTSOptions
import com.runanywhere.sdk.features.vad.VADCapability
import com.runanywhere.sdk.features.vad.VADConfiguration
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.infrastructure.events.EventPublisher
import com.runanywhere.sdk.infrastructure.events.SDKVoiceEvent
import com.runanywhere.sdk.models.LLMGenerationOptions
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * VoiceAgent Capability - Composite capability for end-to-end voice AI pipeline
 *
 * Aligned with iOS VoiceAgentCapability pattern:
 * - Directly composes STT, LLM, TTS, and VAD capabilities (no intermediate component layer)
 * - Three initialization patterns:
 *   1. Full configuration
 *   2. Quick init with model IDs
 *   3. Reuse already-loaded models
 * - Event tracking via EventBus
 * - Full pipeline processing: Audio -> VAD -> STT -> LLM -> TTS -> Audio
 */
class VoiceAgentCapability internal constructor(
    private val llm: LLMCapability,
    private val stt: STTCapability,
    private val tts: TTSCapability,
    private val vad: VADCapability,
) {
    private val logger = SDKLogger("VoiceAgentCapability")

    // MARK: - State

    /** Whether the voice agent is initialized */
    private var isConfigured = false

    /** Current configuration */
    private var currentConfiguration: VoiceAgentConfiguration? = null

    /** Mutex for thread-safe initialization */
    private val mutex = Mutex()

    /** Mutex for pipeline processing */
    private val processingMutex = Mutex()

    /** Current pipeline state */
    @Volatile
    private var pipelineState = VoiceAgentPipelineState.IDLE

    // ============================================================================
    // MARK: - Public Properties (iOS VoiceAgentCapability pattern)
    // ============================================================================

    /**
     * Check if the Voice Agent is ready for use
     */
    val isReady: Boolean
        get() = isConfigured

    /**
     * Get current pipeline state
     */
    val currentPipelineState: VoiceAgentPipelineState
        get() = pipelineState

    /**
     * Check if pipeline is currently processing
     */
    val isProcessing: Boolean
        get() = processingMutex.isLocked

    /**
     * Check if all sub-components are ready
     */
    val areAllComponentsReady: Boolean
        get() = stt.isModelLoaded && llm.isModelLoaded && tts.isVoiceLoaded

    /**
     * Get component states for UI feedback
     */
    fun getComponentStates(): VoiceAgentComponentStates =
        VoiceAgentComponentStates(
            stt =
                if (stt.isModelLoaded) {
                    ComponentLoadState.Loaded(stt.currentModelId ?: "unknown")
                } else {
                    ComponentLoadState.NotLoaded
                },
            llm =
                if (llm.isModelLoaded) {
                    ComponentLoadState.Loaded(llm.currentModelId ?: "unknown")
                } else {
                    ComponentLoadState.NotLoaded
                },
            tts =
                if (tts.isVoiceLoaded) {
                    ComponentLoadState.Loaded(tts.currentVoiceId ?: "unknown")
                } else {
                    ComponentLoadState.NotLoaded
                },
        )

    // ============================================================================
    // MARK: - Initialization (iOS VoiceAgentCapability pattern)
    // ============================================================================

    /**
     * Initialize Voice Agent with full configuration
     *
     * This method is smart about reusing already-loaded models:
     * - If a model is already loaded with the same ID, it will be reused
     * - If a different model is loaded, it will be replaced
     * - If no model is loaded, the specified model will be loaded
     *
     * @param config VoiceAgentConfiguration with all sub-component configs
     * @throws SDKError if initialization fails
     */
    suspend fun initialize(config: VoiceAgentConfiguration) =
        mutex.withLock {
            logger.info("Initializing Voice Agent")

            try {
                EventPublisher.track(SDKVoiceEvent.PipelineStarted)

                initializeVAD(config.vadConfig)
                initializeSTTModel(config.sttConfig)
                initializeLLMModel(config.llmConfig)
                initializeTTSVoice(config.ttsConfig)
                verifyAllComponentsReady()

                currentConfiguration = config
                isConfigured = true

                logger.info("Voice Agent initialized successfully - all components ready")
                EventPublisher.track(SDKVoiceEvent.PipelineCompleted)
            } catch (e: Exception) {
                logger.error("Failed to initialize Voice Agent", e)
                isConfigured = false
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
        ttsVoice: String = "",
    ) {
        val config =
            VoiceAgentConfiguration(
                vadConfig = VADConfiguration(),
                sttConfig = STTConfiguration(modelId = sttModelId.ifEmpty { null }),
                llmConfig = LLMConfiguration(modelId = llmModelId.ifEmpty { null }),
                ttsConfig = TTSConfiguration(modelId = ttsVoice),
            )
        initialize(config)
    }

    /**
     * Initialize Voice Agent with already-loaded models
     * Matches iOS initializeVoiceAgentWithLoadedModels()
     *
     * Uses whatever models are already loaded in STT, LLM, and TTS capabilities
     *
     * @param vadConfig Optional VAD configuration. Use VADConfiguration.sensitive() for whisper detection.
     */
    suspend fun initializeWithLoadedModels(vadConfig: VADConfiguration = VADConfiguration()) =
        mutex.withLock {
            logger.info("Initializing Voice Agent with already-loaded models (VAD threshold: ${vadConfig.energyThreshold})")

            try {
                EventPublisher.track(SDKVoiceEvent.PipelineStarted)

                // Initialize VAD with provided configuration
                try {
                    vad.initialize(vadConfig)
                } catch (e: Exception) {
                    throw CapabilityError.CompositeComponentFailed("VAD", e)
                }

                // Verify all components are ready
                val sttReady = stt.isModelLoaded
                val llmReady = llm.isModelLoaded
                val ttsReady = tts.isVoiceLoaded

                if (!sttReady) {
                    throw CapabilityError.CompositeComponentFailed(
                        "STT",
                        CapabilityError.ResourceNotLoaded("No STT model loaded. Load one first via loadSTTModel()"),
                    )
                }
                if (!llmReady) {
                    throw CapabilityError.CompositeComponentFailed(
                        "LLM",
                        CapabilityError.ResourceNotLoaded("No LLM model loaded. Load one first via loadModel()"),
                    )
                }
                if (!ttsReady) {
                    throw CapabilityError.CompositeComponentFailed(
                        "TTS",
                        CapabilityError.ResourceNotLoaded("No TTS voice loaded. Load one first via loadTTSVoice()"),
                    )
                }

                isConfigured = true
                logger.info("Voice Agent initialized with pre-loaded models - all components ready")
                EventPublisher.track(SDKVoiceEvent.PipelineCompleted)
            } catch (e: Exception) {
                logger.error("Failed to initialize Voice Agent with loaded models", e)
                isConfigured = false
                EventPublisher.track(SDKVoiceEvent.PipelineError(e))
                throw e
            }
        }

    // MARK: - Private Initialization Helpers

    /** Initialize VAD component */
    private suspend fun initializeVAD(vadConfig: VADConfiguration) {
        try {
            vad.initialize(vadConfig)
        } catch (e: Exception) {
            throw CapabilityError.CompositeComponentFailed("VAD", e)
        }
    }

    /** Initialize STT model with smart reuse logic */
    private suspend fun initializeSTTModel(sttConfig: STTConfiguration) {
        val sttModelId = sttConfig.modelId
        if (sttModelId.isNullOrEmpty()) {
            return handleMissingSTTModel()
        }

        val currentModelId = stt.currentModelId
        val isLoaded = stt.isModelLoaded

        if (isLoaded && currentModelId == sttModelId) {
            logger.info("STT model already loaded: $sttModelId - reusing")
            return
        }

        logger.info("Loading STT model: $sttModelId")
        try {
            stt.loadModel(sttModelId)
        } catch (e: Exception) {
            throw CapabilityError.CompositeComponentFailed("STT", e)
        }
    }

    /** Handle case when no STT model is specified */
    private fun handleMissingSTTModel() {
        val isLoaded = stt.isModelLoaded
        if (isLoaded) {
            logger.info("Using already loaded STT model")
        } else {
            logger.warning("No STT model specified and none loaded - STT will not work")
        }
    }

    /** Initialize LLM model with smart reuse logic */
    private suspend fun initializeLLMModel(llmConfig: LLMConfiguration) {
        val llmModelId = llmConfig.modelId
        if (llmModelId.isNullOrEmpty()) {
            return handleMissingLLMModel()
        }

        val currentModelId = llm.currentModelId
        val isLoaded = llm.isModelLoaded

        if (isLoaded && currentModelId == llmModelId) {
            logger.info("LLM model already loaded: $llmModelId - reusing")
            return
        }

        logger.info("Loading LLM model: $llmModelId")
        try {
            llm.loadModel(llmModelId)
        } catch (e: Exception) {
            throw CapabilityError.CompositeComponentFailed("LLM", e)
        }
    }

    /** Handle case when no LLM model is specified */
    private fun handleMissingLLMModel() {
        val isLoaded = llm.isModelLoaded
        if (isLoaded) {
            logger.info("Using already loaded LLM model")
        } else {
            logger.warning("No LLM model specified and none loaded - LLM will not work")
        }
    }

    /** Initialize TTS voice with smart reuse logic */
    private suspend fun initializeTTSVoice(ttsConfig: TTSConfiguration) {
        val ttsVoice = ttsConfig.modelId
        if (ttsVoice.isNullOrEmpty()) {
            return handleMissingTTSVoice()
        }

        val currentVoiceId = tts.currentVoiceId
        val isLoaded = tts.isVoiceLoaded

        if (isLoaded && currentVoiceId == ttsVoice) {
            logger.info("TTS voice already loaded: $ttsVoice - reusing")
            return
        }

        logger.info("Loading TTS voice: $ttsVoice")
        try {
            tts.loadVoice(ttsVoice)
        } catch (e: Exception) {
            throw CapabilityError.CompositeComponentFailed("TTS", e)
        }
    }

    /** Handle case when no TTS voice is specified */
    private fun handleMissingTTSVoice() {
        val isLoaded = tts.isVoiceLoaded
        if (isLoaded) {
            logger.info("Using already loaded TTS voice")
        } else {
            logger.warning("No TTS voice specified and none loaded - TTS will not work")
        }
    }

    /** Verify all required components are ready */
    private fun verifyAllComponentsReady() {
        val sttReady = stt.isModelLoaded
        val llmReady = llm.isModelLoaded
        val ttsReady = tts.isVoiceLoaded

        if (!sttReady) {
            throw CapabilityError.CompositeComponentFailed(
                "STT",
                CapabilityError.ResourceNotLoaded("STT model not loaded"),
            )
        }

        if (!llmReady) {
            throw CapabilityError.CompositeComponentFailed(
                "LLM",
                CapabilityError.ResourceNotLoaded("LLM model not loaded"),
            )
        }

        if (!ttsReady) {
            throw CapabilityError.CompositeComponentFailed(
                "TTS",
                CapabilityError.ResourceNotLoaded("TTS voice not loaded"),
            )
        }
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
        if (!isConfigured) {
            throw CapabilityError.NotInitialized("Voice Agent")
        }

        logger.info("Processing voice turn")

        // Step 1: Transcribe audio
        logger.debug("Step 1: Transcribing audio")
        val transcriptionOutput = stt.transcribe(audioData)
        val transcription = transcriptionOutput.text

        if (transcription.isEmpty()) {
            logger.warning("Empty transcription, skipping processing")
            throw VoiceAgentError.EmptyTranscription
        }

        logger.info("Transcription: $transcription")

        // Step 2: Generate LLM response
        logger.debug("Step 2: Generating LLM response")
        val llmResult = llm.generate(transcription, LLMGenerationOptions())
        val response = llmResult.text

        logger.info("LLM Response: ${response.take(100)}...")

        // Step 3: Synthesize speech
        logger.debug("Step 3: Synthesizing speech")
        val ttsOutput = tts.synthesize(response, TTSOptions.default)

        logger.info("Voice turn completed")

        return VoiceAgentResult(
            speechDetected = true,
            transcription = transcription,
            response = response,
            synthesizedAudio = ttsOutput.audioData,
        )
    }

    /**
     * Process a stream of audio through the pipeline
     * Matches iOS processStream(_ audioStream: AsyncStream<Data>) -> AsyncThrowingStream<VoiceAgentEvent, Error>
     *
     * @param audioStream Flow of audio data chunks
     * @return Flow of VoiceAgentEvent for reactive consumption
     */
    fun processStream(audioStream: Flow<ByteArray>): Flow<VoiceAgentEvent> =
        flow {
            if (!isConfigured) {
                throw CapabilityError.NotInitialized("Voice Agent")
            }

            // Collect audio chunks
            val audioBuffer = mutableListOf<ByteArray>()
            audioStream.collect { chunk ->
                audioBuffer.add(chunk)
            }

            // Combine all chunks
            val totalSize = audioBuffer.sumOf { it.size }
            val combinedAudio = ByteArray(totalSize)
            var offset = 0
            audioBuffer.forEach { chunk ->
                chunk.copyInto(combinedAudio, offset)
                offset += chunk.size
            }

            try {
                // Transcribe
                val transcription = stt.transcribe(combinedAudio, STTOptions.default())
                emit(VoiceAgentEvent.TranscriptionAvailable(transcription.text))

                // Generate response
                val llmResult = llm.generate(transcription.text, LLMGenerationOptions())
                emit(VoiceAgentEvent.ResponseGenerated(llmResult.text))

                // Synthesize
                val ttsOutput = tts.synthesize(llmResult.text, TTSOptions.default)
                emit(VoiceAgentEvent.AudioSynthesized(ttsOutput.audioData))

                // Yield final result
                val result =
                    VoiceAgentResult(
                        speechDetected = true,
                        transcription = transcription.text,
                        response = llmResult.text,
                        synthesizedAudio = ttsOutput.audioData,
                    )
                emit(VoiceAgentEvent.Processed(result))
            } catch (e: Exception) {
                emit(VoiceAgentEvent.Error(e))
                throw e
            }
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
        if (!isConfigured) {
            throw CapabilityError.NotInitialized("Voice Agent")
        }
        val output = stt.transcribe(audioData)
        return output.text
    }

    /**
     * Generate response from text (LLM only)
     * Matches iOS voiceAgentGenerateResponse(_ prompt: String) -> String
     *
     * @param prompt Text prompt
     * @return Generated response
     */
    suspend fun generateResponse(prompt: String): String {
        if (!isConfigured) {
            throw CapabilityError.NotInitialized("Voice Agent")
        }
        val result = llm.generate(prompt, LLMGenerationOptions())
        return result.text
    }

    /**
     * Synthesize speech from text (TTS only)
     * Matches iOS voiceAgentSynthesizeSpeech(_ text: String) -> Data
     *
     * @param text Text to synthesize
     * @return Synthesized audio data
     */
    suspend fun synthesizeSpeech(text: String): ByteArray {
        if (!isConfigured) {
            throw CapabilityError.NotInitialized("Voice Agent")
        }
        val output = tts.synthesize(text, TTSOptions.default)
        return output.audioData
    }

    /**
     * Check if VAD detects speech
     *
     * @param samples Float audio samples
     * @return true if speech is detected
     */
    suspend fun detectSpeech(samples: FloatArray): Boolean {
        val output = vad.detectSpeech(samples)
        return output.isSpeechDetected
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

            llm.cleanup()
            stt.cleanup()
            tts.cleanup()
            vad.cleanup()

            isConfigured = false
            currentConfiguration = null
            pipelineState = VoiceAgentPipelineState.IDLE

            logger.info("Voice Agent cleaned up")
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
