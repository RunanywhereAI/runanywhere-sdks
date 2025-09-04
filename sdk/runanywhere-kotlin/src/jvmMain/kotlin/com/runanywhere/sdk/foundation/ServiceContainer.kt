package com.runanywhere.sdk.foundation

import com.runanywhere.sdk.components.stt.STTComponent
import com.runanywhere.sdk.components.stt.STTConfiguration
import com.runanywhere.sdk.components.vad.VADComponent
import com.runanywhere.sdk.components.vad.VADConfiguration
import com.runanywhere.sdk.data.models.*
import com.runanywhere.sdk.data.repositories.ModelInfoRepository
import com.runanywhere.sdk.data.repositories.ModelInfoRepositoryImpl
import com.runanywhere.sdk.services.modelinfo.ModelInfoService
import com.runanywhere.sdk.services.sync.SyncCoordinator
import com.runanywhere.sdk.services.ValidationService

/**
 * Central service container - JVM Implementation
 * Simplified version for JVM without Android dependencies
 */
class ServiceContainer {

    companion object {
        val shared = ServiceContainer()
    }

    // Working directory (replaces Android Context)
    private var workingDirectory: String? = null

    // Simple in-memory repositories for JVM
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
    val validationService: ValidationService by lazy {
        ValidationService()
    }

    /**
     * Initialize the service container with working directory (JVM version)
     */
    fun initialize(workingDirectory: String) {
        this.workingDirectory = workingDirectory
    }

    /**
     * Bootstrap services for production mode
     */
    suspend fun bootstrap(params: SDKInitParams): ConfigurationData {
        // Initialize services
        modelInfoService.initialize()

        // Return default configuration
        return ConfigurationData.default(params.apiKey)
    }

    /**
     * Bootstrap services for development mode with mock data
     */
    suspend fun bootstrapDevelopmentMode(params: SDKInitParams): ConfigurationData {
        // Initialize services
        modelInfoService.initialize()

        // Return default configuration
        return ConfigurationData.default(params.apiKey)
    }

    /**
     * Cleanup all services
     */
    suspend fun cleanup() {
        sttComponent.cleanup()
        vadComponent.cleanup()
    }
}
