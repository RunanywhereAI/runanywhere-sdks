package com.runanywhere.sdk.foundation

import com.runanywhere.sdk.components.stt.STTComponent
import com.runanywhere.sdk.components.stt.STTConfiguration
import com.runanywhere.sdk.components.vad.VADComponent
import com.runanywhere.sdk.components.vad.VADConfiguration
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
        // Initialize authentication
        authenticationService.initialize(params.apiKey)

        // Initialize services
        modelInfoService.initialize()

        // Return default configuration
        return ConfigurationData.default(params.apiKey)
    }

    /**
     * Bootstrap services for development mode with mock data
     */
    suspend fun bootstrapDevelopmentMode(params: SDKInitParams): ConfigurationData {
        // Initialize authentication (even in dev mode)
        authenticationService.initialize(params.apiKey)

        // Initialize services
        modelInfoService.initialize()

        // Return default configuration
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
