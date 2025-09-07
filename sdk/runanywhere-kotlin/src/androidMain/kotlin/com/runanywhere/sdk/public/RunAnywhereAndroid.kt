package com.runanywhere.sdk.public

import android.content.Context
import com.runanywhere.sdk.data.models.SDKEnvironment
import com.runanywhere.sdk.data.models.SDKInitParams
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.files.FileManager
import com.runanywhere.sdk.foundation.ServiceContainer
import com.runanywhere.sdk.foundation.SDKLogger
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf

/**
 * Android implementation of RunAnywhere SDK
 */
actual object RunAnywhere : BaseRunAnywhereSDK() {

    // Store the Android context
    private var androidContext: Context? = null

    /**
     * Android-specific initialization with Context
     */
    suspend fun initialize(
        context: Context,
        apiKey: String,
        baseURL: String? = null,
        environment: SDKEnvironment = SDKEnvironment.DEVELOPMENT
    ) {
        androidContext = context.applicationContext
        initialize(apiKey, baseURL, environment)
    }

    private val androidLogger = SDKLogger("RunAnywhere.Android")

    override suspend fun storeCredentialsSecurely(params: SDKInitParams) {
        val context = androidContext ?: throw IllegalStateException(
            "Android context not provided. Use RunAnywhere.initialize(context, ...) on Android"
        )

        // Android uses EncryptedSharedPreferences for secure storage
        androidLogger.info("Storing credentials in Android secure storage")

        // Initialize AndroidPlatformContext if not already done
        if (!com.runanywhere.sdk.storage.AndroidPlatformContext.isInitialized()) {
            com.runanywhere.sdk.storage.AndroidPlatformContext.initialize(context)
        }

        // Store API key securely
        val secureStorage = com.runanywhere.sdk.storage.createSecureStorage()
        secureStorage.setSecureString("com.runanywhere.sdk.apiKey", params.apiKey)
    }

    override suspend fun initializeDatabase() {
        val context = androidContext ?: throw IllegalStateException(
            "Android context not provided. Use RunAnywhere.initialize(context, ...) on Android"
        )

        // Android uses Room database
        androidLogger.info("Initializing Room database for Android")
        // Initialize Android-specific services
        val platformContext = com.runanywhere.sdk.foundation.PlatformContext(context)
        ServiceContainer.shared.initialize(platformContext)
        FileManager.initialize(context)
    }

    override suspend fun authenticateWithBackend(params: SDKInitParams) {
        androidLogger.info("Authenticating with backend API")
        // Authentication is handled by ServiceContainer.bootstrap()
        serviceContainer.authenticationService.initialize(params.apiKey)
    }

    override suspend fun performHealthCheck() {
        androidLogger.info("Performing health check")
        // Health check would be implemented here
        // For now, we assume healthy if authentication succeeded
    }

    override suspend fun cleanupPlatform() {
        // Cleanup Android-specific resources
        ServiceContainer.shared.cleanup()
        androidContext = null
    }

    override suspend fun availableModels(): List<ModelInfo> {
        requireInitialized()
        return serviceContainer.modelInfoService.getAvailableModels()
    }

    override suspend fun downloadModel(modelId: String): Flow<Float> {
        requireInitialized()
        val modelInfo = serviceContainer.modelInfoService.getModelInfo(modelId)
            ?: throw IllegalArgumentException("Model not found: $modelId")

        return serviceContainer.downloadService.downloadModel(modelInfo)
    }

    override suspend fun transcribe(audioData: ByteArray): String {
        requireInitialized()

        // Get the STT component from the service container
        val sttComponent = serviceContainer.sttComponent

        // Create STT options with default values
        val options = com.runanywhere.sdk.components.stt.STTOptions(
            language = "en",
            enableTimestamps = false,
            translateToEnglish = false
        )

        // Perform transcription
        val result = sttComponent.transcribe(audioData, options)

        return result.transcript
    }
}
