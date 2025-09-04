package com.runanywhere.sdk.public

import android.content.Context
import com.runanywhere.sdk.components.stt.WhisperServiceProvider
import com.runanywhere.sdk.components.vad.WebRTCVADServiceProvider
import com.runanywhere.sdk.data.models.*
import com.runanywhere.sdk.events.*
import com.runanywhere.sdk.files.FileManager
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.ServiceContainer
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf

/**
 * Android implementation of RunAnywhere SDK
 */
actual object RunAnywhere : BaseRunAnywhereSDK() {
    private val logger = SDKLogger("RunAnywhere-Android")
    private lateinit var context: Context

    /**
     * Android-specific initialization with Context
     */
    suspend fun initialize(
        context: Context,
        apiKey: String,
        baseURL: String? = null,
        environment: SDKEnvironment = SDKEnvironment.DEVELOPMENT
    ) {
        this.context = context.applicationContext
        initialize(apiKey, baseURL, environment)
    }

    override suspend fun initializePlatform(
        apiKey: String,
        baseURL: String?,
        environment: SDKEnvironment
    ) {
        if (!::context.isInitialized) {
            throw IllegalStateException("Android context not provided. Use RunAnywhere.initialize(context, ...) on Android")
        }

        logger.info("Initializing Android platform")

        // Initialize service container with context
        ServiceContainer.shared.initialize(context)

        // Initialize file manager
        FileManager.shared.initialize(context)

        // Register service providers
        WhisperServiceProvider.register()
        WebRTCVADServiceProvider.register()

        // Emit initialization events
        EventBus.publish(SDKInitializationEvent.Started)

        try {
            // Initialize services based on environment
            val configData = if (environment == SDKEnvironment.DEVELOPMENT) {
                ServiceContainer.shared.bootstrapDevelopmentMode(
                    SDKInitParams(apiKey, baseURL, environment)
                )
            } else {
                ServiceContainer.shared.bootstrap(
                    SDKInitParams(apiKey, baseURL, environment)
                )
            }

            EventBus.publish(SDKInitializationEvent.Completed)
            logger.info("Android platform initialized successfully")

        } catch (e: Exception) {
            logger.error("Android platform initialization failed", e)
            EventBus.publish(SDKInitializationEvent.Failed(e))
            throw e
        }
    }

    override suspend fun cleanupPlatform() {
        ServiceContainer.shared.cleanup()
        logger.info("Android platform cleaned up")
    }

    override suspend fun availableModels(): List<ModelInfo> {
        requireInitialized()
        return ServiceContainer.shared.modelInfoService.getAllModels()
    }

    override suspend fun downloadModel(modelId: String): Flow<Float> {
        requireInitialized()
        EventBus.publish(SDKModelEvent.LoadStarted(modelId))

        return try {
            val flow = ServiceContainer.shared.modelInfoService.downloadModel(modelId)
            EventBus.publish(SDKModelEvent.LoadCompleted(modelId))
            flow.map { progress -> progress.percentage }
        } catch (e: Exception) {
            EventBus.publish(SDKModelEvent.LoadFailed(modelId, e))
            throw e
        }
    }

    override suspend fun transcribe(audioData: ByteArray): String {
        requireInitialized()
        EventBus.publish(SDKVoiceEvent.TranscriptionStarted)

        try {
            val sttComponent = ServiceContainer.shared.sttComponent

            // Initialize if needed
            if (!sttComponent.isInitialized()) {
                sttComponent.initialize()
            }

            val result = sttComponent.transcribe(audioData)
            EventBus.publish(SDKVoiceEvent.TranscriptionFinal(result.text))

            return result.text

        } catch (e: Exception) {
            EventBus.publish(SDKVoiceEvent.PipelineError(e))
            throw e
        }
    }

    /**
     * Android-specific: Get device information
     */
    suspend fun deviceInfo(): DeviceInfoData {
        requireInitialized()
        return ServiceContainer.shared.deviceInfoService.getCurrentDeviceInfo()
    }

    /**
     * Android-specific: Get current configuration
     */
    suspend fun configuration(): ConfigurationData {
        requireInitialized()
        return ServiceContainer.shared.configurationService.getCurrentConfiguration()
    }
}
