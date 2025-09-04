package com.runanywhere.sdk.public

import com.runanywhere.sdk.components.stt.STTConfiguration
import com.runanywhere.sdk.components.stt.STTComponent
import com.runanywhere.sdk.components.vad.VADConfiguration
import com.runanywhere.sdk.components.vad.VADComponent
import com.runanywhere.sdk.data.models.*
import com.runanywhere.sdk.foundation.ServiceContainer
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.ModelDownloader
import com.runanywhere.sdk.network.JvmNetworkService
import com.runanywhere.sdk.network.MockNetworkService
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

/**
 * JVM implementation of RunAnywhere SDK
 */
actual object RunAnywhere : BaseRunAnywhereSDK() {

    private lateinit var serviceContainer: ServiceContainer
    private lateinit var networkService: JvmNetworkService
    private lateinit var modelDownloader: ModelDownloader
    private var sttComponent: STTComponent? = null
    private var vadComponent: VADComponent? = null
    private var mockNetworkService: MockNetworkService? = null

    override suspend fun initializePlatform(
        apiKey: String,
        baseURL: String?,
        environment: SDKEnvironment
    ) {
        // Initialize JVM-specific service container
        serviceContainer = ServiceContainer.shared
        serviceContainer.initialize(System.getProperty("user.dir"))

        // Initialize network service
        if (environment == SDKEnvironment.DEVELOPMENT) {
            mockNetworkService = MockNetworkService()
        } else {
            networkService = JvmNetworkService()
            networkService.initialize(apiKey, baseURL)
        }

        // Initialize model downloader
        modelDownloader = ModelDownloader()

        // Initialize components
        sttComponent = STTComponent(STTConfiguration())
        vadComponent = VADComponent(VADConfiguration())

        // Bootstrap services
        val params = SDKInitParams(apiKey, baseURL, environment)
        if (environment == SDKEnvironment.DEVELOPMENT) {
            serviceContainer.bootstrapDevelopmentMode(params)
        } else {
            serviceContainer.bootstrap(params)
        }
    }

    override suspend fun cleanupPlatform() {
        sttComponent?.cleanup()
        vadComponent?.cleanup()
        serviceContainer.cleanup()
    }

    override suspend fun availableModels(): List<ModelInfo> {
        requireInitialized()

        return if (_currentEnvironment == SDKEnvironment.DEVELOPMENT) {
            // Use mock data for development
            mockNetworkService?.fetchModels() ?: emptyList()
        } else {
            // Use real network service for production
            try {
                networkService.fetchModels()
            } catch (e: Exception) {
                // Fallback to service container models
                serviceContainer.modelInfoService.getAllModels()
            }
        }
    }

    override suspend fun downloadModel(modelId: String): Flow<Float> {
        requireInitialized()

        return flow {
            try {
                val models = availableModels()
                val model = models.find { it.id == modelId }
                    ?: throw IllegalArgumentException("Model not found: $modelId")

                // Check if already downloaded
                if (modelDownloader.isModelDownloaded(model)) {
                    emit(1.0f)
                    return@flow
                }

                // Download with progress tracking
                emit(0.0f)

                modelDownloader.downloadModel(model) { progress ->
                    // This will be called from the download service
                    // We can't emit directly here due to suspend context
                }

                emit(1.0f)

            } catch (e: Exception) {
                throw IllegalStateException("Failed to download model $modelId: ${e.message}", e)
            }
        }
    }

    override suspend fun transcribe(audioData: ByteArray): String {
        requireInitialized()
        return sttComponent?.transcribe(audioData)?.text
            ?: throw IllegalStateException("STT component not initialized")
    }

    /**
     * Get model downloader instance for direct access
     */
    fun getModelDownloader(): ModelDownloader {
        requireInitialized()
        return modelDownloader
    }

    /**
     * Get network service instance for direct access
     */
    fun getNetworkService(): JvmNetworkService? {
        requireInitialized()
        return if (_currentEnvironment != SDKEnvironment.DEVELOPMENT) networkService else null
    }
}
