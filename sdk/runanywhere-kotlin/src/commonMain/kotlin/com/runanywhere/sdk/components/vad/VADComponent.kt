package com.runanywhere.sdk.components.vad

import com.runanywhere.sdk.components.base.*
import com.runanywhere.sdk.data.models.SDKError
import kotlinx.coroutines.flow.*
import kotlinx.datetime.Clock

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
        val startTime = Clock.System.now().toEpochMilliseconds()

        // Process audio chunk
        val result = service.processAudioChunk(input.audioSamples)

        val processingTime = (Clock.System.now().toEpochMilliseconds() - startTime) / 1000.0

        // Calculate energy level (simple RMS)
        val energyLevel = calculateEnergyLevel(input.audioSamples)

        // Create metadata
        val metadata = VADMetadata(
            frameDuration = input.frameDuration ?: vadConfiguration.frameDuration,
            sampleRate = input.sampleRate ?: vadConfiguration.sampleRate,
            aggressiveness = vadConfiguration.aggressiveness,
            processingTime = processingTime
        )

        return VADOutput(
            isSpeech = result.isSpeech,
            confidence = result.confidence,
            energyLevel = energyLevel,
            speechProbability = result.confidence, // Use confidence as speech probability
            metadata = metadata
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
        val silenceFramesThreshold =
            vadConfiguration.silenceThreshold / vadConfiguration.frameDuration

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
     * Get service for compatibility
     */
    fun getService(): VADService? {
        return vadService
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
