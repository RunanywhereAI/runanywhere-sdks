package com.runanywhere.sdk.public

import com.runanywhere.sdk.components.stt.STTComponent
import com.runanywhere.sdk.components.stt.STTConfiguration
import com.runanywhere.sdk.components.vad.VADComponent
import com.runanywhere.sdk.components.vad.VADConfiguration
import com.runanywhere.sdk.data.models.ConfigurationData
import com.runanywhere.sdk.data.models.SDKEnvironment
import com.runanywhere.sdk.data.models.SDKInitParams
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.ServiceContainer
import com.runanywhere.sdk.models.ModelDownloader
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.storage.createFileSystem
import kotlinx.coroutines.flow.Flow

/**
 * JVM implementation of RunAnywhere SDK
 * Simplified version using platform abstractions
 */
actual object RunAnywhere : BaseRunAnywhereSDK() {

    private val logger = SDKLogger("RunAnywhere.JVM")
    private lateinit var serviceContainer: ServiceContainer
    private lateinit var modelDownloader: ModelDownloader
    private var sttComponent: STTComponent? = null
    private var vadComponent: VADComponent? = null

    override suspend fun initializePlatform(
        apiKey: String,
        baseURL: String?,
        environment: SDKEnvironment
    ) {
        logger.info("Initializing JVM platform for ${environment.name} environment")

        // Initialize service container
        serviceContainer = ServiceContainer.shared
        serviceContainer.initialize(System.getProperty("user.dir"))

        // Create SDK init params
        val params = SDKInitParams(
            apiKey = apiKey,
            baseURL = baseURL ?: "https://api.runanywhere.com",
            environment = environment
        )

        // Bootstrap services based on environment
        val configurationData: ConfigurationData = when (environment) {
            SDKEnvironment.DEVELOPMENT -> {
                logger.info("Bootstrapping development mode")
                serviceContainer.bootstrapDevelopmentMode(params)
            }
            else -> {
                logger.info("Bootstrapping production mode")
                serviceContainer.bootstrap(params)
            }
        }

        // Initialize ModelDownloader with dependencies
        modelDownloader = ModelDownloader(
            fileSystem = createFileSystem(),
            downloadService = serviceContainer.downloadService
        )

        // Initialize components
        sttComponent = STTComponent(STTConfiguration())
        vadComponent = VADComponent(VADConfiguration())

        sttComponent?.initialize()
        vadComponent?.initialize()

        logger.info("JVM platform initialization complete")
    }

    override suspend fun cleanupPlatform() {
        sttComponent?.cleanup()
        vadComponent?.cleanup()
        serviceContainer.cleanup()
    }

    override suspend fun availableModels(): List<ModelInfo> {
        requireInitialized()
        return serviceContainer.modelInfoService.getAllModels()
    }

    override suspend fun downloadModel(modelId: String): Flow<Float> {
        requireInitialized()

        val model = serviceContainer.modelInfoService.getModel(modelId)
            ?: throw IllegalArgumentException("Model not found: $modelId")

        return modelDownloader.downloadModelWithProgress(model)
    }

    override suspend fun transcribe(audioData: ByteArray): String {
        requireInitialized()

        // Simple transcription without VAD for now
        val result = sttComponent?.transcribe(audioData)
            ?: throw IllegalStateException("STT component not initialized")

        return result.text
    }
}
