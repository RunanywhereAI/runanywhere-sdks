package com.runanywhere.sdk.features.vad

import com.runanywhere.sdk.core.ModuleRegistry
import com.runanywhere.sdk.core.capabilities.ServiceBasedCapability
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.models.enums.InferenceFramework
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

/**
 * VAD Capability - Actor-like class for Voice Activity Detection operations
 *
 * Aligned EXACTLY with iOS VADCapability pattern:
 * - ServiceBasedCapability (not ModelLoadable) - no model loading, just service initialization
 * - Service lifecycle management (initialize, cleanup)
 * - Detection API (detectSpeech)
 * - Control API (start, stop, reset, pause, resume)
 * - Configuration updates (setEnergyThreshold, setSpeechActivityCallback)
 * - Analytics tracking via VADAnalyticsService
 * - TTS integration (notifyTTSWillStart, notifyTTSDidFinish)
 */
class VADCapability internal constructor(
    private val analyticsService: VADAnalyticsService = VADAnalyticsService(),
) : ServiceBasedCapability<VADConfiguration, VADService> {
    private val logger = SDKLogger("VADCapability")

    // Current VAD service
    private var service: VADService? = null

    // Whether VAD is initialized
    private var isConfigured = false

    // Current configuration
    private var config: VADConfiguration? = null

    // ============================================================================
    // MARK: - State Properties (iOS ServiceBasedCapability pattern)
    // ============================================================================

    /**
     * Whether VAD is ready for use
     */
    override val isReady: Boolean
        get() = isConfigured && service != null

    /**
     * Whether speech is currently active
     */
    val isSpeechActive: Boolean
        get() = service?.isSpeechActive ?: false

    /**
     * Current energy threshold
     */
    val energyThreshold: Float
        get() = service?.energyThreshold ?: 0.0f

    // ============================================================================
    // MARK: - Configuration (Capability Protocol)
    // ============================================================================

    override fun configure(config: VADConfiguration) {
        this.config = config
        // Configuration is passed during initialize
    }

    // ============================================================================
    // MARK: - Service Lifecycle (ServiceBasedCapability Protocol)
    // ============================================================================

    /**
     * Initialize VAD with default configuration
     *
     * @throws SDKError if initialization fails
     */
    override suspend fun initialize() {
        initialize(config ?: VADConfiguration())
    }

    /**
     * Initialize VAD with custom configuration
     *
     * @param config VAD configuration
     * @throws SDKError if initialization fails
     */
    override suspend fun initialize(config: VADConfiguration) {
        logger.info("Initializing VAD")

        // Try to get service from ModuleRegistry, fallback to built-in
        val vadService: VADService

        try {
            val provider = ModuleRegistry.vadProvider(config.modelId)
            if (provider != null) {
                vadService = provider.createVADService(config)
            } else {
                // Fall back to built-in SimpleEnergyVAD
                vadService = SimpleEnergyVAD(vadConfig = config)
                vadService.initialize(config)
            }

            this.service = vadService
            this.config = config
            this.isConfigured = true

            // Track initialization success
            analyticsService.trackInitialized(framework = InferenceFramework.BUILT_IN)

            logger.info("VAD initialized successfully")
        } catch (e: Exception) {
            // Track initialization failure
            analyticsService.trackInitializationFailed(
                error = e.message ?: e.toString(),
                framework = InferenceFramework.BUILT_IN,
            )
            logger.error("Failed to initialize VAD", e)
            throw SDKError.InitializationFailed("VAD initialization failed: ${e.message}")
        }
    }

    /**
     * Cleanup VAD resources
     */
    override suspend fun cleanup() {
        logger.info("Cleaning up VAD")

        service?.stop()
        service?.cleanup()
        service = null
        isConfigured = false

        // Track cleanup
        analyticsService.trackCleanedUp()
    }

    // ============================================================================
    // MARK: - Detection API (iOS detectSpeech pattern)
    // ============================================================================

    /**
     * Detect speech in audio samples
     *
     * @param samples Float array of audio samples
     * @return VADOutput with detection result
     * @throws SDKError if VAD is not ready
     */
    fun detectSpeech(samples: FloatArray): VADOutput {
        ensureReady()

        val vadService = service!!
        val result = vadService.processAudioChunk(samples)

        // Calculate energy level (simple RMS)
        val energyLevel = calculateEnergyLevel(samples)

        return VADOutput(
            isSpeechDetected = result.isSpeechDetected,
            energyLevel = energyLevel,
            confidence = result.confidence,
        )
    }

    /**
     * Detect speech with energy threshold override
     *
     * @param samples Float array of audio samples
     * @param energyThresholdOverride Optional threshold override for this detection
     * @return VADOutput with detection result
     * @throws SDKError if VAD is not ready
     */
    fun detectSpeech(
        samples: FloatArray,
        energyThresholdOverride: Float? = null,
    ): VADOutput {
        ensureReady()

        val vadService = service!!

        // Apply threshold override if provided
        val originalThreshold = vadService.energyThreshold
        energyThresholdOverride?.let { override ->
            vadService.energyThreshold = override
        }

        try {
            val result = vadService.processAudioChunk(samples)
            val energyLevel = calculateEnergyLevel(samples)

            return VADOutput(
                isSpeechDetected = result.isSpeechDetected,
                energyLevel = energyLevel,
                confidence = result.confidence,
            )
        } finally {
            // Restore original threshold
            if (energyThresholdOverride != null) {
                vadService.energyThreshold = originalThreshold
            }
        }
    }

    /**
     * Stream VAD processing
     *
     * @param audioStream Flow of audio samples
     * @return Flow of VADOutput with detection results
     */
    fun streamDetectSpeech(audioStream: Flow<FloatArray>): Flow<VADOutput> = flow {
        ensureReady()

        audioStream.collect { samples ->
            val output = detectSpeech(samples)
            emit(output)
        }
    }

    /**
     * Detect speech segments with callbacks (matching iOS pattern)
     *
     * @param audioStream Flow of audio samples
     * @param onSpeechStart Callback when speech starts
     * @param onSpeechEnd Callback when speech ends
     * @return Flow of VADOutput with detection results
     */
    fun detectSpeechSegments(
        audioStream: Flow<FloatArray>,
        onSpeechStart: () -> Unit = {},
        onSpeechEnd: () -> Unit = {},
    ): Flow<VADOutput> = flow {
        ensureReady()

        var isInSpeech = false
        var silenceFrames = 0
        // Use iOS-style hysteresis - 10 frames of silence to end speech
        val silenceFramesThreshold = 10

        audioStream.collect { samples ->
            val output = detectSpeech(samples)

            when {
                output.isSpeechDetected && !isInSpeech -> {
                    isInSpeech = true
                    silenceFrames = 0
                    analyticsService.trackSpeechStart()
                    onSpeechStart()
                }

                !output.isSpeechDetected && isInSpeech -> {
                    silenceFrames++
                    if (silenceFrames >= silenceFramesThreshold) {
                        isInSpeech = false
                        analyticsService.trackSpeechEnd()
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

    // ============================================================================
    // MARK: - Control API (iOS start/stop/reset pattern)
    // ============================================================================

    /**
     * Start VAD processing
     */
    suspend fun start() {
        logger.info("Starting VAD")
        service?.start()
        analyticsService.trackStarted()
    }

    /**
     * Stop VAD processing
     */
    suspend fun stop() {
        logger.info("Stopping VAD")
        service?.stop()
        analyticsService.trackStopped()
    }

    /**
     * Reset VAD state
     */
    fun reset() {
        logger.info("Resetting VAD")
        service?.reset()
    }

    /**
     * Pause VAD processing
     */
    suspend fun pause() {
        logger.info("Pausing VAD")
        service?.pause()
        analyticsService.trackPaused()
    }

    /**
     * Resume VAD processing
     */
    suspend fun resume() {
        logger.info("Resuming VAD")
        service?.resume()
        analyticsService.trackResumed()
    }

    // ============================================================================
    // MARK: - Configuration Updates (iOS pattern)
    // ============================================================================

    /**
     * Set energy threshold
     *
     * @param threshold New energy threshold (0.0 to 1.0)
     */
    fun setEnergyThreshold(threshold: Float) {
        service?.energyThreshold = threshold
    }

    /**
     * Set speech activity callback
     *
     * @param callback Callback invoked when speech state changes
     */
    fun setSpeechActivityCallback(callback: (SpeechActivityEvent) -> Unit) {
        service?.onSpeechActivity = callback
    }

    /**
     * Set audio buffer callback
     *
     * @param callback Callback invoked for processed audio buffers
     */
    fun setAudioBufferCallback(callback: (ByteArray) -> Unit) {
        service?.onAudioBuffer = callback
    }

    // ============================================================================
    // MARK: - TTS Integration (iOS pattern)
    // ============================================================================

    /**
     * Notify VAD that TTS is about to start (to adjust sensitivity)
     */
    fun notifyTTSWillStart() {
        service?.notifyTTSWillStart()
    }

    /**
     * Notify VAD that TTS has finished
     */
    fun notifyTTSDidFinish() {
        service?.notifyTTSDidFinish()
    }

    // ============================================================================
    // MARK: - Analytics (iOS getAnalyticsMetrics pattern)
    // ============================================================================

    /**
     * Get current VAD analytics metrics.
     * Matches iOS getAnalyticsMetrics() pattern.
     *
     * @return VADMetrics with aggregated statistics
     */
    suspend fun getAnalyticsMetrics(): VADMetrics = analyticsService.getMetrics()

    // ============================================================================
    // MARK: - Private Helpers
    // ============================================================================

    private fun ensureReady() {
        if (!isReady) {
            throw SDKError.ComponentNotReady("VAD not initialized. Call initializeVAD() first.")
        }
    }

    private fun calculateEnergyLevel(audioSamples: FloatArray): Float {
        if (audioSamples.isEmpty()) return 0f

        var sum = 0.0
        for (sample in audioSamples) {
            sum += sample * sample
        }

        return kotlin.math.sqrt(sum / audioSamples.size).toFloat()
    }
}
