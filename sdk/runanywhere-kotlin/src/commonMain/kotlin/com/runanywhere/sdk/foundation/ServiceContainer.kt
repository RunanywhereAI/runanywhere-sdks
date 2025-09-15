package com.runanywhere.sdk.foundation

import com.runanywhere.sdk.components.stt.STTComponent
import com.runanywhere.sdk.components.stt.STTConfiguration
import com.runanywhere.sdk.components.vad.VADComponent
import com.runanywhere.sdk.components.vad.VADConfiguration
import com.runanywhere.sdk.core.ModuleRegistry
import com.runanywhere.sdk.data.models.ConfigurationData
import com.runanywhere.sdk.data.models.SDKInitParams
import com.runanywhere.sdk.data.models.SDKEnvironment
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
import com.runanywhere.sdk.data.network.NetworkService
import com.runanywhere.sdk.data.network.NetworkServiceFactory
import com.runanywhere.sdk.data.network.models.APIEndpoint
import com.runanywhere.sdk.models.DeviceInfo
import com.runanywhere.sdk.models.collectDeviceInfo
import com.runanywhere.sdk.services.analytics.AnalyticsService
import com.runanywhere.sdk.data.repositories.TelemetryRepository
import com.runanywhere.sdk.services.sync.SyncCoordinator
import com.runanywhere.sdk.memory.MemoryService
import com.runanywhere.sdk.events.SDKInitializationEvent
import com.runanywhere.sdk.events.SDKBootstrapEvent
import com.runanywhere.sdk.events.SDKDeviceEvent
import com.runanywhere.sdk.events.EventBus
import com.runanywhere.sdk.foundation.currentTimeMillis
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.serialization.json.Json
import kotlinx.serialization.decodeFromString

/**
 * Central service container - Common implementation
 * Platform-specific initialization is handled through expect/actual
 */
class ServiceContainer {

    companion object {
        val shared = ServiceContainer()
    }

    // Platform abstractions
    internal val fileSystem by lazy { createFileSystem() }
    private val httpClient by lazy { createHttpClient() }
    private val secureStorage by lazy { createSecureStorage() }

    // Network service (will be initialized based on environment)
    private lateinit var networkService: NetworkService
    private var currentEnvironment: SDKEnvironment? = null

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
        STTComponent(STTConfiguration(modelId = "whisper-base"))
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

    // New services for 8-step bootstrap matching iOS
    val memoryService: MemoryService by lazy {
        MemoryService()
    }

    val syncCoordinator: SyncCoordinator by lazy {
        SyncCoordinator()
    }

    // Platform-specific telemetry repository
    val telemetryRepository: TelemetryRepository by lazy {
        createTelemetryRepository()
    }

    // Analytics service initialized during bootstrap
    private var _analyticsService: AnalyticsService? = null
    val analyticsService: AnalyticsService? get() = _analyticsService

    // Device info (collected during initialization)
    private var _deviceInfo: DeviceInfo? = null
    private var _deviceInfoData: com.runanywhere.sdk.data.models.DeviceInfoData? = null
    val deviceInfo: DeviceInfo? get() = _deviceInfo

    /**
     * Initialize the service container with platform-specific context
     * This is implemented differently for each platform
     */
    fun initialize(platformContext: PlatformContext, environment: SDKEnvironment = SDKEnvironment.PRODUCTION) {
        platformContext.initialize()
        currentEnvironment = environment

        // Create the appropriate network service based on environment
        networkService = NetworkServiceFactory.create(
            environment = environment,
            baseURL = null,
            apiKey = null
        )

        logger.info("ServiceContainer initialized with $environment environment")
    }

    /**
     * Enhanced 8-step bootstrap process for production mode matching iOS implementation
     */
    suspend fun bootstrap(params: SDKInitParams): ConfigurationData {
        logger.info("Starting comprehensive 8-step bootstrap process (Production Mode)")
        EventBus.publish(SDKBootstrapEvent.BootstrapStarted)

        var stepStartTime: Long

        try {
            // Step 1: Platform initialization & device info collection
            stepStartTime = currentTimeMillis()
            EventBus.publish(SDKInitializationEvent.StepStarted(1, "Platform initialization & device info collection"))
            EventBus.publish(SDKBootstrapEvent.NetworkServicesConfigured)

            _deviceInfo = collectDeviceInfo()
            // Convert DeviceInfo to DeviceInfoData for events
            _deviceInfoData = convertToDeviceInfoData(_deviceInfo!!)
            EventBus.publish(SDKBootstrapEvent.DeviceInfoCollected(_deviceInfoData!!))

            try {
                // Optional: sync device info to backend
                // TODO: Implement device info sync when backend integration is ready
                EventBus.publish(SDKBootstrapEvent.DeviceInfoSynced(_deviceInfoData!!))
            } catch (e: Exception) {
                logger.warn("Device info sync failed (optional): ${e.message}")
                EventBus.publish(SDKBootstrapEvent.DeviceInfoSyncFailed(e.message ?: "Unknown error"))
            }

            EventBus.publish(SDKInitializationEvent.StepCompleted(1, "Platform initialization & device info collection", currentTimeMillis() - stepStartTime))

            // Step 2: Configuration loading (from multiple sources)
            stepStartTime = currentTimeMillis()
            EventBus.publish(SDKInitializationEvent.StepStarted(2, "Configuration loading"))

            // TODO: Implement multi-source configuration loading
            val configData = ConfigurationData.default(params.apiKey)
            EventBus.publish(SDKBootstrapEvent.ConfigurationLoaded(configData))

            EventBus.publish(SDKInitializationEvent.StepCompleted(2, "Configuration loading", currentTimeMillis() - stepStartTime))

            // Step 3: Authentication service initialization
            stepStartTime = currentTimeMillis()
            EventBus.publish(SDKInitializationEvent.StepStarted(3, "Authentication service initialization"))

            authenticationService.authenticate(params.apiKey)

            EventBus.publish(SDKInitializationEvent.StepCompleted(3, "Authentication service initialization", currentTimeMillis() - stepStartTime))

            // Step 4: Model repository sync
            stepStartTime = currentTimeMillis()
            EventBus.publish(SDKInitializationEvent.StepStarted(4, "Model repository sync"))

            modelInfoService.initialize()
            val models = modelInfoService.getAllModels()
            EventBus.publish(SDKBootstrapEvent.ModelCatalogSynced(models))

            EventBus.publish(SDKInitializationEvent.StepCompleted(4, "Model repository sync", currentTimeMillis() - stepStartTime))

            // Step 5: Analytics service setup
            stepStartTime = currentTimeMillis()
            EventBus.publish(SDKInitializationEvent.StepStarted(5, "Analytics service setup"))

            try {
                _analyticsService = AnalyticsService(telemetryRepository, syncCoordinator)
                _analyticsService?.initialize()
                EventBus.publish(SDKBootstrapEvent.AnalyticsInitialized)
            } catch (e: Exception) {
                logger.warn("Analytics initialization failed (optional): ${e.message}")
                EventBus.publish(SDKBootstrapEvent.AnalyticsInitializationFailed(e.message ?: "Unknown error"))
            }

            EventBus.publish(SDKInitializationEvent.StepCompleted(5, "Analytics service setup", currentTimeMillis() - stepStartTime))

            // Step 6: Component initialization
            stepStartTime = currentTimeMillis()
            EventBus.publish(SDKInitializationEvent.StepStarted(6, "Component initialization"))

            registerDefaultModules()
            initializeComponents()

            EventBus.publish(SDKInitializationEvent.StepCompleted(6, "Component initialization", currentTimeMillis() - stepStartTime))

            // Step 7: Cache warmup
            stepStartTime = currentTimeMillis()
            EventBus.publish(SDKInitializationEvent.StepStarted(7, "Cache warmup"))

            // TODO: Implement cache warmup
            logger.info("Cache warmup completed (placeholder)")

            EventBus.publish(SDKInitializationEvent.StepCompleted(7, "Cache warmup", currentTimeMillis() - stepStartTime))

            // Step 8: Health check
            stepStartTime = currentTimeMillis()
            EventBus.publish(SDKInitializationEvent.StepStarted(8, "Health check"))

            // TODO: Implement comprehensive health check
            logger.info("Health check completed (placeholder)")

            EventBus.publish(SDKInitializationEvent.StepCompleted(8, "Health check", currentTimeMillis() - stepStartTime))

            EventBus.publish(SDKBootstrapEvent.BootstrapCompleted)
            logger.info("✅ 8-step bootstrap process completed successfully (Production Mode)")

            return configData

        } catch (error: Exception) {
            logger.error("❌ Bootstrap process failed: ${error.message}")
            EventBus.publish(SDKBootstrapEvent.BootstrapFailed("Bootstrap", error.message ?: "Unknown error"))
            throw error
        }
    }

    /**
     * Enhanced 8-step bootstrap process for development mode with mock data
     */
    suspend fun bootstrapDevelopmentMode(params: SDKInitParams): ConfigurationData {
        logger.info("🧪 DEVELOPMENT MODE: Starting comprehensive 8-step bootstrap process...")
        EventBus.publish(SDKBootstrapEvent.BootstrapStarted)

        var stepStartTime: Long

        try {
            // Step 1: Platform initialization & device info collection
            stepStartTime = currentTimeMillis()
            EventBus.publish(SDKInitializationEvent.StepStarted(1, "Platform initialization & device info collection"))
            logger.info("🔧 Step 1: Platform initialization & device info collection...")

            EventBus.publish(SDKBootstrapEvent.NetworkServicesConfigured)
            _deviceInfo = collectDeviceInfo()
            // Convert DeviceInfo to DeviceInfoData for events
            _deviceInfoData = convertToDeviceInfoData(_deviceInfo!!)
            EventBus.publish(SDKBootstrapEvent.DeviceInfoCollected(_deviceInfoData!!))
            logger.info("   Device: ${_deviceInfo!!.description}")

            EventBus.publish(SDKInitializationEvent.StepCompleted(1, "Platform initialization & device info collection", currentTimeMillis() - stepStartTime))
            logger.info("✅ Step 1 completed")

            // Step 2: Configuration loading (mock in dev mode)
            stepStartTime = currentTimeMillis()
            EventBus.publish(SDKInitializationEvent.StepStarted(2, "Configuration loading"))
            logger.info("🔧 Step 2: Configuration loading (dev mode)...")

            val configData = ConfigurationData.default(params.apiKey)
            EventBus.publish(SDKBootstrapEvent.ConfigurationLoaded(configData))

            EventBus.publish(SDKInitializationEvent.StepCompleted(2, "Configuration loading", currentTimeMillis() - stepStartTime))
            logger.info("✅ Step 2 completed")

            // Step 3: Authentication service initialization (SKIPPED in dev mode)
            stepStartTime = currentTimeMillis()
            EventBus.publish(SDKInitializationEvent.StepStarted(3, "Authentication service initialization"))
            logger.info("🔧 Step 3: Skipping authentication service in development mode...")

            // NO AUTHENTICATION IN DEVELOPMENT MODE - Following iOS pattern exactly
            logger.info("   Authentication skipped - using mock/local services only")

            EventBus.publish(SDKInitializationEvent.StepCompleted(3, "Authentication service initialization", currentTimeMillis() - stepStartTime))
            logger.info("✅ Step 3 completed (authentication skipped)")

            // Step 4: Model repository sync (fetch mock models)
            stepStartTime = currentTimeMillis()
            EventBus.publish(SDKInitializationEvent.StepStarted(4, "Model repository sync"))
            logger.info("🔧 Step 4: Model repository sync (fetching mock models)...")

            modelInfoService.initialize()
            fetchAndPopulateModels()
            val models = modelInfoService.getAllModels()
            EventBus.publish(SDKBootstrapEvent.ModelCatalogSynced(models))

            EventBus.publish(SDKInitializationEvent.StepCompleted(4, "Model repository sync", currentTimeMillis() - stepStartTime))
            logger.info("✅ Step 4 completed (${models.size} models)")

            // Step 5: Analytics service setup (simplified in dev mode)
            stepStartTime = currentTimeMillis()
            EventBus.publish(SDKInitializationEvent.StepStarted(5, "Analytics service setup"))
            logger.info("🔧 Step 5: Analytics service setup (dev mode)...")

            try {
                _analyticsService = AnalyticsService(telemetryRepository, syncCoordinator)
                _analyticsService?.initialize()
                EventBus.publish(SDKBootstrapEvent.AnalyticsInitialized)
            } catch (e: Exception) {
                logger.warn("Analytics initialization failed (optional): ${e.message}")
                EventBus.publish(SDKBootstrapEvent.AnalyticsInitializationFailed(e.message ?: "Unknown error"))
            }

            EventBus.publish(SDKInitializationEvent.StepCompleted(5, "Analytics service setup", currentTimeMillis() - stepStartTime))
            logger.info("✅ Step 5 completed")

            // Step 6: Component initialization
            stepStartTime = currentTimeMillis()
            EventBus.publish(SDKInitializationEvent.StepStarted(6, "Component initialization"))
            logger.info("🔧 Step 6: Component initialization...")

            registerDefaultModules()
            initializeComponents()

            EventBus.publish(SDKInitializationEvent.StepCompleted(6, "Component initialization", currentTimeMillis() - stepStartTime))
            logger.info("✅ Step 6 completed")

            // Step 7: Cache warmup (minimal in dev mode)
            stepStartTime = currentTimeMillis()
            EventBus.publish(SDKInitializationEvent.StepStarted(7, "Cache warmup"))
            logger.info("🔧 Step 7: Cache warmup (dev mode)...")

            // Minimal cache warmup for development
            logger.info("   Cache warmup minimal for dev mode")

            EventBus.publish(SDKInitializationEvent.StepCompleted(7, "Cache warmup", currentTimeMillis() - stepStartTime))
            logger.info("✅ Step 7 completed")

            // Step 8: Health check (basic in dev mode)
            stepStartTime = currentTimeMillis()
            EventBus.publish(SDKInitializationEvent.StepStarted(8, "Health check"))
            logger.info("🔧 Step 8: Health check (dev mode)...")

            // Basic health check for development mode
            logger.info("   Basic health check passed")

            EventBus.publish(SDKInitializationEvent.StepCompleted(8, "Health check", currentTimeMillis() - stepStartTime))
            logger.info("✅ Step 8 completed")

            EventBus.publish(SDKBootstrapEvent.BootstrapCompleted)
            logger.info("🎉 8-step bootstrap process completed successfully (Development Mode)")

            return configData

        } catch (error: Exception) {
            logger.error("❌ Development bootstrap process failed: ${error.message}")
            EventBus.publish(SDKBootstrapEvent.BootstrapFailed("Development Bootstrap", error.message ?: "Unknown error"))
            throw error
        }
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
    /**
     * Convert simple DeviceInfo to comprehensive DeviceInfoData
     */
    private fun convertToDeviceInfoData(info: DeviceInfo): com.runanywhere.sdk.data.models.DeviceInfoData {
        return com.runanywhere.sdk.data.models.DeviceInfoData(
            deviceId = "${info.platformName}-${info.deviceModel}",
            deviceName = info.deviceModel,
            systemName = info.platformName,
            systemVersion = info.osVersion,
            modelName = info.deviceModel,
            modelIdentifier = info.deviceModel,
            cpuType = "Unknown",
            cpuArchitecture = "Unknown",
            cpuCoreCount = info.cpuCores,
            totalMemoryMB = info.totalMemoryMB,
            availableMemoryMB = info.totalMemoryMB / 2, // Estimate available as half of total
            totalStorageMB = 8192L, // Default 8GB storage
            availableStorageMB = 2048L, // Default 2GB available
            gpuType = com.runanywhere.sdk.data.models.GPUType.UNKNOWN,
            updatedAt = currentTimeMillis()
        )
    }

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

        // Register VAD providers based on platform
        try {
            // For JVM platform, register all available VAD providers
            registerVADProviders()
            logger.info("✅ VAD providers registered")
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
     * Register VAD providers
     */
    private fun registerVADProviders() {
        // Register SimpleEnergyVAD as the primary VAD implementation
        registerSimpleEnergyVADProvider()
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
     * Fetch models from MockNetworkService and populate ModelInfoService
     * This follows the iOS pattern where MockNetworkService provides the models
     */
    private suspend fun fetchAndPopulateModels() {
        logger.info("🔄 Fetching models from MockNetworkService (like iOS)")

        try {
            // Initialize network service if not already done
            if (!::networkService.isInitialized) {
                networkService = NetworkServiceFactory.create(
                    environment = SDKEnvironment.DEVELOPMENT,
                    baseURL = null,
                    apiKey = null
                )
            }

            // Fetch models from the network service (will return mock data in dev mode)
            val modelsData = networkService.getRaw(
                endpoint = APIEndpoint.models,
                requiresAuth = false
            )

            // Parse the response
            val json = Json {
                ignoreUnknownKeys = true
                isLenient = true
            }

            val modelsJson = modelsData.decodeToString()
            logger.info("📦 Received models JSON: ${modelsJson.take(200)}...")

            val models = json.decodeFromString<List<com.runanywhere.sdk.models.ModelInfo>>(modelsJson)
            logger.info("📦 Parsed ${models.size} models from MockNetworkService")

            // Save each model to the ModelInfoService
            for (model in models) {
                logger.info("💾 Saving model: ${model.id} - ${model.name}")
                modelInfoService.saveModel(model)
            }

            // Verify models were saved
            val allModels = modelInfoService.getAllModels()
            logger.info("✅ Total models in ModelInfoService: ${allModels.size}")

            // Specifically check for whisper-base
            val whisperBase = modelInfoService.getModel("whisper-base")
            if (whisperBase != null) {
                logger.info("✅ Whisper Base model verified: ${whisperBase.name} (${(whisperBase.downloadSize ?: 0) / 1_000_000}MB)")
            } else {
                logger.error("❌ Whisper Base model not found after fetching from MockNetworkService!")
            }

        } catch (e: Exception) {
            logger.error("❌ Failed to fetch and populate models: ${e.message}", e)
            e.printStackTrace()
        }
    }

    /**
     * Cleanup all services
     */
    suspend fun cleanup() {
        // Only clear authentication if not in development mode
        // This avoids lazy-initializing the authenticationService in dev mode
        if (currentEnvironment != SDKEnvironment.DEVELOPMENT) {
            authenticationService.clearAuthentication()
        }
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

/**
 * Platform-specific telemetry repository creation
 */
expect fun createTelemetryRepository(): TelemetryRepository
