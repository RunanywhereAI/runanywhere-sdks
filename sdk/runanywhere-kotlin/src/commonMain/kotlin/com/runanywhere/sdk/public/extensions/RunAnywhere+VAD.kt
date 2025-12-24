package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.features.vad.SpeechActivityEvent
import com.runanywhere.sdk.features.vad.VADConfiguration
import com.runanywhere.sdk.features.vad.VADOutput
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.flow.Flow

/**
 * VAD (Voice Activity Detection) extension functions for RunAnywhere
 *
 * Provides public API for voice activity detection operations,
 * aligned with iOS RunAnywhere+VAD.swift pattern.
 */

// ============================================================================
// MARK: - Initialization
// ============================================================================

/**
 * Initialize VAD with default configuration
 *
 * @throws SDKError if SDK is not initialized
 */
suspend fun RunAnywhere.initializeVAD() {
    requireInitialized()
    vadCapability.initialize()
}

/**
 * Initialize VAD with configuration
 *
 * @param config VAD configuration
 * @throws SDKError if SDK is not initialized
 */
suspend fun RunAnywhere.initializeVAD(config: VADConfiguration) {
    requireInitialized()
    vadCapability.initialize(config)
}

/**
 * Check if VAD is ready
 */
val RunAnywhere.isVADReady: Boolean
    get() = vadCapability.isReady

// ============================================================================
// MARK: - Detection
// ============================================================================

/**
 * Detect speech in audio samples
 *
 * @param samples Float array of audio samples
 * @return VADOutput with detection result
 * @throws SDKError if SDK is not initialized or VAD not ready
 */
fun RunAnywhere.detectSpeech(samples: FloatArray): VADOutput {
    requireInitialized()
    return vadCapability.detectSpeech(samples)
}

/**
 * Detect speech with energy threshold override
 *
 * @param samples Float array of audio samples
 * @param energyThresholdOverride Optional threshold override
 * @return VADOutput with detection result
 */
fun RunAnywhere.detectSpeech(
    samples: FloatArray,
    energyThresholdOverride: Float,
): VADOutput {
    requireInitialized()
    return vadCapability.detectSpeech(samples, energyThresholdOverride)
}

/**
 * Stream VAD detection
 *
 * @param audioStream Flow of audio samples
 * @return Flow of VADOutput with detection results
 */
fun RunAnywhere.streamDetectSpeech(audioStream: Flow<FloatArray>): Flow<VADOutput> {
    requireInitialized()
    return vadCapability.streamDetectSpeech(audioStream)
}

/**
 * Detect speech segments with callbacks
 *
 * @param audioStream Flow of audio samples
 * @param onSpeechStart Callback when speech starts
 * @param onSpeechEnd Callback when speech ends
 * @return Flow of VADOutput with detection results
 */
fun RunAnywhere.detectSpeechSegments(
    audioStream: Flow<FloatArray>,
    onSpeechStart: () -> Unit = {},
    onSpeechEnd: () -> Unit = {},
): Flow<VADOutput> {
    requireInitialized()
    return vadCapability.detectSpeechSegments(audioStream, onSpeechStart, onSpeechEnd)
}

// ============================================================================
// MARK: - Control
// ============================================================================

/**
 * Start VAD processing
 */
suspend fun RunAnywhere.startVAD() {
    vadCapability.start()
}

/**
 * Stop VAD processing
 */
suspend fun RunAnywhere.stopVAD() {
    vadCapability.stop()
}

/**
 * Reset VAD state
 */
fun RunAnywhere.resetVAD() {
    vadCapability.reset()
}

// ============================================================================
// MARK: - Configuration
// ============================================================================

/**
 * Set VAD energy threshold
 *
 * @param threshold New energy threshold (0.0 to 1.0)
 */
fun RunAnywhere.setVADEnergyThreshold(threshold: Float) {
    vadCapability.setEnergyThreshold(threshold)
}

/**
 * Get current energy threshold
 */
val RunAnywhere.vadEnergyThreshold: Float
    get() = vadCapability.energyThreshold

/**
 * Check if speech is currently active
 */
val RunAnywhere.isVADSpeechActive: Boolean
    get() = vadCapability.isSpeechActive

// ============================================================================
// MARK: - Callbacks
// ============================================================================

/**
 * Set speech activity callback
 *
 * @param callback Callback invoked on speech activity changes
 */
fun RunAnywhere.setVADSpeechActivityCallback(callback: (SpeechActivityEvent) -> Unit) {
    vadCapability.setSpeechActivityCallback(callback)
}

/**
 * Set audio buffer callback
 *
 * @param callback Callback invoked with audio buffer data
 */
fun RunAnywhere.setVADAudioBufferCallback(callback: (ByteArray) -> Unit) {
    vadCapability.setAudioBufferCallback(callback)
}

// ============================================================================
// MARK: - Cleanup
// ============================================================================

/**
 * Cleanup VAD resources
 */
suspend fun RunAnywhere.cleanupVAD() {
    vadCapability.cleanup()
}
