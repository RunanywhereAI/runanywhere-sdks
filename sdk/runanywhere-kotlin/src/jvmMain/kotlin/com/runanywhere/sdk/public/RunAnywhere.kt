package com.runanywhere.sdk.public

import com.runanywhere.sdk.components.stt.STTConfiguration
import com.runanywhere.sdk.components.stt.STTComponent
import com.runanywhere.sdk.components.vad.VADConfiguration
import com.runanywhere.sdk.components.vad.VADComponent
import com.runanywhere.sdk.data.models.*
import com.runanywhere.sdk.events.EventBus
import com.runanywhere.sdk.events.SDKInitializationEvent
import com.runanywhere.sdk.events.SDKModelEvent
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.ServiceContainer
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.ModelDownloader
import com.runanywhere.sdk.models.ModelLoadingService
import com.runanywhere.sdk.models.enums.ModelCategory
import com.runanywhere.sdk.network.JvmNetworkService
import com.runanywhere.sdk.network.MockNetworkService
import com.runanywhere.sdk.storage.DatabaseManager
import com.runanywhere.sdk.storage.KeychainManager
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.launch

/**
 * JVM implementation of RunAnywhere SDK
 */
actual object RunAnywhere : BaseRunAnywhereSDK() {

    private val logger = SDKLogger("RunAnywhere.JVM")
    private lateinit var serviceContainer: ServiceContainer
    private lateinit var networkService: JvmNetworkService
    private lateinit var modelDownloader: ModelDownloader
    private lateinit var modelLoadingService: ModelLoadingService
    private lateinit var eventBus: EventBus
    private var sttComponent: STTComponent? = null
    private var vadComponent: VADComponent? = null
    private var mockNetworkService: MockNetworkService? = null
    private var configurationData: ConfigurationData? = null
    private var loadedModel: LoadedModel? = null
    private var sttModel: ModelInfo? = null

    override suspend fun initializePlatform(
        apiKey: String,
        baseURL: String?,
        environment: SDKEnvironment
    ) {
        // Initialize event bus first
        eventBus = EventBus
        eventBus.publish(SDKInitializationEvent.Started)

        try {
            // Step 1: Validate API key (skip in development)
            if (environment != SDKEnvironment.DEVELOPMENT) {
                logger.info("Step 1/8: Validating API key")
                if (apiKey.isEmpty()) {
                    throw IllegalArgumentException("API key cannot be empty")
                }
            } else {
                logger.info("Step 1/8: Skipping API key validation in development mode")
            }

            // Step 2: Initialize logging system
            logger.info("Step 2/8: Initializing logging system")
            SDKLogger.setLogLevel(environment.defaultLogLevel)

            // Step 3: Store credentials securely
            logger.info("Step 3/8: Storing credentials securely")
            if (environment != SDKEnvironment.DEVELOPMENT) {
                KeychainManager.storeAPIKey(apiKey)
            }

            // Step 4: Initialize database
            logger.info("Step 4/8: Initializing local database")
            DatabaseManager.initialize()

            // Initialize JVM-specific service container
            serviceContainer = ServiceContainer.shared
            serviceContainer.initialize(System.getProperty("user.dir"))

            if (environment == SDKEnvironment.DEVELOPMENT) {
                logger.info("🚀 Running in DEVELOPMENT mode - using local/mock services")
                logger.info("Step 5/8: Skipping API authentication in development mode")
                logger.info("Step 6/8: Skipping health check in development mode")
                logger.info("Step 7/8: Bootstrapping SDK services with local data")

                // Initialize mock network service
                mockNetworkService = MockNetworkService()

                // Bootstrap development mode
                val params = SDKInitParams(apiKey, baseURL, environment)
                configurationData = serviceContainer.bootstrapDevelopmentMode(params)

            } else {
                // Production/Staging mode
                logger.info("Step 5/8: Authenticating with backend")

                // Initialize real network service
                networkService = JvmNetworkService()
                networkService.initialize(apiKey, baseURL ?: environment.defaultBaseURL)

                // Fetch configuration from API
                logger.info("Step 6/8: Fetching configuration")
                configurationData = networkService.fetchConfiguration()

                // Perform device info call (similar to health check)
                logger.info("Step 7/8: Sending device info")
                val deviceInfo = getDeviceInfo()
                // networkService.reportDeviceInfo(deviceInfo) // TODO: Implement if needed

                // Bootstrap services
                val params = SDKInitParams(apiKey, baseURL, environment)
                serviceContainer.bootstrap(params)
            }

            // Step 8: Initialize core components
            logger.info("Step 8/8: Initializing core components")

            // Initialize model services
            modelDownloader = ModelDownloader()
            val modelRegistry = com.runanywhere.sdk.models.ModelRegistry()
            val downloadService = com.runanywhere.sdk.services.DownloadService()
            modelLoadingService = ModelLoadingService(modelRegistry, downloadService)

            // Initialize STT and VAD components
            sttComponent = STTComponent(STTConfiguration())
            vadComponent = VADComponent(VADConfiguration())

            // Auto-load default STT model if available
            val models = fetchAvailableModels()
            val defaultSTTModel = models.find {
                it.category == ModelCategory.SPEECH_RECOGNITION &&
                it.id == "whisper-tiny"
            }

            if (defaultSTTModel != null) {
                logger.info("Loading default STT model: ${defaultSTTModel.id}")
                loadSTTModel(defaultSTTModel)
            }

            logger.info("✅ SDK initialization completed successfully")
            eventBus.publish(SDKInitializationEvent.Completed)

        } catch (e: Exception) {
            logger.error("❌ SDK initialization failed: ${e.message}", e)
            eventBus.publish(SDKInitializationEvent.Failed(e))
            throw e
        }
    }

    override suspend fun cleanupPlatform() {
        sttComponent?.cleanup()
        vadComponent?.cleanup()
        serviceContainer.cleanup()
    }

    override suspend fun availableModels(): List<ModelInfo> {
        requireInitialized()
        return fetchAvailableModels()
    }

    private suspend fun fetchAvailableModels(): List<ModelInfo> {
        return if (_currentEnvironment == SDKEnvironment.DEVELOPMENT) {
            // Use mock data for development
            mockNetworkService?.fetchModels() ?: emptyList()
        } else {
            // Use real network service for production
            try {
                networkService.fetchModels()
            } catch (e: Exception) {
                logger.warn("Failed to fetch models from API, using local models")
                // Fallback to service container models
                serviceContainer.modelInfoService.getAllModels()
            }
        }
    }

    override suspend fun downloadModel(modelId: String): Flow<Float> {
        requireInitialized()

        val models = availableModels()
        val model = models.find { it.id == modelId }
            ?: throw IllegalArgumentException("Model not found: $modelId")

        // Publish download started event
        eventBus.publish(SDKModelEvent.DownloadStarted(modelId))

        return modelDownloader.downloadModelWithProgress(model).also {
            // Handle completion
            GlobalScope.launch {
                try {
                    var lastProgress = 0f
                    it.collect { progress ->
                        lastProgress = progress
                        if (progress >= 1.0f) {
                            eventBus.publish(SDKModelEvent.DownloadCompleted(modelId))
                            // Auto-load if it's an STT model
                            if (model.category == ModelCategory.SPEECH_RECOGNITION) {
                                loadSTTModel(model)
                            }
                        }
                    }
                } catch (e: Exception) {
                    eventBus.publish(SDKModelEvent.DownloadFailed(modelId, e))
                }
            }
        }
    }

    override suspend fun transcribe(audioData: ByteArray): String {
        requireInitialized()

        // Ensure STT model is loaded
        if (sttModel == null) {
            throw IllegalStateException("No STT model loaded. Please download and load an STT model first.")
        }

        // Apply VAD if configured
        val processedAudio = if (vadComponent?.isEnabled() == true) {
            vadComponent!!.processAudio(audioData)
        } else {
            audioData
        }

        // Transcribe
        return sttComponent?.transcribe(processedAudio)?.text
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

    /**
     * Load an STT model into memory
     */
    suspend fun loadSTTModel(model: ModelInfo) {
        requireInitialized()

        eventBus.publish(SDKModelEvent.LoadStarted(model.id))

        try {
            // Ensure model is downloaded
            if (!modelDownloader.isModelDownloaded(model)) {
                logger.info("Model ${model.id} not downloaded, downloading now...")
                downloadModel(model.id).collect { progress ->
                    logger.debug("Download progress: ${(progress * 100).toInt()}%")
                }
            }

            // Get local path
            val localPath = modelDownloader.getModelPath(model)

            // Load into STT component
            sttComponent?.loadModel(localPath)

            // Keep reference
            sttModel = model
            loadedModel = LoadedModel(model, localPath, System.currentTimeMillis())

            // Keep pipeline warm with VAD
            vadComponent?.enable()

            logger.info("STT model ${model.id} loaded successfully")
            eventBus.publish(SDKModelEvent.LoadCompleted(model.id))

        } catch (e: Exception) {
            logger.error("Failed to load STT model ${model.id}", e)
            eventBus.publish(SDKModelEvent.LoadFailed(model.id, e))
            throw e
        }
    }

    /**
     * Get currently loaded STT model
     */
    fun getLoadedSTTModel(): ModelInfo? {
        return sttModel
    }

    /**
     * Check if STT pipeline is ready
     */
    fun isSTTPipelineReady(): Boolean {
        return _isInitialized && sttModel != null && sttComponent != null
    }

    /**
     * Get device information for telemetry
     */
    private fun getDeviceInfo(): Map<String, Any> {
        return mapOf(
            "platform" to "JVM",
            "java_version" to System.getProperty("java.version"),
            "os_name" to System.getProperty("os.name"),
            "os_version" to System.getProperty("os.version"),
            "os_arch" to System.getProperty("os.arch"),
            "available_processors" to Runtime.getRuntime().availableProcessors(),
            "max_memory" to Runtime.getRuntime().maxMemory(),
            "total_memory" to Runtime.getRuntime().totalMemory()
        )
    }
}
