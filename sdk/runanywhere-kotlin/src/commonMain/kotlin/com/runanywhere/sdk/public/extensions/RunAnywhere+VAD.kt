package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.features.vad.SpeechActivityEvent
import com.runanywhere.sdk.features.vad.VADCapabilityConfiguration
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

    val capability =
        vadCapability
            ?: throw SDKError.ComponentNotInitialized("VAD capability not available")

    capability.initialize()
}

/**
 * Initialize VAD with configuration
 *
 * @param config VAD configuration
 * @throws SDKError if SDK is not initialized
 */
suspend fun RunAnywhere.initializeVAD(config: VADCapabilityConfiguration) {
    requireInitialized()

    val capability =
        vadCapability
            ?: throw SDKError.ComponentNotInitialized("VAD capability not available")

    capability.initialize(config.toComponentConfiguration())
}

/**
 * Check if VAD is ready
 */
val RunAnywhere.isVADReady: Boolean
    get() = vadCapability?.isReady ?: false

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

    val capability =
        vadCapability
            ?: throw SDKError.ComponentNotInitialized("VAD capability not available")

    return capability.detectSpeech(samples)
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

    val capability =
        vadCapability
            ?: throw SDKError.ComponentNotInitialized("VAD capability not available")

    return capability.detectSpeech(samples, energyThresholdOverride)
}

/**
 * Stream VAD detection
 *
 * @param audioStream Flow of audio samples
 * @return Flow of VADOutput with detection results
 */
fun RunAnywhere.streamDetectSpeech(audioStream: Flow<FloatArray>): Flow<VADOutput> {
    requireInitialized()

    val capability =
        vadCapability
            ?: throw SDKError.ComponentNotInitialized("VAD capability not available")

    return capability.streamDetectSpeech(audioStream)
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

    val capability =
        vadCapability
            ?: throw SDKError.ComponentNotInitialized("VAD capability not available")

    return capability.detectSpeechSegments(audioStream, onSpeechStart, onSpeechEnd)
}

// ============================================================================
// MARK: - Control
// ============================================================================

/**
 * Start VAD processing
 */
fun RunAnywhere.startVAD() {
    vadCapability?.start()
}

/**
 * Stop VAD processing
 */
fun RunAnywhere.stopVAD() {
    vadCapability?.stop()
}

/**
 * Reset VAD state
 */
fun RunAnywhere.resetVAD() {
    vadCapability?.reset()
}

// ============================================================================
// MARK: - Configuration
// ============================================================================

/**
 * Set VAD energy threshold
 *
 * @param threshold Energy threshold (0.0 to 1.0)
 */
fun RunAnywhere.setVADEnergyThreshold(threshold: Float) {
    vadCapability?.setEnergyThreshold(threshold)
}

/**
 * Set VAD speech activity callback
 *
 * @param callback Callback invoked when speech state changes
 */
fun RunAnywhere.setVADSpeechActivityCallback(callback: (SpeechActivityEvent) -> Unit) {
    vadCapability?.setSpeechActivityCallback(callback)
}

/**
 * Get current VAD energy threshold
 */
val RunAnywhere.vadEnergyThreshold: Float
    get() = vadCapability?.energyThreshold ?: 0.0f

/**
 * Check if speech is currently active
 */
val RunAnywhere.isVADSpeechActive: Boolean
    get() = vadCapability?.isSpeechActive ?: false

// ============================================================================
// MARK: - Cleanup
// ============================================================================

/**
 * Cleanup VAD resources
 */
suspend fun RunAnywhere.cleanupVAD() {
    vadCapability?.cleanup()
}
