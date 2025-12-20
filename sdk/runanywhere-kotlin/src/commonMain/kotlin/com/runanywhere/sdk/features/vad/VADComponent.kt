package com.runanywhere.sdk.features.vad

import com.runanywhere.sdk.core.ModuleRegistry
import com.runanywhere.sdk.core.capabilities.*
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.models.enums.InferenceFramework
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch

// MARK: - VAD Component

/**
 * Voice Activity Detection component following the clean architecture.
 * Integrates with VADAnalyticsService for event tracking matching iOS pattern.
 */
class VADComponent(
    configuration: VADConfiguration,
    private val analyticsService: VADAnalyticsService = VADAnalyticsService(),
) : BaseComponent<VADServiceWrapper>(configuration) {
    // MARK: - Properties

    override val componentType: SDKComponent = SDKComponent.VAD

    private val vadConfiguration: VADConfiguration = configuration

    /** Coroutine scope for analytics operations */
    private val analyticsScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    // MARK: - Service Creation

    override suspend fun createService(): VADServiceWrapper {
        // Try to get a registered VAD provider from central registry
        val provider =
            ModuleRegistry.vadProvider(vadConfiguration.modelId)
                ?: run {
                    analyticsService.trackInitializationFailed(
                        error = "No VAD service provider registered",
                        framework = InferenceFramework.BUILT_IN,
                    )
                    throw SDKError.ComponentNotInitialized(
                        "No VAD service provider registered. Please register WebRTCVADServiceProvider.register()",
                    )
                }

        try {
            // Create service through provider
            val vadService = provider.createVADService(vadConfiguration)

            // Track successful initialization (using BUILT_IN for energy-based VAD)
            analyticsService.trackInitialized(framework = InferenceFramework.BUILT_IN)

            // Wrap the service
            return VADServiceWrapper(vadService)
        } catch (e: Exception) {
            analyticsService.trackInitializationFailed(
                error = e.message ?: "Unknown error",
                framework = InferenceFramework.BUILT_IN,
            )
            throw e
        }
    }

    override suspend fun performCleanup() {
        analyticsService.trackCleanedUp()
        service?.wrappedService?.cleanup()
    }

    // MARK: - Helper Methods

    private val vadService: VADService?
        get() = service?.wrappedService

    // MARK: - Public API

    /**
     * Process audio samples for voice activity detection - matching iOS detectSpeech(in: [Float])
     */
    fun processAudioChunk(audioSamples: FloatArray): VADOutput {
        ensureReady()

        val input =
            VADInput(
                audioSamples = audioSamples,
            )
        return process(input)
    }

    /**
     * Detect speech in audio samples - iOS-style method name
     */
    fun detectSpeech(audioSamples: FloatArray): VADOutput = processAudioChunk(audioSamples)

    /**
     * Process VAD input - supporting threshold override like iOS
     */
    fun process(input: VADInput): VADOutput {
        ensureReady()

        val service = vadService ?: throw SDKError.ComponentNotReady("VAD service not available")

        // Validate input
        input.validate()

        // Apply threshold override if provided (matching iOS pattern)
        val originalThreshold = service.energyThreshold
        input.energyThresholdOverride?.let { override ->
            service.energyThreshold = override
        }

        try {
            // Process audio chunk
            val result = service.processAudioChunk(input.audioSamples)

            // Calculate energy level (simple RMS)
            val energyLevel = calculateEnergyLevel(input.audioSamples)

            return VADOutput(
                isSpeechDetected = result.isSpeechDetected,
                energyLevel = energyLevel,
                confidence = result.confidence,
            )
        } finally {
            // Restore original threshold if it was overridden
            if (input.energyThresholdOverride != null) {
                service.energyThreshold = originalThreshold
            }
        }
    }

    /**
     * Stream VAD processing
     */
    fun streamProcess(audioStream: Flow<FloatArray>): Flow<VADOutput> =
        flow {
            ensureReady()

            audioStream.collect { audioSamples ->
                val output = processAudioChunk(audioSamples)
                emit(output)
            }
        }.catch { error ->
            throw VADError.ProcessingFailed(error)
        }

    /**
     * Process with speech segments detection.
     * Tracks speech start/end events for analytics matching iOS pattern.
     */
    fun detectSpeechSegments(
        audioStream: Flow<FloatArray>,
        onSpeechStart: () -> Unit = {},
        onSpeechEnd: () -> Unit = {},
    ): Flow<VADOutput> =
        flow {
            ensureReady()

            var isInSpeech = false
            var silenceFrames = 0
            // Use iOS-style hysteresis - 10 frames of silence to end speech
            val silenceFramesThreshold = 10

            audioStream.collect { audioSamples ->
                val output = processAudioChunk(audioSamples)

                when {
                    output.isSpeechDetected && !isInSpeech -> {
                        isInSpeech = true
                        silenceFrames = 0
                        // Track speech start for analytics
                        analyticsScope.launch { analyticsService.trackSpeechStart() }
                        onSpeechStart()
                    }

                    !output.isSpeechDetected && isInSpeech -> {
                        silenceFrames++
                        if (silenceFrames >= silenceFramesThreshold) {
                            isInSpeech = false
                            // Track speech end for analytics
                            analyticsScope.launch { analyticsService.trackSpeechEnd() }
                            onSpeechEnd()
                        }
                    }

                    output.isSpeechDetected && isInSpeech -> {
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
     * Set audio buffer callback (matching iOS pattern)
     */
    fun setAudioBufferCallback(callback: (ByteArray) -> Unit) {
        vadService?.onAudioBuffer = callback
    }

    /**
     * Get service for compatibility
     */
    fun getService(): VADService? = vadService

    /**
     * Check if VAD is enabled
     */
    fun isEnabled(): Boolean = state == ComponentState.READY

    /**
     * Start VAD processing - matching iOS method.
     * Tracks started event for analytics.
     */
    fun start() {
        analyticsScope.launch { analyticsService.trackStarted() }
        vadService?.start()
    }

    /**
     * Stop VAD processing - matching iOS method.
     * Tracks stopped event for analytics.
     */
    fun stop() {
        analyticsScope.launch { analyticsService.trackStopped() }
        vadService?.stop()
    }

    /**
     * Pause VAD processing - matching iOS method.
     * Tracks paused event for analytics.
     */
    fun pause() {
        analyticsScope.launch { analyticsService.trackPaused() }
        // VAD service may not have pause, but we track the event
    }

    /**
     * Resume VAD processing - matching iOS method.
     * Tracks resumed event for analytics.
     */
    fun resume() {
        analyticsScope.launch { analyticsService.trackResumed() }
        // VAD service may not have resume, but we track the event
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

    // MARK: - Analytics

    /**
     * Get current VAD analytics metrics.
     * Matches iOS getAnalyticsMetrics() pattern.
     */
    suspend fun getAnalyticsMetrics(): VADMetrics = analyticsService.getMetrics()

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
