package com.runanywhere.sdk.public

import android.content.Context
import com.runanywhere.sdk.components.stt.STTComponent
import com.runanywhere.sdk.components.stt.STTConfiguration
import com.runanywhere.sdk.components.stt.WhisperServiceProvider
import com.runanywhere.sdk.components.vad.VADComponent
import com.runanywhere.sdk.components.vad.VADConfiguration
import com.runanywhere.sdk.components.vad.WebRTCVADServiceProvider
import com.runanywhere.sdk.data.models.*
import com.runanywhere.sdk.events.*
import com.runanywhere.sdk.files.FileManager
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.ServiceContainer
import kotlinx.coroutines.flow.Flow
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Main public API for RunAnywhere SDK
 */
object RunAnywhere {
    private val logger = SDKLogger("RunAnywhere")
    private val _isInitialized = AtomicBoolean(false)
    private var _currentEnvironment: SDKEnvironment = SDKEnvironment.DEVELOPMENT

    val serviceContainer: ServiceContainer get() = ServiceContainer.shared
    val eventBus: EventBus get() = EventBus.shared

    /**
     * Initialize the SDK
     */
    suspend fun initialize(
        context: Context,
        apiKey: String,
        baseURL: String? = null,
        environment: SDKEnvironment = SDKEnvironment.DEVELOPMENT
    ) {
        if (_isInitialized.get()) {
            logger.info("SDK already initialized")
            return
        }

        _currentEnvironment = environment

        // Initialize file manager
        FileManager.initialize(context)

        // Register service providers
        WhisperServiceProvider.register()
        WebRTCVADServiceProvider.register()

        // Emit initialization started event
        eventBus.publish(SDKInitializationEvent.Started)

        try {
            // Initialize services based on environment
            val configData = if (environment == SDKEnvironment.DEVELOPMENT) {
                serviceContainer.bootstrapDevelopmentMode(
                    SDKInitParams(apiKey, baseURL, environment)
                )
            } else {
                // For production, would need proper auth service
                serviceContainer.bootstrapDevelopmentMode(
                    SDKInitParams(apiKey, baseURL, environment)
                )
            }

            _isInitialized.set(true)
            eventBus.publish(SDKInitializationEvent.Completed)

            logger.info("SDK initialized successfully in ${environment.name} mode")

        } catch (e: Exception) {
            logger.error("SDK initialization failed", e)
            eventBus.publish(SDKInitializationEvent.Failed(e))
            throw e
        }
    }

    /**
     * Load a model
     */
    suspend fun loadModel(modelId: String): LoadedModel {
        requireInitialized()

        eventBus.publish(SDKModelEvent.LoadStarted(modelId))

        try {
            val loadedModel = serviceContainer.modelLoadingService.loadModel(modelId)
            eventBus.publish(SDKModelEvent.LoadCompleted(modelId))
            return loadedModel
        } catch (e: Exception) {
            eventBus.publish(SDKModelEvent.LoadFailed(modelId, e))
            throw e
        }
    }

    /**
     * Get available models
     */
    suspend fun availableModels(): List<ModelInfo> {
        requireInitialized()
        return serviceContainer.modelRegistry.discoverModels()
    }

    /**
     * Simple transcription
     */
    suspend fun transcribe(audioData: ByteArray): String {
        requireInitialized()

        eventBus.publish(SDKVoiceEvent.TranscriptionStarted)

        try {
            val sttComponent = serviceContainer.sttComponent

            // Initialize if needed
            if (!sttComponent.isInitialized()) {
                sttComponent.initialize()
            }

            val result = sttComponent.transcribe(audioData)
            eventBus.publish(SDKVoiceEvent.TranscriptionFinal(result.text))

            return result.text

        } catch (e: Exception) {
            eventBus.publish(SDKVoiceEvent.PipelineError(e))
            throw e
        }
    }

    /**
     * Stream transcription
     */
    fun transcribeStream(audioStream: Flow<ByteArray>): Flow<com.runanywhere.sdk.components.stt.TranscriptionEvent> {
        requireInitialized()
        return serviceContainer.sttComponent.transcribeStream(audioStream)
    }

    /**
     * Check if SDK is initialized
     */
    val isInitialized: Boolean
        get() = _isInitialized.get()

    val currentEnvironment: SDKEnvironment
        get() = _currentEnvironment

    /**
     * Cleanup and release resources
     */
    suspend fun cleanup() {
        if (!_isInitialized.get()) return

        serviceContainer.sttComponent.cleanup()
        serviceContainer.vadComponent.cleanup()

        _isInitialized.set(false)
        logger.info("SDK cleaned up")
    }

    private fun requireInitialized() {
        if (!_isInitialized.get()) {
            throw SDKError.NotInitialized
        }
    }
}
