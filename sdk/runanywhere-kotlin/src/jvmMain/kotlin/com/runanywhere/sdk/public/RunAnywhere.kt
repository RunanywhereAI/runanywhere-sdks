package com.runanywhere.sdk.public

import com.runanywhere.sdk.components.stt.STTComponent
import com.runanywhere.sdk.components.stt.STTConfiguration
import com.runanywhere.sdk.components.vad.VADComponent
import com.runanywhere.sdk.components.vad.VADConfiguration
import com.runanywhere.sdk.data.models.ConfigurationData
import com.runanywhere.sdk.data.models.SDKEnvironment
import com.runanywhere.sdk.data.models.SDKInitParams
import com.runanywhere.sdk.foundation.PlatformContext
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

    private val jvmLogger = SDKLogger("RunAnywhere.JVM")
    private lateinit var modelDownloader: ModelDownloader
    private var sttComponent: STTComponent? = null
    private var vadComponent: VADComponent? = null

    override suspend fun storeCredentialsSecurely(params: SDKInitParams) {
        // JVM uses file-based storage with encryption
        // For now, credentials are kept in memory in ServiceContainer
        jvmLogger.info("Storing credentials in memory (JVM)")
    }

    override suspend fun initializeDatabase() {
        // JVM uses file-based database
        jvmLogger.info("Initializing file-based database for JVM")
        // Database initialization is handled by ServiceContainer
    }

    override suspend fun authenticateWithBackend(params: SDKInitParams) {
        jvmLogger.info("Authenticating with backend API")
        // Authentication is handled by ServiceContainer.bootstrap()
        serviceContainer.authenticationService.initialize(params.apiKey)
    }

    override suspend fun performHealthCheck() {
        jvmLogger.info("Performing health check")
        // Health check would be implemented here
        // For now, we assume healthy if authentication succeeded
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
