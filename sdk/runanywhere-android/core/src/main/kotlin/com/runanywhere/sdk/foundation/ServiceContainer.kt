package com.runanywhere.sdk.foundation

import com.runanywhere.sdk.components.stt.STTComponent
import com.runanywhere.sdk.components.stt.STTConfiguration
import com.runanywhere.sdk.components.vad.VADComponent
import com.runanywhere.sdk.components.vad.VADConfiguration
import com.runanywhere.sdk.models.*
import com.runanywhere.sdk.services.*
import com.runanywhere.sdk.data.models.SDKInitParams
import com.runanywhere.sdk.data.models.ConfigurationData
import com.runanywhere.sdk.data.models.ConfigurationSource
import com.runanywhere.sdk.network.APIClient
import com.runanywhere.sdk.network.AuthenticationService

/**
 * Central service container - mirrors Swift's ServiceContainer
 * Manages all SDK services with lazy initialization
 */
class ServiceContainer {

    companion object {
        val shared = ServiceContainer()
    }

    // Core Services
    val configurationService: ConfigurationService by lazy {
        ConfigurationService()
    }

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
        STTComponent(STTConfiguration())
    }

    // Network Services (can be null in development mode)
    var apiClient: APIClient? = null
    var authService: AuthenticationService? = null

    /**
     * Bootstrap services for production mode
     */
    suspend fun bootstrap(
        params: SDKInitParams,
        authService: AuthenticationService,
        apiClient: APIClient
    ): ConfigurationData {
        this.authService = authService
        this.apiClient = apiClient

        // Initialize configuration
        val config = configurationService.loadConfiguration()
            ?: ConfigurationData.default()

        // Initialize other services
        modelRegistry.initialize()
        memoryService.initialize()

        return config
    }

    /**
     * Bootstrap services for development mode with mock data
     */
    suspend fun bootstrapDevelopmentMode(params: SDKInitParams): ConfigurationData {
        // Use mock services
        val config = ConfigurationData(
            id = "dev-config",
            apiKey = "dev-mode",
            source = ConfigurationSource.LOCAL
        )

        // Initialize services with mock data
        modelRegistry.initialize()
        memoryService.initialize()

        return config
    }
}
