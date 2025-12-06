package com.runanywhere.sdk.components.wakeword

import com.runanywhere.sdk.components.base.*
import com.runanywhere.sdk.core.ModuleRegistry
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.utils.getCurrentTimeMillis

// MARK: - Wake Word Component

/**
 * Wake Word Detection component following the clean architecture
 * Matches iOS WakeWordComponent exactly
 */
class WakeWordComponent(configuration: WakeWordConfiguration) :
    BaseComponent<WakeWordServiceWrapper>(configuration) {

    // MARK: - Properties

    override val componentType: SDKComponent = SDKComponent.WAKEWORD

    private val wakeWordConfiguration: WakeWordConfiguration = configuration
    private var isDetecting = false

    // MARK: - Service Creation

    override suspend fun createService(): WakeWordServiceWrapper {
        // Emit model checking event
        eventBus.publish(com.runanywhere.sdk.events.ComponentInitializationEvent.ComponentChecking(
            component = componentType.name,
            modelId = wakeWordConfiguration.modelId
        ))

        // Try to get a registered wake word provider from central registry
        val provider = ModuleRegistry.wakeWordProvider(wakeWordConfiguration.modelId)

        // If no provider registered, use default implementation
        val wakeWordService = if (provider != null) {
            provider.createWakeWordService(wakeWordConfiguration)
        } else {
            // Use default implementation (no detection)
            DefaultWakeWordService()
        }

        // Wrap the service
        return WakeWordServiceWrapper(wakeWordService)
    }

    override suspend fun initializeService() {
        val wakeWordService = service?.wrappedService ?: return

        eventBus.publish(com.runanywhere.sdk.events.ComponentInitializationEvent.ComponentInitializing(
            component = componentType.name,
            modelId = wakeWordConfiguration.modelId
        ))

        wakeWordService.initialize()
    }

    // MARK: - Public API

    /**
     * Start listening for wake words
     */
    suspend fun startListening() {
        ensureReady()

        val wakeWordService = service?.wrappedService
            ?: throw SDKError.ComponentNotReady("Wake word service not available")

        wakeWordService.startListening()
        isDetecting = true
    }

    /**
     * Stop listening for wake words
     */
    suspend fun stopListening() {
        val wakeWordService = service?.wrappedService ?: return

        wakeWordService.stopListening()
        isDetecting = false
    }

    /**
     * Process audio input for wake word detection
     * Matches iOS process(_ input: WakeWordInput) method exactly
     */
    fun process(input: WakeWordInput): WakeWordOutput {
        ensureReady()

        val wakeWordService = service?.wrappedService
            ?: throw SDKError.ComponentNotReady("Wake word service not available")

        // Validate input
        input.validate()

        // Track processing time
        val startTime = getCurrentTimeMillis()

        // Process audio buffer
        val detected = wakeWordService.processAudioBuffer(input.audioBuffer)

        val processingTime = (getCurrentTimeMillis() - startTime) / 1000.0

        // Create output
        return WakeWordOutput(
            detected = detected,
            wakeWord = if (detected) wakeWordConfiguration.wakeWords.firstOrNull() else null,
            confidence = if (detected) wakeWordConfiguration.confidenceThreshold else 0.0f,
            metadata = WakeWordMetadata(
                processingTime = processingTime,
                bufferSize = input.audioBuffer.size,
                sampleRate = wakeWordConfiguration.sampleRate
            )
        )
    }

    /**
     * Process audio buffer for wake word detection (convenience method)
     */
    fun processAudioBuffer(buffer: FloatArray): WakeWordOutput {
        return process(WakeWordInput(audioBuffer = buffer))
    }

    /**
     * Check if currently listening
     * Matches iOS isListening property exactly
     */
    val isListening: Boolean
        get() = service?.wrappedService?.isListening ?: false

    // MARK: - Cleanup

    override suspend fun performCleanup() {
        service?.wrappedService?.cleanup()
        isDetecting = false
    }
}
