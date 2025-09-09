package com.runanywhere.sdk.public

import com.runanywhere.sdk.components.stt.STTComponent
import com.runanywhere.sdk.components.vad.VADComponent
import com.runanywhere.sdk.data.models.SDKInitParams
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.models.ModelDownloader
import com.runanywhere.sdk.models.ModelInfo
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

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

        // Initialize ServiceContainer with platform context and environment
        val platformContext = com.runanywhere.sdk.foundation.PlatformContext()
        serviceContainer.initialize(platformContext, currentEnvironment)

        jvmLogger.info("ServiceContainer initialized with environment: $currentEnvironment")
    }

    override suspend fun authenticateWithBackend(params: SDKInitParams) {
        jvmLogger.info("Authenticating with backend API")
        // Authentication is handled by ServiceContainer.bootstrap()
        serviceContainer.authenticationService.authenticate(params.apiKey)
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

        // Ensure STT component is initialized
        var sttComponent = serviceContainer.getComponent(com.runanywhere.sdk.components.base.SDKComponent.STT) as? STTComponent

        jvmLogger.info("STT component from service container: ${sttComponent}, state: ${sttComponent?.state}")

        if (sttComponent == null || sttComponent.state != com.runanywhere.sdk.components.base.ComponentState.READY) {
            // Try to initialize STT component if not ready
            jvmLogger.info("STT component not ready (state: ${sttComponent?.state}), attempting initialization...")
            try {
                val containerComponent = serviceContainer.sttComponent
                jvmLogger.info("Container STT component state before init: ${containerComponent.state}")

                containerComponent.initialize()

                jvmLogger.info("Container STT component state after init: ${containerComponent.state}")
                sttComponent = containerComponent

                if (sttComponent.state == com.runanywhere.sdk.components.base.ComponentState.READY) {
                    jvmLogger.info("STT component initialized successfully and is READY")
                } else {
                    jvmLogger.error("STT component initialized but not READY, state: ${sttComponent.state}")
                }
            } catch (e: Exception) {
                jvmLogger.error("Failed to initialize STT component: ${e.message}", e)
                throw IllegalStateException(
                    "STT component could not be initialized: ${e.message}",
                    e
                )
            }
        }

        if (sttComponent.state != com.runanywhere.sdk.components.base.ComponentState.READY) {
            jvmLogger.error("STT component is not in READY state after init attempt: ${sttComponent.state}")
            throw IllegalStateException("STT component is not in READY state: ${sttComponent.state}")
        }

        val result = sttComponent.transcribe(audioData)
        return result.text
    }

    override suspend fun loadModel(modelId: String): Boolean {
        requireInitialized()

        jvmLogger.info("Loading model: $modelId")

        // Check if model is downloaded
        val model = serviceContainer.modelInfoService.getModel(modelId)
            ?: throw IllegalArgumentException("Model not found: $modelId")

        if (model.localPath == null) {
            jvmLogger.warn("Model $modelId not downloaded. Download it first.")
            return false
        }

        // Load model into memory using ModelManager
        return try {
            serviceContainer.modelManager.loadModel(model)
            jvmLogger.info("Model $modelId loaded successfully")
            true
        } catch (e: Exception) {
            jvmLogger.error("Failed to load model $modelId: ${e.message}")
            false
        }
    }

    override suspend fun generate(
        prompt: String,
        options: com.runanywhere.sdk.models.RunAnywhereGenerationOptions?
    ): String {
        requireInitialized()

        jvmLogger.info("Generating response for prompt: ${prompt.take(50)}...")

        // Convert RunAnywhereGenerationOptions to GenerationOptions
        val generationOptions =
            options?.toGenerationOptions() ?: com.runanywhere.sdk.generation.GenerationOptions()

        // Use generation service from service container
        val result = serviceContainer.generationService.generate(prompt, generationOptions)

        jvmLogger.info("Generated response: ${result.text.take(50)}...")
        return result.text
    }

    override fun generateStream(
        prompt: String,
        options: com.runanywhere.sdk.models.RunAnywhereGenerationOptions?
    ): Flow<String> {
        requireInitialized()

        jvmLogger.info("Starting streaming generation for prompt: ${prompt.take(50)}...")

        // Convert RunAnywhereGenerationOptions to GenerationOptions
        val generationOptions =
            options?.toGenerationOptions() ?: com.runanywhere.sdk.generation.GenerationOptions(
            )

        // Use streaming service from service container
        return serviceContainer.streamingService.stream(prompt, generationOptions)
            .map { chunk -> chunk.text }
    }
}
