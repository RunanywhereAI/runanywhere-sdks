package com.runanywhere.sdk.foundation

import com.runanywhere.sdk.components.stt.STTComponent
import com.runanywhere.sdk.components.stt.STTConfiguration
import com.runanywhere.sdk.components.vad.VADComponent
import com.runanywhere.sdk.components.vad.VADConfiguration
import com.runanywhere.sdk.core.ModuleRegistry
import com.runanywhere.sdk.data.models.ConfigurationData
import com.runanywhere.sdk.data.models.SDKInitParams
import com.runanywhere.sdk.data.repositories.ModelInfoRepository
import com.runanywhere.sdk.data.repositories.ModelInfoRepositoryImpl
import com.runanywhere.sdk.generation.GenerationService
import com.runanywhere.sdk.generation.StreamingService
import com.runanywhere.sdk.models.ModelManager
import com.runanywhere.sdk.network.createHttpClient
import com.runanywhere.sdk.services.AuthenticationService
import com.runanywhere.sdk.services.download.DownloadService
import com.runanywhere.sdk.services.ValidationService
import com.runanywhere.sdk.services.modelinfo.ModelInfoService
import com.runanywhere.sdk.storage.createFileSystem
import com.runanywhere.sdk.storage.createSecureStorage
import com.runanywhere.sdk.storage.FileSystem
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

/**
 * Central service container - Common implementation
 * Platform-specific initialization is handled through expect/actual
 */
class ServiceContainer {

    companion object {
        val shared = ServiceContainer()
    }

    // Platform abstractions
    private val fileSystem by lazy { createFileSystem() }
    private val httpClient by lazy { createHttpClient() }
    private val secureStorage by lazy { createSecureStorage() }

    // Simple in-memory repositories
    val modelInfoRepository: ModelInfoRepository by lazy {
        ModelInfoRepositoryImpl()
    }

    val modelInfoService: ModelInfoService by lazy {
        ModelInfoService(
            modelInfoRepository = modelInfoRepository,
            syncCoordinator = null
        )
    }

    // Components
    val vadComponent: VADComponent by lazy {
        VADComponent(VADConfiguration())
    }

    val sttComponent: STTComponent by lazy {
        STTComponent(STTConfiguration())
    }

    // Services
    val authenticationService: AuthenticationService by lazy {
        AuthenticationService(secureStorage, httpClient)
    }

    val validationService: ValidationService by lazy {
        ValidationService(fileSystem)
    }

    val downloadService: DownloadService by lazy {
        SimpleDownloadService(fileSystem)
    }

    val modelManager: ModelManager by lazy {
        ModelManager(fileSystem, downloadService)
    }

    val generationService: GenerationService by lazy {
        GenerationService()
    }

    val streamingService: StreamingService by lazy {
        StreamingService()
    }

    /**
     * Initialize the service container with platform-specific context
     * This is implemented differently for each platform
     */
    fun initialize(platformContext: PlatformContext) {
        platformContext.initialize()
    }

    /**
     * Bootstrap services for production mode
     */
    suspend fun bootstrap(params: SDKInitParams): ConfigurationData {
        logger.info("Bootstrapping services for production mode")

        // Step 1: Register default modules
        registerDefaultModules()

        // Step 2: Initialize authentication
        authenticationService.initialize(params.apiKey)

        // Step 3: Initialize services
        modelInfoService.initialize()

        // Step 4: Initialize components
        initializeComponents()

        logger.info("Production bootstrap completed successfully")
        return ConfigurationData.default(params.apiKey)
    }

    /**
     * Bootstrap services for development mode with mock data
     */
    suspend fun bootstrapDevelopmentMode(params: SDKInitParams): ConfigurationData {
        logger.info("🧪 DEVELOPMENT MODE: Starting bootstrap process...")
        logger.info("Bootstrapping services for development mode")

        // Step 1: Register default modules (including WhisperKit for development)
        logger.info("🔧 Step 1: Registering default modules...")
        registerDefaultModules()
        logger.info("✅ Step 1 completed")

        // Step 2: Initialize authentication (even in dev mode)
        logger.info("🔧 Step 2: Initializing authentication...")
        authenticationService.initialize(params.apiKey)
        logger.info("✅ Step 2 completed")

        // Step 3: Initialize services
        logger.info("🔧 Step 3: Initializing model info service...")
        modelInfoService.initialize()
        logger.info("✅ Step 3 completed")

        // Step 3a: Populate with mock models in development mode
        logger.info("🚀 About to populate mock models...")
        populateMockModels()
        logger.info("🚀 Mock model population completed")

        // Step 4: Initialize components
        initializeComponents()

        logger.info("Development bootstrap completed successfully")
        return ConfigurationData.default(params.apiKey)
    }

    /**
     * Get component by type
     */
    fun getComponent(component: com.runanywhere.sdk.components.base.SDKComponent): com.runanywhere.sdk.components.base.Component? {
        return when (component) {
            com.runanywhere.sdk.components.base.SDKComponent.STT -> sttComponent
            com.runanywhere.sdk.components.base.SDKComponent.VAD -> vadComponent
            else -> null
        }
    }

    /**
     * Register default modules for SDK operation
     */
    private fun registerDefaultModules() {
        logger.info("Registering default modules")

        // Register WhisperKit provider
        try {
            // Note: WhisperKit registration will be handled by the consuming application
            // since it's an external module dependency
            logger.info("ℹ️ WhisperKit provider should be registered by consuming application")
        } catch (e: Exception) {
            logger.warn("⚠️ WhisperKit provider registration failed: ${e.message}")
        }

        // Register simple energy VAD provider
        try {
            registerSimpleEnergyVADProvider()
            logger.info("✅ Simple Energy VAD provider registered")
        } catch (e: Exception) {
            logger.warn("⚠️ VAD provider registration failed: ${e.message}")
        }

        logger.info("Module registration completed. Registered modules: ${ModuleRegistry.registeredModules}")
    }

    /**
     * Initialize all components
     */
    private suspend fun initializeComponents() {
        logger.info("Initializing SDK components")

        try {
            // Initialize VAD component
            vadComponent.initialize()
            logger.info("✅ VAD component initialized")
        } catch (e: Exception) {
            logger.warn("⚠️ VAD component initialization failed: ${e.message}")
        }

        try {
            // Initialize STT component only if a provider is registered
            if (ModuleRegistry.hasSTT) {
                sttComponent.initialize()
                logger.info("✅ STT component initialized")
            } else {
                logger.info("ℹ️ STT component skipped - no provider registered yet")
            }
        } catch (e: Exception) {
            logger.warn("⚠️ STT component initialization failed: ${e.message}")
        }

        logger.info("Component initialization completed")
    }

    /**
     * Register simple energy VAD provider for development
     */
    private fun registerSimpleEnergyVADProvider() {
        val simpleVADProvider = object : com.runanywhere.sdk.core.VADServiceProvider {
            override suspend fun createVADService(configuration: VADConfiguration): com.runanywhere.sdk.components.vad.VADService {
                return com.runanywhere.sdk.voice.vad.SimpleEnergyVAD(
                    vadConfig = configuration
                )
            }

            override fun canHandle(modelId: String): Boolean = modelId.contains("simple", ignoreCase = true) || modelId.contains("energy", ignoreCase = true)

            override val name: String = "SimpleEnergyVAD"
        }

        ModuleRegistry.registerVAD(simpleVADProvider)
    }

    /**
     * Add logging
     */
    private val logger = SDKLogger("ServiceContainer")

    /**
     * Populate ModelInfoService with ONLY whisper-base model in development mode
     * Hardcoded exactly like iOS MockNetworkService whisper-base model
     */
    private suspend fun populateMockModels() {
        logger.info("🔄 Populating ModelInfoService with whisper-base model for development mode")

        try {
            // Create hardcoded whisper-base model exactly like iOS
            val whisperBaseModel = com.runanywhere.sdk.models.ModelInfo(
                id = "whisper-base",
                name = "Whisper Base",
                category = com.runanywhere.sdk.models.enums.ModelCategory.SPEECH_RECOGNITION,
                format = com.runanywhere.sdk.models.enums.ModelFormat.MLMODEL,
                downloadURL = "https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-base",
                localPath = null,
                downloadSize = 74_000_000L, // 74MB like iOS
                memoryRequired = 74_000_000L, // 74MB like iOS
                compatibleFrameworks = listOf(com.runanywhere.sdk.models.enums.LLMFramework.WHISPER_KIT),
                preferredFramework = com.runanywhere.sdk.models.enums.LLMFramework.WHISPER_KIT,
                contextLength = 0,
                supportsThinking = false,
                createdAt = com.runanywhere.sdk.utils.SimpleInstant.now(),
                updatedAt = com.runanywhere.sdk.utils.SimpleInstant.now()
            )

            logger.info("💾 Saving whisper-base model directly...")
            modelInfoService.saveModel(whisperBaseModel)
            logger.info("✅ Whisper Base model saved successfully!")

            // Verify it's accessible
            val savedWhisperBase = modelInfoService.getModel("whisper-base")
            if (savedWhisperBase != null) {
                logger.info("✅ Whisper Base model verified and retrievable")
                logger.info("🎙️ Whisper Base: ${savedWhisperBase.name} (74MB)")
            } else {
                logger.error("❌ Whisper Base model not found after save!")
            }

            // Check total models
            val allModels = modelInfoService.getAllModels()
            logger.info("🔍 Total models in ModelInfoService: ${allModels.size}")

        } catch (e: Exception) {
            logger.error("❌ Failed to populate whisper-base model: ${e.message}", e)
            e.printStackTrace()
        }
    }

    /**
     * Cleanup all services
     */
    suspend fun cleanup() {
        authenticationService.signOut()
        sttComponent.cleanup()
        vadComponent.cleanup()
    }
}

/**
 * Platform-specific context for initialization
 */
expect class PlatformContext {
    fun initialize()
}

/**
 * Simple DownloadService implementation that uses existing FileSystem
 */
private class SimpleDownloadService(
    private val fileSystem: FileSystem
) : DownloadService {

    override suspend fun downloadModel(
        model: com.runanywhere.sdk.models.ModelInfo,
        progressHandler: ((com.runanywhere.sdk.services.download.DownloadProgress) -> Unit)?
    ): String {
        // For now, return a placeholder path
        val fileName = model.downloadURL?.substringAfterLast("/") ?: "${model.id}.bin"
        return "models/$fileName"
    }

    override fun downloadModelStream(model: com.runanywhere.sdk.models.ModelInfo): Flow<com.runanywhere.sdk.services.download.DownloadProgress> = flow {
        emit(com.runanywhere.sdk.services.download.DownloadProgress(
            bytesDownloaded = 0,
            totalBytes = model.downloadSize ?: 0,
            state = com.runanywhere.sdk.services.download.DownloadState.Pending
        ))
    }

    override fun cancelDownload(modelId: String) {
        // No-op for now
    }

    override fun getActiveDownloads(): List<com.runanywhere.sdk.services.download.DownloadTask> {
        return emptyList()
    }

    override fun isDownloading(modelId: String): Boolean {
        return false
    }

    override suspend fun resumeDownload(modelId: String): String? {
        return null
    }
}
