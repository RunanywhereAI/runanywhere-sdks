package com.runanywhere.sdk.public

import com.runanywhere.sdk.components.stt.WhisperServiceProvider
import com.runanywhere.sdk.data.models.*
import com.runanywhere.sdk.events.*
import com.runanywhere.sdk.files.FileManager
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.ServiceContainer
import kotlinx.coroutines.flow.Flow
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Main public API for RunAnywhere SDK - JVM Implementation
 */
object RunAnywhere {
    private val logger = SDKLogger("RunAnywhere")
    private val _isInitialized = AtomicBoolean(false)
    private var _currentEnvironment: SDKEnvironment = SDKEnvironment.DEVELOPMENT

    val serviceContainer: ServiceContainer get() = ServiceContainer.shared
    val eventBus: EventBus get() = EventBus

    /**
     * Initialize the SDK - JVM version without Android Context
     */
    suspend fun initialize(
        apiKey: String,
        baseURL: String? = null,
        environment: SDKEnvironment = SDKEnvironment.DEVELOPMENT,
        workingDirectory: String = System.getProperty("user.dir")
    ) {
        if (_isInitialized.get()) {
            logger.info("SDK already initialized")
            return
        }

        _currentEnvironment = environment

        // Initialize service container (JVM version)
        serviceContainer.initialize(workingDirectory)

        // Initialize file manager (JVM version)
        FileManager.initialize(workingDirectory)

        // Register service providers
        WhisperServiceProvider.register()
        // Note: Using JVM VAD service instead of WebRTC
        // WebRTCVADServiceProvider.register()

        // Emit initialization started event
        eventBus.publish(SDKInitializationEvent.Started)

        try {
            // Initialize services based on environment
            val configData = if (environment == SDKEnvironment.DEVELOPMENT) {
                serviceContainer.bootstrapDevelopmentMode(
                    SDKInitParams(apiKey, baseURL, environment)
                )
            } else {
                serviceContainer.bootstrap(
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
     * Get available models (using new ModelInfoService)
     */
    suspend fun availableModels(): List<ModelInfoData> {
        requireInitialized()
        return serviceContainer.modelInfoService.getAvailableModels()
    }

    /**
     * Simple transcription
     */
    suspend fun transcribe(audioData: ByteArray): String {
        requireInitialized()
        val result = serviceContainer.sttComponent.transcribe(audioData)
        return result.text
    }

    /**
     * Stream transcription
     */
    fun transcribeStream(audioStream: Flow<ByteArray>) = serviceContainer.sttComponent.transcribeStream(audioStream)

    /**
     * Cleanup resources
     */
    suspend fun cleanup() {
        if (!_isInitialized.get()) return

        try {
            serviceContainer.cleanup()
            _isInitialized.set(false)
            logger.info("SDK cleanup completed")
        } catch (e: Exception) {
            logger.error("SDK cleanup failed", e)
            throw e
        }
    }

    private fun requireInitialized() {
        if (!_isInitialized.get()) {
            throw IllegalStateException("SDK not initialized. Call initialize() first.")
        }
    }

    fun isInitialized(): Boolean = _isInitialized.get()
    fun getCurrentEnvironment(): SDKEnvironment = _currentEnvironment
}
