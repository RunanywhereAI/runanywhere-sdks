package com.runanywhere.sdk.public

import android.content.Context
import com.runanywhere.sdk.data.models.SDKEnvironment
import com.runanywhere.sdk.data.models.SDKInitParams
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.files.FileManager
import com.runanywhere.sdk.foundation.ServiceContainer
import com.runanywhere.sdk.foundation.SDKLogger
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map

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
        // FileManager is initialized through its companion object
    }

    override suspend fun authenticateWithBackend(params: SDKInitParams) {
        // Skip authentication in development mode
        if (currentEnvironment == SDKEnvironment.DEVELOPMENT) {
            androidLogger.info("Skipping authentication in development mode")
            return
        }

        androidLogger.info("Authenticating with backend API")
        // Authentication is handled by ServiceContainer.bootstrap()
        serviceContainer.authenticationService.authenticate(params.apiKey)
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
        return serviceContainer.modelInfoService.getAllModels()
    }

    override suspend fun downloadModel(modelId: String): Flow<Float> {
        requireInitialized()
        val modelInfo = serviceContainer.modelInfoService.getModel(modelId)
            ?: throw IllegalArgumentException("Model not found: $modelId")

        // Use downloadModelStream which returns a Flow<DownloadProgress>
        return serviceContainer.downloadService.downloadModelStream(modelInfo).map { progress ->
            progress.percentage.toFloat()
        }
    }

    override suspend fun transcribe(audioData: ByteArray): String {
        requireInitialized()

        // Get the STT component from the service container
        val sttComponent = serviceContainer.sttComponent

        // Perform transcription using STTComponent
        val result = sttComponent.transcribe(
            audioData = audioData,
            format = com.runanywhere.sdk.components.stt.AudioFormat.WAV,
            language = "en"
        )

        return result.text
    }

    override suspend fun loadModel(modelId: String): Boolean {
        requireInitialized()

        androidLogger.info("Loading model: $modelId")

        // Check if model is downloaded
        val model = serviceContainer.modelInfoService.getModel(modelId)
            ?: throw IllegalArgumentException("Model not found: $modelId")

        if (model.localPath == null) {
            androidLogger.warn("Model $modelId not downloaded. Download it first.")
            return false
        }

        // Load model into memory using ModelManager
        return try {
            serviceContainer.modelManager.loadModel(model)
            androidLogger.info("Model $modelId loaded successfully")
            true
        } catch (e: Exception) {
            androidLogger.error("Failed to load model $modelId: ${e.message}")
            false
        }
    }

    override suspend fun generate(prompt: String, options: com.runanywhere.sdk.models.RunAnywhereGenerationOptions?): String {
        requireInitialized()

        androidLogger.info("Generating response for prompt: ${prompt.take(50)}...")

        // Convert RunAnywhereGenerationOptions to GenerationOptions
        val generationOptions = com.runanywhere.sdk.generation.GenerationOptions(
            model = null, // Model will be auto-selected
            temperature = options?.temperature ?: 0.7f,
            maxTokens = options?.maxTokens ?: 100,
            stopSequences = options?.stopSequences ?: emptyList()
        )

        // Use generation service from service container
        val result = serviceContainer.generationService.generate(prompt, generationOptions)

        androidLogger.info("Generated response: ${result.text.take(50)}...")
        return result.text
    }

    override fun generateStream(prompt: String, options: com.runanywhere.sdk.models.RunAnywhereGenerationOptions?): Flow<String> {
        requireInitialized()

        androidLogger.info("Starting streaming generation for prompt: ${prompt.take(50)}...")

        // Convert RunAnywhereGenerationOptions to GenerationOptions
        val generationOptions = com.runanywhere.sdk.generation.GenerationOptions(
            model = null, // Model will be auto-selected
            temperature = options?.temperature ?: 0.7f,
            maxTokens = options?.maxTokens ?: 100,
            stopSequences = options?.stopSequences ?: emptyList()
        )

        // Use streaming service from service container
        return serviceContainer.streamingService.stream(prompt, generationOptions)
            .map { chunk -> chunk.text }
    }
}
