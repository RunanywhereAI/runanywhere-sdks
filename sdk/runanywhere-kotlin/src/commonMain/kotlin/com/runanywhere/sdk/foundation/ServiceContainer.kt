package com.runanywhere.sdk.foundation

import com.runanywhere.sdk.data.datasources.RemoteTelemetryDataSource
import com.runanywhere.sdk.data.models.SDKEnvironment
import com.runanywhere.sdk.data.network.AuthenticationService
import com.runanywhere.sdk.data.network.createHttpClient
import com.runanywhere.sdk.data.network.services.AnalyticsNetworkService
import com.runanywhere.sdk.data.repositories.ModelInfoRepository
import com.runanywhere.sdk.data.repositories.ModelInfoRepositoryImpl
import com.runanywhere.sdk.data.repositories.TelemetryRepository
import com.runanywhere.sdk.data.sync.SyncCoordinator
import com.runanywhere.sdk.features.llm.LLMCapability
import com.runanywhere.sdk.features.speakerdiarization.SpeakerDiarizationCapability
import com.runanywhere.sdk.features.stt.STTCapability
import com.runanywhere.sdk.features.tts.TTSCapability
import com.runanywhere.sdk.features.vad.VADCapability
import com.runanywhere.sdk.features.voiceagent.VoiceAgentCapability
import com.runanywhere.sdk.infrastructure.analytics.AnalyticsService
import com.runanywhere.sdk.infrastructure.analytics.TelemetryService
import com.runanywhere.sdk.infrastructure.download.DownloadConfiguration
import com.runanywhere.sdk.infrastructure.download.DownloadService
import com.runanywhere.sdk.infrastructure.download.KtorDownloadService
import com.runanywhere.sdk.infrastructure.download.KtorDownloadServiceAdapter
import com.runanywhere.sdk.infrastructure.modelmanagement.services.ModelInfoService
import com.runanywhere.sdk.models.DefaultModelRegistry
import com.runanywhere.sdk.models.DeviceInfo
import com.runanywhere.sdk.models.ModelManager
import com.runanywhere.sdk.models.ModelRegistry
import com.runanywhere.sdk.security.SecureStorageFactory
import com.runanywhere.sdk.storage.createFileSystem

/**
 * Central service container - Thin wrapper holding services, capabilities, and instances
 *
 * This is a dependency container that provides lazy-initialized instances.
 * All business logic and initialization flow is handled by RunAnywhere.kt.
 *
 * Pattern: iOS ServiceContainer.shared - provides access to shared instances
 */
class ServiceContainer {
    companion object {
        val shared = ServiceContainer()
    }

    private val logger = SDKLogger("ServiceContainer")

    // ============================================================================
    // MARK: - Platform Abstractions
    // ============================================================================

    internal val fileSystem by lazy { createFileSystem() }
    private val httpClient by lazy { createHttpClient() }
    private val secureStorage by lazy { SecureStorageFactory.create() }

    // ============================================================================
    // MARK: - Core Services
    // ============================================================================

    val authenticationService: AuthenticationService by lazy {
        AuthenticationService(secureStorage, httpClient)
    }

    val downloadService: DownloadService by lazy {
        val ktorService = KtorDownloadService(
            configuration = DownloadConfiguration(),
            fileSystem = fileSystem,
        )
        KtorDownloadServiceAdapter(ktorService)
    }

    val modelRegistry: ModelRegistry by lazy {
        DefaultModelRegistry()
    }

    val modelManager: ModelManager by lazy {
        ModelManager(fileSystem, downloadService)
    }

    val syncCoordinator: SyncCoordinator by lazy {
        SyncCoordinator()
    }

    val telemetryRepository: TelemetryRepository by lazy {
        createTelemetryRepository()
    }

    val modelInfoRepository: ModelInfoRepository by lazy {
        ModelInfoRepositoryImpl()
    }

    val modelInfoService: ModelInfoService by lazy {
        ModelInfoService(
            modelInfoRepository = modelInfoRepository,
            syncCoordinator = null,
        )
    }

    // ============================================================================
    // MARK: - Mutable Service State (Set by RunAnywhere during init)
    // ============================================================================

    /** Current environment - set during initialization */
    var currentEnvironment: SDKEnvironment? = null
        internal set

    /** Device info - collected during initialization (matches iOS DeviceInfo.current) */
    private var _deviceInfo: DeviceInfo? = null
    val deviceInfo: DeviceInfo? get() = _deviceInfo

    /** Device ID for analytics and telemetry */
    val deviceId: String
        get() = _deviceInfo?.deviceId ?: "unknown"

    /** Set device info (called by RunAnywhere during init) */
    internal fun setDeviceInfo(info: DeviceInfo) {
        _deviceInfo = info
    }

    // ============================================================================
    // MARK: - Analytics Services (Set by RunAnywhere during init)
    // ============================================================================

    private var _analyticsService: AnalyticsService? = null
    val analyticsService: AnalyticsService? get() = _analyticsService

    private var _telemetryService: TelemetryService? = null
    val telemetryService: TelemetryService? get() = _telemetryService

    private var _analyticsNetworkService: AnalyticsNetworkService? = null
    internal val analyticsNetworkService: AnalyticsNetworkService? get() = _analyticsNetworkService

    private var _remoteTelemetryDataSource: RemoteTelemetryDataSource? = null
    internal val remoteTelemetryDataSource: RemoteTelemetryDataSource? get() = _remoteTelemetryDataSource

    /** Set analytics services (called by RunAnywhere during init) */
    internal fun setAnalyticsService(service: AnalyticsService) {
        _analyticsService = service
    }

    internal fun setTelemetryService(service: TelemetryService) {
        _telemetryService = service
    }

    internal fun setAnalyticsNetworkService(service: AnalyticsNetworkService) {
        _analyticsNetworkService = service
    }

    internal fun setRemoteTelemetryDataSource(dataSource: RemoteTelemetryDataSource) {
        _remoteTelemetryDataSource = dataSource
    }

    // ============================================================================
    // MARK: - Capabilities (iOS-aligned - Capabilities are the primary API)
    // ============================================================================

    /**
     * STT Capability - Public API for Speech-to-Text operations
     * Uses ManagedLifecycle directly (iOS pattern - no Component layer)
     */
    val sttCapability: STTCapability by lazy {
        STTCapability()
    }

    /**
     * TTS Capability - Public API for Text-to-Speech operations
     * Uses ManagedLifecycle directly (iOS pattern - no Component layer)
     */
    val ttsCapability: TTSCapability by lazy {
        TTSCapability()
    }

    /**
     * LLM Capability - Public API for Language Model operations
     * Uses ManagedLifecycle directly (iOS pattern - no Component layer)
     */
    val llmCapability: LLMCapability by lazy {
        LLMCapability()
    }

    /**
     * VAD Capability - Public API for Voice Activity Detection operations
     * Uses VADService directly (iOS pattern - ServiceBasedCapability)
     */
    val vadCapability: VADCapability by lazy {
        VADCapability()
    }

    /**
     * Speaker Diarization Capability - Public API for Speaker Diarization operations
     * Uses service directly (iOS pattern - ServiceBasedCapability)
     */
    val speakerDiarizationCapability: SpeakerDiarizationCapability by lazy {
        SpeakerDiarizationCapability()
    }

    /**
     * VoiceAgent Capability - Public API for end-to-end voice AI pipeline
     * Composes: STT + LLM + TTS + VAD capabilities directly (iOS pattern)
     */
    val voiceAgentCapability: VoiceAgentCapability by lazy {
        VoiceAgentCapability(
            llm = llmCapability,
            stt = sttCapability,
            tts = ttsCapability,
            vad = vadCapability,
        )
    }

    // ============================================================================
    // MARK: - Cleanup
    // ============================================================================

    /**
     * Cleanup all services and capabilities
     * Called by RunAnywhere.cleanup()
     */
    suspend fun cleanup() {
        // Flush telemetry before cleanup
        try {
            _telemetryService?.flush()
            logger.info("✅ Telemetry flushed during cleanup")
        } catch (e: Exception) {
            logger.warn("Failed to flush telemetry during cleanup: ${e.message}")
        }

        // Clear authentication if not in development mode
        if (currentEnvironment != SDKEnvironment.DEVELOPMENT) {
            authenticationService.clearAuthentication()
        }

        // Cleanup capabilities
        sttCapability.cleanup()
        vadCapability.cleanup()
        llmCapability.cleanup()
        ttsCapability.cleanup()
        speakerDiarizationCapability.cleanup()
    }

    /**
     * Reset all mutable state (for testing)
     */
    internal fun reset() {
        currentEnvironment = null
        _deviceInfo = null
        _analyticsService = null
        _telemetryService = null
        _analyticsNetworkService = null
        _remoteTelemetryDataSource = null
    }
}

/**
 * Platform-specific context for initialization
 */
expect class PlatformContext {
    fun initialize()
}

/**
 * Platform-specific telemetry repository creation
 */
expect fun createTelemetryRepository(): TelemetryRepository
