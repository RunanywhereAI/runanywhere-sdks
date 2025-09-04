package com.runanywhere.sdk.foundation

import android.content.Context
import com.runanywhere.sdk.components.stt.STTComponent
import com.runanywhere.sdk.components.stt.STTConfiguration
import com.runanywhere.sdk.components.vad.VADComponent
import com.runanywhere.sdk.components.vad.VADConfiguration
import com.runanywhere.sdk.models.*
import com.runanywhere.sdk.services.*
import com.runanywhere.sdk.data.models.*
import com.runanywhere.sdk.data.network.*
import com.runanywhere.sdk.data.network.services.MockNetworkService
import com.runanywhere.sdk.data.services.*
import com.runanywhere.sdk.data.database.RunAnywhereDatabase
import com.runanywhere.sdk.utils.SDKConstants

/**
 * Central service container - mirrors Swift's ServiceContainer
 * Manages all SDK services with lazy initialization
 */
class ServiceContainer {

    companion object {
        val shared = ServiceContainer()
    }

    // Context (set during initialization)
    private var context: Context? = null

    // Database
    val database: RunAnywhereDatabase by lazy {
        RunAnywhereDatabase.getDatabase(requireContext())
    }

    // Data Services (translated from iOS)
    val authenticationService: AuthenticationService by lazy {
        AuthenticationService(requireContext())
    }

    val configurationService: ConfigurationService by lazy {
        ConfigurationService(
            networkService = networkService,
            database = database
        )
    }

    val modelInfoService: ModelInfoService by lazy {
        ModelInfoService(
            networkService = networkService,
            database = database
        )
    }

    val deviceInfoService: DeviceInfoService by lazy {
        DeviceInfoService(
            context = requireContext(),
            database = database
        )
    }

    val telemetryService: TelemetryService by lazy {
        TelemetryService(
            networkService = networkService,
            database = database,
            deviceInfoService = deviceInfoService
        )
    }

    val fileManager: FileManager by lazy {
        FileManager(requireContext())
    }

    // Network Services
    val networkService: NetworkService by lazy {
        if (SDKConstants.Development.ENABLE_MOCK_SERVICES) {
            MockNetworkService()
        } else {
            // Real network service would be implemented here
            MockNetworkService() // For now, always use mock in development
        }
    }

    val apiClient: APIClient by lazy {
        APIClient(
            networkService = networkService,
            authenticationService = authenticationService
        )
    }

    // Legacy Services (keeping for compatibility)
    val modelRegistry: ModelRegistry by lazy {
        ModelRegistry()
    }

    val modelLoadingService: ModelLoadingService by lazy {
        ModelLoadingService(
            modelRegistry = modelRegistry,
            downloadService = downloadService,
            validationService = validationService
        )
    }

    val downloadService: DownloadService by lazy {
        DownloadService()
    }

    val validationService: ValidationService by lazy {
        ValidationService()
    }

    val memoryService: MemoryService by lazy {
        MemoryService()
    }

    val analyticsService: AnalyticsService by lazy {
        AnalyticsService()
    }

    // Components
    val vadComponent: VADComponent by lazy {
        VADComponent(VADConfiguration())
    }

    val sttComponent: STTComponent by lazy {
        STTComponent(STTConfiguration()).also { component ->
            // Integrate STT analytics
            component.setAnalyticsCallback { event, metadata ->
                // Send STT analytics through telemetry service
                val telemetryEvent = TelemetryEventData(
                    id = java.util.UUID.randomUUID().toString(),
                    type = TelemetryEventType.STT_EVENT,
                    sessionId = metadata["sessionId"] as? String ?: "",
                    deviceId = deviceInfoService.getDeviceId(),
                    timestamp = System.currentTimeMillis(),
                    eventData = mapOf(
                        "stt_event" to event.toString(),
                        "metadata" to metadata
                    ),
                    success = true,
                    duration = metadata["duration"] as? Long
                )

                // Launch coroutine to send telemetry
                kotlinx.coroutines.GlobalScope.launch {
                    try {
                        telemetryService.trackEvent(telemetryEvent)
                    } catch (e: Exception) {
                        SDKLogger("ServiceContainer").error("Failed to send STT analytics", e)
                    }
                }
            }
        }
    }

    /**
     * Initialize the service container with context
     */
    fun initialize(context: Context) {
        this.context = context.applicationContext
    }

    /**
     * Get the required context, throwing if not initialized
     */
    private fun requireContext(): Context {
        return context ?: throw IllegalStateException("ServiceContainer not initialized with context")
    }

    /**
     * Bootstrap services for production mode
     */
    suspend fun bootstrap(params: SDKInitParams): ConfigurationData {
        // Initialize authentication
        authenticationService.initialize(params.apiKey)

        // Load configuration from multiple sources
        val config = configurationService.loadConfiguration()
            ?: ConfigurationData.default(params.apiKey)

        // Initialize device info service
        deviceInfoService.initialize()

        // Initialize model info service with remote data
        modelInfoService.initialize()

        // Initialize telemetry service
        telemetryService.initialize()

        // Initialize legacy services for compatibility
        modelRegistry.initialize()
        memoryService.initialize()

        return config
    }

    /**
     * Bootstrap services for development mode with mock data
     */
    suspend fun bootstrapDevelopmentMode(params: SDKInitParams): ConfigurationData {
        // Initialize device info service
        deviceInfoService.initialize()

        // Load configuration from mock service
        val config = configurationService.loadConfiguration()
            ?: ConfigurationData.default(params.apiKey)

        // Initialize model info service with mock data
        modelInfoService.initialize()

        // Initialize telemetry service (will use mock backend)
        telemetryService.initialize()

        // Initialize legacy services with mock data
        modelRegistry.initialize()
        memoryService.initialize()

        return config
    }

    /**
     * Cleanup all services
     */
    suspend fun cleanup() {
        telemetryService.cleanup()
        sttComponent.cleanup()
        vadComponent.cleanup()
    }
}
