package com.runanywhere.sdk.components.voiceagent

import com.runanywhere.sdk.components.base.BaseComponent
import com.runanywhere.sdk.components.base.SDKComponent
import com.runanywhere.sdk.components.llm.LLMComponent
import com.runanywhere.sdk.components.stt.STTComponent
import com.runanywhere.sdk.components.stt.STTInput
import com.runanywhere.sdk.components.stt.STTOptions
import com.runanywhere.sdk.components.vad.VADComponent
import com.runanywhere.sdk.components.vad.VADInput
import com.runanywhere.sdk.components.TTSComponent
import com.runanywhere.sdk.components.TTSOptions
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.events.EventPublisher
import com.runanywhere.sdk.events.SDKVoiceEvent
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.ServiceContainer
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.sync.Mutex

/**
 * Voice Agent Component - Orchestrates the complete voice AI pipeline
 * Combines VAD, STT, LLM, and TTS into a unified processing pipeline
 *
 * Matches iOS VoiceAgentComponent.swift exactly:
 * - Sequential initialization of sub-components
 * - Full pipeline processing: Audio -> VAD -> STT -> LLM -> TTS -> Audio
 * - Individual component access for custom orchestration
 * - Event-driven architecture with EventBus integration
 * - Streaming support via Flow
 */
class VoiceAgentComponent(
    private val agentConfiguration: VoiceAgentConfiguration,
    serviceContainer: ServiceContainer? = null
) : BaseComponent<VoiceAgentService>(agentConfiguration, serviceContainer) {

    private val logger = SDKLogger("VoiceAgentComponent")

    override val componentType: SDKComponent = SDKComponent.VOICE_AGENT

    // MARK: - Sub-Components (publicly accessible for custom orchestration)

    /** VAD component for voice activity detection */
    var vadComponent: VADComponent? = null
        private set

    /** STT component for speech-to-text */
    var sttComponent: STTComponent? = null
        private set

    /** LLM component for language model processing */
    var llmComponent: LLMComponent? = null
        private set

    /** TTS component for text-to-speech */
    var ttsComponent: TTSComponent? = null
        private set

    // MARK: - State Management

    /** Mutex to ensure atomic access to pipeline processing */
    private val processingMutex = Mutex()

    /** Current pipeline state */
    @Volatile
    private var pipelineState = VoiceAgentPipelineState.IDLE

    // MARK: - Service Creation

    override suspend fun createService(): VoiceAgentService {
        // VoiceAgentService is a simple wrapper - no external service needed
        return VoiceAgentService()
    }

    override suspend fun initializeService() {
        // Initialize all sub-components sequentially (matching iOS pattern)
        initializeComponents()

        // Publish pipeline started event
        EventPublisher.track(SDKVoiceEvent.PipelineStarted)
    }

    /**
     * Initialize all sub-components in order
     * Matches iOS initializeComponents() exactly
     */
    private suspend fun initializeComponents() {
        logger.info("Initializing VoiceAgent sub-components...")

        // 1. Initialize VAD
        try {
            logger.info("Initializing VAD component...")
            vadComponent = VADComponent(agentConfiguration.vadConfig)
            vadComponent?.initialize()
            logger.info("VAD component initialized successfully")
        } catch (e: Exception) {
            logger.error("Failed to initialize VAD component", e)
            throw VoiceAgentError.ComponentInitializationFailed("VAD", e)
        }

        // 2. Initialize STT
        try {
            logger.info("Initializing STT component...")
            sttComponent = STTComponent(agentConfiguration.sttConfig)
            sttComponent?.initialize()
            logger.info("STT component initialized successfully")
        } catch (e: Exception) {
            logger.error("Failed to initialize STT component", e)
            // Cleanup VAD before throwing
            vadComponent?.cleanup()
            vadComponent = null
            throw VoiceAgentError.ComponentInitializationFailed("STT", e)
        }

        // 3. Initialize LLM
        try {
            logger.info("Initializing LLM component...")
            llmComponent = LLMComponent(agentConfiguration.llmConfig)
            llmComponent?.initialize()
            logger.info("LLM component initialized successfully")
        } catch (e: Exception) {
            logger.error("Failed to initialize LLM component", e)
            // Cleanup STT and VAD before throwing
            sttComponent?.cleanup()
            sttComponent = null
            vadComponent?.cleanup()
            vadComponent = null
            throw VoiceAgentError.ComponentInitializationFailed("LLM", e)
        }

        // 4. Initialize TTS
        try {
            logger.info("Initializing TTS component...")
            ttsComponent = TTSComponent(agentConfiguration.ttsConfig)
            ttsComponent?.initialize()
            logger.info("TTS component initialized successfully")
        } catch (e: Exception) {
            logger.error("Failed to initialize TTS component", e)
            // Cleanup LLM, STT, and VAD before throwing
            llmComponent?.cleanup()
            llmComponent = null
            sttComponent?.cleanup()
            sttComponent = null
            vadComponent?.cleanup()
            vadComponent = null
            throw VoiceAgentError.ComponentInitializationFailed("TTS", e)
        }

        logger.info("All VoiceAgent sub-components initialized successfully")
    }

    override suspend fun performCleanup() {
        pipelineState = VoiceAgentPipelineState.IDLE

        // Cleanup all sub-components in order
        try {
            vadComponent?.cleanup()
        } catch (e: Exception) {
            logger.warn("Error cleaning up VAD component: ${e.message}")
        }
        vadComponent = null

        try {
            sttComponent?.cleanup()
        } catch (e: Exception) {
            logger.warn("Error cleaning up STT component: ${e.message}")
        }
        sttComponent = null

        try {
            llmComponent?.cleanup()
        } catch (e: Exception) {
            logger.warn("Error cleaning up LLM component: ${e.message}")
        }
        llmComponent = null

        try {
            ttsComponent?.cleanup()
        } catch (e: Exception) {
            logger.warn("Error cleaning up TTS component: ${e.message}")
        }
        ttsComponent = null

        logger.info("VoiceAgent pipeline cleaned up")
    }

    // MARK: - Full Pipeline Processing

    /**
     * Process audio through the complete VAD -> STT -> LLM -> TTS pipeline
     * Matches iOS processAudio(_ audioData: Data) -> VoiceAgentResult
     *
     * @param audioData Raw audio data (PCM format expected)
     * @return VoiceAgentResult with all intermediate results
     */
    suspend fun processAudio(audioData: ByteArray): VoiceAgentResult {
        ensureReady()

        if (!processingMutex.tryLock()) {
            throw SDKError.InvalidState("Pipeline is already processing")
        }

        try {
            pipelineState = VoiceAgentPipelineState.VAD_PROCESSING
            var result = VoiceAgentResult()

            // Step 1: VAD - Voice Activity Detection
            val audioSamples = audioData.toFloatArray()
            val speechDetected = detectVoiceActivity(audioSamples)
            result = result.copy(speechDetected = speechDetected)

            if (!speechDetected) {
                logger.debug("No speech detected, returning early")
                pipelineState = VoiceAgentPipelineState.COMPLETED
                return result
            }

            // Publish speech detected event
            EventPublisher.track(SDKVoiceEvent.SpeechDetected)

            // Step 2: STT - Speech to Text
            pipelineState = VoiceAgentPipelineState.STT_PROCESSING
            val transcription = transcribe(audioData)
            result = result.copy(transcription = transcription)

            if (transcription.isNullOrBlank()) {
                logger.debug("No transcription result, returning early")
                pipelineState = VoiceAgentPipelineState.COMPLETED
                return result
            }

            // Publish transcription event
            EventPublisher.track(SDKVoiceEvent.TranscriptionFinal(transcription))

            // Step 3: LLM - Generate Response
            pipelineState = VoiceAgentPipelineState.LLM_PROCESSING
            val response = generateResponse(transcription)
            result = result.copy(response = response)

            if (response.isNullOrBlank()) {
                logger.debug("No LLM response, returning early")
                pipelineState = VoiceAgentPipelineState.COMPLETED
                return result
            }

            // Publish response generated event
            EventPublisher.track(SDKVoiceEvent.ResponseGenerated(response))

            // Step 4: TTS - Text to Speech
            pipelineState = VoiceAgentPipelineState.TTS_PROCESSING
            val synthesizedAudio = synthesizeSpeech(response)
            result = result.copy(synthesizedAudio = synthesizedAudio)

            if (synthesizedAudio != null) {
                // Publish audio generated event
                EventPublisher.track(SDKVoiceEvent.AudioGenerated(synthesizedAudio))
            }

            pipelineState = VoiceAgentPipelineState.COMPLETED
            return result

        } catch (e: Exception) {
            pipelineState = VoiceAgentPipelineState.ERROR
            logger.error("Pipeline processing failed", e)
            EventPublisher.track(SDKVoiceEvent.PipelineError(e))
            throw e
        } finally {
            processingMutex.unlock()
        }
    }

    /**
     * Process a continuous audio stream through the pipeline
     * Matches iOS processStream(_ audioStream: AsyncStream<Data>) -> AsyncThrowingStream<VoiceAgentEvent, Error>
     *
     * @param audioStream Flow of audio data chunks
     * @return Flow of VoiceAgentEvent for reactive consumption
     */
    fun processStream(audioStream: Flow<ByteArray>): Flow<VoiceAgentEvent> = flow {
        ensureReady()

        try {
            audioStream.collect { audioData ->
                try {
                    val result = processAudio(audioData)
                    emit(VoiceAgentEvent.Processed(result))
                } catch (e: Exception) {
                    emit(VoiceAgentEvent.Error(e))
                }
            }
        } catch (e: Exception) {
            emit(VoiceAgentEvent.Error(e))
        }
    }

    // MARK: - Individual Component Access (for custom orchestration)

    /**
     * Process only VAD - Voice Activity Detection
     * Matches iOS detectVoiceActivity(_ audioData: Data) -> Bool
     *
     * @param audioData Raw audio samples as float array
     * @return true if speech is detected
     */
    fun detectVoiceActivity(audioSamples: FloatArray): Boolean {
        val vad = vadComponent
            ?: throw SDKError.ComponentNotReady("VAD component is not initialized")

        val vadInput = VADInput(audioSamples = audioSamples)
        val vadOutput = vad.process(vadInput)
        return vadOutput.isSpeechDetected
    }

    /**
     * Convenience method for ByteArray input
     */
    fun detectVoiceActivity(audioData: ByteArray): Boolean {
        return detectVoiceActivity(audioData.toFloatArray())
    }

    /**
     * Process only STT - Speech to Text
     * Matches iOS transcribe(_ audioData: Data) -> String?
     *
     * @param audioData Raw audio data
     * @return Transcribed text or null if transcription fails
     */
    suspend fun transcribe(audioData: ByteArray): String? {
        val stt = sttComponent
            ?: throw SDKError.ComponentNotReady("STT component is not initialized")

        return try {
            val sttInput = STTInput(
                audioData = audioData,
                options = STTOptions(
                    language = agentConfiguration.sttConfig.language,
                    enablePunctuation = agentConfiguration.sttConfig.enablePunctuation,
                    enableTimestamps = agentConfiguration.sttConfig.enableTimestamps
                )
            )
            val sttOutput = stt.process(sttInput)
            sttOutput.text.takeIf { it.isNotBlank() }
        } catch (e: Exception) {
            logger.error("STT transcription failed", e)
            throw VoiceAgentError.STTFailed(e)
        }
    }

    /**
     * Process only LLM - Generate Response
     * Matches iOS generateResponse(_ prompt: String) -> String?
     *
     * @param prompt Text prompt for the LLM
     * @return Generated response or null if generation fails
     */
    suspend fun generateResponse(prompt: String): String? {
        val llm = llmComponent
            ?: throw SDKError.ComponentNotReady("LLM component is not initialized")

        return try {
            val llmOutput = llm.generate(
                prompt = prompt,
                systemPrompt = agentConfiguration.llmConfig.systemPrompt
            )
            llmOutput.text.takeIf { it.isNotBlank() }
        } catch (e: Exception) {
            logger.error("LLM generation failed", e)
            throw VoiceAgentError.LLMFailed(e)
        }
    }

    /**
     * Process only TTS - Text to Speech
     * Matches iOS synthesizeSpeech(_ text: String) -> Data?
     *
     * @param text Text to synthesize
     * @return Synthesized audio data or null if synthesis fails
     */
    suspend fun synthesizeSpeech(text: String): ByteArray? {
        val tts = ttsComponent
            ?: throw SDKError.ComponentNotReady("TTS component is not initialized")

        return try {
            val ttsOutput = tts.synthesize(
                text = text,
                voice = agentConfiguration.ttsConfig.voice,
                language = agentConfiguration.ttsConfig.language
            )
            ttsOutput.audioData.takeIf { it.isNotEmpty() }
        } catch (e: Exception) {
            logger.error("TTS synthesis failed", e)
            throw VoiceAgentError.TTSFailed(e)
        }
    }

    // MARK: - Utility Methods

    /**
     * Get current pipeline state
     */
    fun getPipelineState(): VoiceAgentPipelineState = pipelineState

    /**
     * Check if pipeline is currently processing
     */
    fun isProcessing(): Boolean = processingMutex.isLocked

    /**
     * Check if all sub-components are ready
     */
    fun areAllComponentsReady(): Boolean {
        return vadComponent?.isReady == true &&
                sttComponent?.isReady == true &&
                llmComponent?.isReady == true &&
                ttsComponent?.isReady == true
    }

    companion object {
        val componentType: SDKComponent = SDKComponent.VOICE_AGENT
    }
}

// MARK: - Audio Conversion Extension

/**
 * Convert ByteArray to FloatArray for VAD processing
 * Assumes 16-bit PCM audio data (2 bytes per sample)
 */
private fun ByteArray.toFloatArray(): FloatArray {
    // Handle raw bytes as 16-bit PCM samples (little-endian)
    val sampleCount = this.size / 2
    val floatArray = FloatArray(sampleCount)

    for (i in 0 until sampleCount) {
        val low = this[i * 2].toInt() and 0xFF
        val high = this[i * 2 + 1].toInt()
        val sample = (high shl 8) or low
        // Normalize to -1.0 to 1.0 range
        floatArray[i] = sample / 32768.0f
    }

    return floatArray
}
