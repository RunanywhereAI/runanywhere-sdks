package com.runanywhere.sdk.components.vad

import com.runanywhere.sdk.components.base.*
import com.runanywhere.sdk.core.ModuleRegistry
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.utils.getCurrentTimeMillis
import kotlinx.coroutines.flow.*

// MARK: - VAD Component

/**
 * Voice Activity Detection component following the clean architecture
 */
class VADComponent(configuration: VADConfiguration) :
    BaseComponent<VADServiceWrapper>(configuration) {

    // MARK: - Properties

    override val componentType: SDKComponent = SDKComponent.VAD

    private val vadConfiguration: VADConfiguration = configuration

    // MARK: - Service Creation

    override suspend fun createService(): VADServiceWrapper {
        // Try to get a registered VAD provider from central registry
        val provider = ModuleRegistry.vadProvider(vadConfiguration.modelId)
            ?: throw SDKError.ComponentNotInitialized(
                "No VAD service provider registered. Please register WebRTCVADServiceProvider.register()"
            )

        // Create service through provider
        val vadService = provider.createVADService(vadConfiguration)

        // Wrap the service
        return VADServiceWrapper(vadService)
    }

    override suspend fun performCleanup() {
        service?.wrappedService?.cleanup()
    }

    // MARK: - Helper Methods

    private val vadService: VADService?
        get() = service?.wrappedService

    // MARK: - Public API

    /**
     * Process audio samples for voice activity detection
     */
    fun processAudioChunk(audioSamples: FloatArray): VADOutput {
        ensureReady()

        val input = VADInput(
            audioSamples = audioSamples
        )
        return process(input)
    }

    /**
     * Process VAD input
     */
    fun process(input: VADInput): VADOutput {
        ensureReady()

        val service = vadService ?: throw SDKError.ComponentNotReady("VAD service not available")

        // Validate input
        input.validate()

        // Track processing time
        val startTime = getCurrentTimeMillis()

        // Process audio chunk
        val result = service.processAudioChunk(input.audioSamples)

        val processingTime = (getCurrentTimeMillis() - startTime) / 1000.0

        // Calculate energy level (simple RMS)
        val energyLevel = calculateEnergyLevel(input.audioSamples)

        return VADOutput(
            isSpeech = result.isSpeech,
            energyLevel = energyLevel,
            confidence = result.confidence
        )
    }

    /**
     * Stream VAD processing
     */
    fun streamProcess(audioStream: Flow<FloatArray>): Flow<VADOutput> = flow {
        ensureReady()

        audioStream.collect { audioSamples ->
            val output = processAudioChunk(audioSamples)
            emit(output)
        }
    }.catch { error ->
        throw VADError.ProcessingFailed(error)
    }

    /**
     * Process with speech segments detection
     */
    fun detectSpeechSegments(
        audioStream: Flow<FloatArray>,
        onSpeechStart: () -> Unit = {},
        onSpeechEnd: () -> Unit = {}
    ): Flow<VADOutput> = flow {
        ensureReady()

        var isInSpeech = false
        var silenceFrames = 0
        // Use iOS-style hysteresis - 10 frames of silence to end speech
        val silenceFramesThreshold = 10

        audioStream.collect { audioSamples ->
            val output = processAudioChunk(audioSamples)

            when {
                output.isSpeech && !isInSpeech -> {
                    isInSpeech = true
                    silenceFrames = 0
                    onSpeechStart()
                }

                !output.isSpeech && isInSpeech -> {
                    silenceFrames++
                    if (silenceFrames >= silenceFramesThreshold) {
                        isInSpeech = false
                        onSpeechEnd()
                    }
                }

                output.isSpeech && isInSpeech -> {
                    silenceFrames = 0
                }
            }

            emit(output)
        }
    }

    /**
     * Reset VAD state
     */
    fun reset() {
        vadService?.reset()
    }

    /**
     * Set speech activity callback (matching iOS pattern)
     */
    fun setSpeechActivityCallback(callback: (SpeechActivityEvent) -> Unit) {
        vadService?.onSpeechActivity = callback
    }

    /**
     * Get service for compatibility
     */
    fun getService(): VADService? {
        return vadService
    }

    /**
     * Check if VAD is enabled
     */
    fun isEnabled(): Boolean {
        return state == ComponentState.READY
    }

    /**
     * Enable VAD (initialize if needed)
     */
    suspend fun enable() {
        if (state != ComponentState.READY) {
            initialize()
        }
    }

    /**
     * Disable VAD
     */
    suspend fun disable() {
        if (state == ComponentState.READY) {
            cleanup()
        }
    }

    /**
     * Process audio and keep pipeline warm
     */
    fun processAudio(audioData: ByteArray): ByteArray {
        // Simply pass through for now
        // In production, this would apply VAD filtering
        return audioData
    }

    // MARK: - Private Helpers

    private fun calculateEnergyLevel(audioSamples: FloatArray): Float {
        if (audioSamples.isEmpty()) return 0f

        var sum = 0.0
        for (sample in audioSamples) {
            sum += sample * sample
        }

        return kotlin.math.sqrt(sum / audioSamples.size).toFloat()
    }
}
