package com.runanywhere.sdk.public

import com.runanywhere.sdk.components.stt.STTConfiguration
import com.runanywhere.sdk.components.stt.STTComponent
import com.runanywhere.sdk.components.vad.VADConfiguration
import com.runanywhere.sdk.components.vad.VADComponent
import com.runanywhere.sdk.data.models.*
import com.runanywhere.sdk.foundation.ServiceContainer
import com.runanywhere.sdk.models.ModelInfo
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf

/**
 * JVM implementation of RunAnywhere SDK
 */
actual object RunAnywhere : BaseRunAnywhereSDK() {

    private lateinit var serviceContainer: ServiceContainer
    private var sttComponent: STTComponent? = null
    private var vadComponent: VADComponent? = null

    override suspend fun initializePlatform(
        apiKey: String,
        baseURL: String?,
        environment: SDKEnvironment
    ) {
        // Initialize JVM-specific service container
        serviceContainer = ServiceContainer.shared
        serviceContainer.initialize(System.getProperty("user.dir"))

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
        // Return available models from service
        return serviceContainer.modelInfoService.getAllModels()
    }

    override suspend fun downloadModel(modelId: String): Flow<Float> {
        requireInitialized()
        // Implement model download with progress
        return flowOf(0f, 0.5f, 1.0f)
    }

    override suspend fun transcribe(audioData: ByteArray): String {
        requireInitialized()
        return sttComponent?.transcribe(audioData)?.text
            ?: throw IllegalStateException("STT component not initialized")
    }
}
