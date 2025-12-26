package com.runanywhere.sdk.public

import com.runanywhere.sdk.config.SDKConfig
import com.runanywhere.sdk.core.ModuleRegistry
import com.runanywhere.sdk.data.datasources.RemoteTelemetryDataSource
import com.runanywhere.sdk.data.models.SDKEnvironment
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.data.models.SDKInitParams
import com.runanywhere.sdk.data.network.services.AnalyticsNetworkService
import com.runanywhere.sdk.data.repositories.ModelInfoRepositoryImpl
import com.runanywhere.sdk.features.llm.LLMCapability
import com.runanywhere.sdk.features.speakerdiarization.SpeakerDiarizationCapability
import com.runanywhere.sdk.features.stt.STTCapability
import com.runanywhere.sdk.features.tts.TTSCapability
import com.runanywhere.sdk.features.vad.SimpleEnergyVAD
import com.runanywhere.sdk.features.vad.VADCapability
import com.runanywhere.sdk.features.voiceagent.VoiceAgentCapability
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.ServiceContainer
import com.runanywhere.sdk.foundation.device.DeviceInfoService
import com.runanywhere.sdk.foundation.utils.ModelPathUtils
import com.runanywhere.sdk.infrastructure.analytics.AnalyticsQueueManager
import com.runanywhere.sdk.infrastructure.analytics.AnalyticsService
import com.runanywhere.sdk.infrastructure.analytics.TelemetryService
import com.runanywhere.sdk.infrastructure.events.EventBus
import com.runanywhere.sdk.infrastructure.events.EventPublisher
import com.runanywhere.sdk.infrastructure.events.SDKInitializationEvent
import com.runanywhere.sdk.models.DeviceInfo
import com.runanywhere.sdk.utils.SDKConstants
import io.ktor.client.HttpClient
import io.ktor.client.plugins.HttpTimeout
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.serialization.kotlinx.json.json
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.Json

// ═══════════════════════════════════════════════════════════════════════════
// SDK INITIALIZATION FLOW
// ═══════════════════════════════════════════════════════════════════════════
//
// PHASE 1: Core Init (Synchronous, ~1-5ms, No Network)
// ─────────────────────────────────────────────────────
//   RunAnywhere.initialize() or RunAnywhere.initialize(apiKey, baseURL, environment)
//     ├─ Validate params (API key, URL, environment)
//     ├─ Set log level
//     ├─ Store params locally
//     ├─ Store in Keychain (production/staging only)
//     └─ Mark: isInitialized = true
//
// PHASE 2: Services Init (Async, ~100-500ms, Network Required)
// ────────────────────────────────────────────────────────────
//   RunAnywhere.completeServicesInitialization()
//     ├─ Collect device info (DeviceInfo.current)
//     ├─ Setup API Client
//     │    ├─ Development: No auth needed
//     │    └─ Production/Staging: Authenticate with backend
//     ├─ Create Core Services (telemetry, models, sync)
//     ├─ Load Models (scan local storage)
//     ├─ Initialize Analytics & EventPublisher
//     ├─ Register Default Modules (VAD, STT, TTS, LLM, Speaker Diarization)
//     └─ Initialize Capabilities (VAD auto-init, others on-demand)
//
// USAGE:
// ──────
//   // Development mode (default)
//   RunAnywhere.initialize()
//
//   // Production mode - requires API key and backend URL
//   RunAnywhere.initialize(
//       apiKey = "your_api_key",
//       baseURL = "https://api.runanywhere.ai",
//       environment = SDKEnvironment.PRODUCTION
//   )
//

/**
 * The RunAnywhere SDK - Single entry point for on-device AI
 *
 * This object mirrors the iOS RunAnywhere enum pattern, providing:
 * - SDK initialization (two-phase: fast sync + async services)
 * - State access (isInitialized, areServicesReady, version, environment)
 * - Event access via `events` property
 * - Capability access via sttCapability, ttsCapability, llmCapability
 *
 * Feature-specific APIs are available through extension functions:
 * - STT: RunAnywhere.transcribe(), RunAnywhere.loadSTTModel()
 * - TTS: RunAnywhere.synthesize(), RunAnywhere.loadTTSVoice()
 * - LLM: RunAnywhere.chat(), RunAnywhere.generate(), RunAnywhere.generateStream()
 */
object RunAnywhere {
    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: - Internal State Management
    // ═══════════════════════════════════════════════════════════════════════════

    private val logger = SDKLogger("RunAnywhere")
    private val initMutex = Mutex()

    /** Internal init params storage */
    internal var initParams: SDKInitParams? = null
        private set

    /** Current environment */
    internal var currentEnvironment: SDKEnvironment? = null
        private set

    /** Phase 1 completion flag */
    private var _isInitialized = false

    /** Phase 2 completion flag */
    private var _hasCompletedServicesInit = false

    /** Access to service container (thin wrapper) */
    internal val serviceContainer: ServiceContainer
        get() = ServiceContainer.shared

    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: - SDK State (Public Properties)
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * Check if SDK is initialized (Phase 1 complete)
     */
    val isSDKInitialized: Boolean
        get() = _isInitialized

    /**
     * Alias for isSDKInitialized for convenience
     */
    val isInitialized: Boolean
        get() = _isInitialized

    /**
     * Check if services are fully ready (Phase 2 complete)
     */
    val areServicesReady: Boolean
        get() = _hasCompletedServicesInit

    /**
     * Check if SDK is active and ready for use
     */
    val isActive: Boolean
        get() = _isInitialized && initParams != null

    /**
     * Current SDK version
     */
    val version: String
        get() = SDKConstants.SDK_VERSION

    /**
     * Current environment (null if not initialized)
     */
    val environment: SDKEnvironment?
        get() = currentEnvironment

    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: - Event Access
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * Access to all SDK events for subscription-based patterns
     * Events are routed based on their destination property:
     * - PUBLIC_ONLY → EventBus only (app developers)
     * - ANALYTICS_ONLY → Backend only (telemetry)
     * - ALL → Both destinations (default)
     */
    val events: EventBus
        get() = EventBus.shared

    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: - Capability Access
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * STT Capability for speech-to-text operations
     * Use via extension functions: RunAnywhere.transcribe(), RunAnywhere.loadSTTModel()
     */
    val sttCapability: STTCapability
        get() = serviceContainer.sttCapability

    /**
     * TTS Capability for text-to-speech operations
     * Use via extension functions: RunAnywhere.synthesize(), RunAnywhere.loadTTSVoice()
     */
    val ttsCapability: TTSCapability
        get() = serviceContainer.ttsCapability

    /**
     * LLM Capability for language model operations
     * Use via extension functions: RunAnywhere.chat(), RunAnywhere.generate()
     */
    val llmCapability: LLMCapability
        get() = serviceContainer.llmCapability

    /**
     * VAD Capability for voice activity detection operations
     * Use via extension functions: RunAnywhere.detectSpeech(), etc.
     */
    val vadCapability: VADCapability
        get() = serviceContainer.vadCapability

    /**
     * Speaker Diarization Capability for speaker identification operations
     * Use via extension functions: RunAnywhere.identifySpeaker(), etc.
     */
    val speakerDiarizationCapability: SpeakerDiarizationCapability
        get() = serviceContainer.speakerDiarizationCapability

    /**
     * VoiceAgent Capability for end-to-end voice AI pipeline
     * Use via extension functions: RunAnywhere.initializeVoiceAgent(), RunAnywhere.processVoiceTurn()
     */
    val voiceAgentCapability: VoiceAgentCapability
        get() = serviceContainer.voiceAgentCapability

    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: - SDK Initialization
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * Initialize the RunAnywhere SDK
     *
     * This performs fast synchronous initialization, then starts async services in background.
     * The SDK is usable immediately - services will be ready when first API call is made.
     *
     * **Phase 1 (Sync, ~1-5ms):** Validates params, sets up logging, stores config
     * **Phase 2 (Background):** Network auth, service creation, model loading, device registration
     *
     * ## Usage Examples
     *
     * ```kotlin
     * // Development mode (default)
     * RunAnywhere.initialize()
     *
     * // Production mode - requires API key and backend URL
     * RunAnywhere.initialize(
     *     apiKey = "your_api_key",
     *     baseURL = "https://api.runanywhere.ai",
     *     environment = SDKEnvironment.PRODUCTION
     * )
     * ```
     *
     * @param apiKey API key (optional for development, required for production/staging)
     * @param baseURL Backend API base URL (optional for development, required for production/staging)
     * @param environment SDK environment (default: DEVELOPMENT)
     * @throws SDKError.InvalidConfiguration if validation fails
     */
    fun initialize(
        apiKey: String? = null,
        baseURL: String? = null,
        environment: SDKEnvironment = SDKEnvironment.DEVELOPMENT,
    ) {
        val params: SDKInitParams

        if (environment == SDKEnvironment.DEVELOPMENT) {
            // Development mode - no auth needed
            params =
                SDKInitParams(
                    apiKey = apiKey ?: "",
                    baseURL = baseURL,
                    environment = environment,
                )
        } else {
            // Production/Staging mode - require API key and URL
            if (apiKey.isNullOrEmpty()) {
                throw SDKError.InvalidConfiguration("API key is required for ${environment.name} mode")
            }
            if (baseURL.isNullOrEmpty()) {
                throw SDKError.InvalidConfiguration("Base URL is required for ${environment.name} mode")
            }
            params = SDKInitParams(apiKey = apiKey, baseURL = baseURL, environment = environment)
        }

        performCoreInit(params)
    }

    /**
     * Initialize SDK for development mode (convenience method)
     */
    fun initializeForDevelopment(apiKey: String? = null) {
        initialize(apiKey = apiKey, environment = SDKEnvironment.DEVELOPMENT)
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: - Phase 1: Core Initialization (Synchronous)
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * Perform core initialization (Phase 1)
     */
    private fun performCoreInit(params: SDKInitParams) {
        // Return early if already initialized
        if (_isInitialized) {
            logger.info("SDK already initialized")
            return
        }

        val initStartTime = System.currentTimeMillis()

        EventPublisher.track(SDKInitializationEvent.Started)

        try {
            // Step 1: Initialize logging system
            val logLevel =
                when (params.environment) {
                    SDKEnvironment.DEVELOPMENT -> SDKLogger.Companion.LogLevel.DEBUG
                    SDKEnvironment.STAGING -> SDKLogger.Companion.LogLevel.INFO
                    SDKEnvironment.PRODUCTION -> SDKLogger.Companion.LogLevel.WARNING
                }
            SDKLogger.setLogLevel(logLevel)

            // Step 2: Store parameters
            initParams = params
            currentEnvironment = params.environment
            serviceContainer.currentEnvironment = params.environment

            // Step 3: Persist to secure storage (production/staging only)
            if (params.environment != SDKEnvironment.DEVELOPMENT) {
                logger.debug("Credentials will be stored securely")
            }

            // Mark Phase 1 complete
            _isInitialized = true

            val initDurationMs = System.currentTimeMillis() - initStartTime
            logger.info("✅ Phase 1 complete in ${initDurationMs}ms (${params.environment.name})")

            EventPublisher.track(SDKInitializationEvent.Completed)
        } catch (error: Exception) {
            logger.error("❌ Initialization failed: ${error.message}")
            initParams = null
            _isInitialized = false
            EventPublisher.track(SDKInitializationEvent.Failed(error))
            throw error
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: - Phase 2: Services Initialization (Async)
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * Complete services initialization (Phase 2)
     *
     * Called automatically on first API call, or can be awaited directly.
     * Safe to call multiple times - returns immediately if already done.
     *
     * This method:
     * 1. Collects device info (DeviceInfo.current)
     * 2. Sets up API client (with authentication for production/staging)
     * 3. Creates core services (telemetry, models, sync)
     * 4. Loads model catalog from local storage
     * 5. Initializes analytics pipeline
     * 6. Registers default modules for all capabilities
     * 7. Initializes capabilities (VAD auto-init, others on-demand)
     */
    suspend fun completeServicesInitialization() {
        // Fast path: already completed
        if (_hasCompletedServicesInit) {
            return
        }

        val params = initParams ?: throw SDKError.NotInitialized

        initMutex.withLock {
            // Double-check after acquiring lock
            if (_hasCompletedServicesInit) {
                return
            }

            val environment = params.environment
            logger.info("Initializing services for ${environment.name} mode...")

            try {
                // Step 1: Collect device info (matches iOS DeviceInfo.current)
                val deviceInfo = DeviceInfo.current
                serviceContainer.setDeviceInfo(deviceInfo)
                logger.debug("Device: ${deviceInfo.description}")

                // Step 2: Setup API client based on environment
                setupAPIClient(params, environment)

                // Step 3: Create core services
                setupCoreServices()

                // Step 4: Load models from storage
                loadModels()

                // Step 5: Initialize analytics
                initializeAnalytics(params, environment)

                // Step 6: Register default modules for all capabilities
                registerDefaultModules()

                // Step 7: Initialize capabilities
                initializeCapabilities()

                // Mark Phase 2 complete
                _hasCompletedServicesInit = true
                logger.info("✅ Services initialized for ${environment.name} mode")
            } catch (e: Exception) {
                logger.error("Services initialization failed: ${e.message}")
                throw e
            }
        }
    }

    /**
     * Ensure services are ready before API calls (internal guard)
     * O(1) after first successful initialization
     */
    internal suspend fun ensureServicesReady() {
        if (_hasCompletedServicesInit) {
            return // O(1) fast path
        }
        completeServicesInitialization()
    }

    /**
     * Ensure SDK is initialized (throws if not)
     */
    internal fun requireInitialized() {
        if (!_isInitialized) {
            throw SDKError.NotInitialized
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: - Initialization Steps
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * Setup API client based on environment
     * - Development: No auth needed
     * - Staging/Production: Authenticate with backend
     */
    private suspend fun setupAPIClient(params: SDKInitParams, environment: SDKEnvironment) {
        when (environment) {
            SDKEnvironment.DEVELOPMENT -> {
                logger.debug("APIClient: Development mode (no auth)")
            }

            SDKEnvironment.STAGING, SDKEnvironment.PRODUCTION -> {
                if (params.baseURL != null) {
                    SDKConfig.baseURL = params.baseURL
                    logger.debug("SDKConfig.baseURL set to: ${params.baseURL}")
                }
                serviceContainer.authenticationService.authenticate(params.apiKey)
                logger.info("Authenticated for ${environment.name}")
            }
        }
    }

    /**
     * Create and initialize core services
     */
    private suspend fun setupCoreServices() {
        logger.debug("Creating core services...")
        serviceContainer.modelInfoService.initialize()
        logger.debug("Core services created")
    }

    /**
     * Load models from storage
     */
    private suspend fun loadModels() {
        val modelsPath = ModelPathUtils.getModelsDirectory()
        val repository = serviceContainer.modelInfoRepository
        if (repository is ModelInfoRepositoryImpl) {
            repository.scanAndUpdateDownloadedModels(modelsPath, serviceContainer.fileSystem)
        }
        logger.debug("Model catalog loaded from: $modelsPath")
    }

    /**
     * Initialize analytics pipeline
     */
    private suspend fun initializeAnalytics(params: SDKInitParams, environment: SDKEnvironment) {
        try {
            // Create analytics network services for production/staging
            if (environment != SDKEnvironment.DEVELOPMENT && params.baseURL != null) {
                logger.debug("Creating production analytics network services...")

                val analyticsKtorClient =
                    HttpClient {
                        install(ContentNegotiation) {
                            json(
                                Json {
                                    ignoreUnknownKeys = true
                                    prettyPrint = false
                                    isLenient = true
                                },
                            )
                        }
                        install(HttpTimeout) {
                            requestTimeoutMillis = 30000
                            connectTimeoutMillis = 10000
                        }
                    }

                val analyticsNetworkService =
                    AnalyticsNetworkService(
                        httpClient = analyticsKtorClient,
                        baseURL = params.baseURL,
                        apiKey = params.apiKey,
                        authenticationService = serviceContainer.authenticationService,
                    )
                serviceContainer.setAnalyticsNetworkService(analyticsNetworkService)

                val remoteTelemetryDataSource =
                    RemoteTelemetryDataSource(
                        analyticsNetworkService = analyticsNetworkService,
                    )
                serviceContainer.setRemoteTelemetryDataSource(remoteTelemetryDataSource)

                logger.debug("Production analytics network services created")
            }

            // Initialize AnalyticsService
            val analyticsService =
                AnalyticsService(
                    telemetryRepository = serviceContainer.telemetryRepository,
                    syncCoordinator = serviceContainer.syncCoordinator,
                    supabaseConfig = params.supabaseConfig,
                    environment = environment,
                )
            analyticsService.initialize()
            serviceContainer.setAnalyticsService(analyticsService)

            // Initialize TelemetryService
            val telemetryService =
                TelemetryService(
                    telemetryRepository = serviceContainer.telemetryRepository,
                    syncCoordinator = serviceContainer.syncCoordinator,
                )
            telemetryService.initialize()
            serviceContainer.setTelemetryService(telemetryService)

            // Set telemetry context with device info
            val deviceId = serviceContainer.deviceId
            telemetryService.setContext(
                deviceId = deviceId,
                appVersion = null,
                sdkVersion = SDKConstants.SDK_VERSION,
            )

            // Wire EventPublisher to AnalyticsQueueManager for dual-path routing
            initializeEventPublisher()

            logger.debug("Analytics initialized")
        } catch (e: Exception) {
            if (environment == SDKEnvironment.DEVELOPMENT) {
                logger.warn("Analytics initialization failed (non-critical in dev mode): ${e.message}")
            } else {
                throw SDKError.InitializationFailed(
                    "Analytics service initialization failed: ${e.message}",
                )
            }
        }
    }

    /**
     * Initialize EventPublisher with AnalyticsQueueManager for dual-path event routing.
     *
     * SDKEvent is the single unified event type for the entire SDK.
     * Events are routed based on their destination property:
     * - PUBLIC_ONLY → EventBus only (app developers)
     * - ANALYTICS_ONLY → AnalyticsQueueManager only (backend telemetry)
     * - ALL → Both destinations (default)
     */
    private fun initializeEventPublisher() {
        // Initialize AnalyticsQueueManager with telemetry repository and device info
        val deviceInfoService = DeviceInfoService()
        AnalyticsQueueManager.initialize(
            telemetryRepository = serviceContainer.telemetryRepository,
            deviceInfoService = deviceInfoService,
        )

        // Wire EventPublisher to route SDKEvents to analytics
        // SDKEvent implements the required fields (type, properties, timestamp)
        EventPublisher.initializeWithSDKEventRouting(serviceContainer.telemetryRepository)

        logger.debug("EventPublisher initialized with dual-path routing")
    }

    /**
     * Register default modules for all capabilities.
     *
     * Each capability type has providers that must be registered:
     * - VAD: SimpleEnergyVAD (built-in), Silero VAD (external module)
     * - STT: WhisperKit (external module - registered by consuming app)
     * - TTS: Platform TTS (external module - registered by consuming app)
     * - LLM: LlamaCpp (external module - auto-registers if on classpath)
     * - Speaker Diarization: (external module - registered by consuming app)
     *
     * External modules register themselves via ModuleRegistry when imported.
     */
    private fun registerDefaultModules() {
        logger.info("Registering default modules for all capabilities")

        // VAD: Register built-in SimpleEnergyVAD provider
        try {
            registerBuiltInVADProvider()
            logger.info("✅ VAD: SimpleEnergyVAD provider registered")
        } catch (e: Exception) {
            logger.warn("⚠️ VAD provider registration failed: ${e.message}")
        }

        // STT: WhisperKit and other STT providers are external modules
        // They auto-register when the module is included in the app
        if (ModuleRegistry.hasSTT) {
            logger.info("✅ STT: Provider already registered by external module")
        } else {
            logger.info("ℹ️ STT: No provider registered - include an STT module (e.g., WhisperKit)")
        }

        // TTS: Platform TTS providers are external modules
        if (ModuleRegistry.hasTTS) {
            logger.info("✅ TTS: Provider already registered by external module")
        } else {
            logger.info("ℹ️ TTS: No provider registered - include a TTS module")
        }

        // LLM: LlamaCpp and other LLM providers are external modules
        // LlamaCpp auto-registers via its object initializer when on classpath
        if (ModuleRegistry.hasLLM) {
            logger.info("✅ LLM: Provider already registered by external module")
        } else {
            logger.info("ℹ️ LLM: No provider registered - include an LLM module (e.g., LlamaCpp)")
        }

        // Speaker Diarization: External modules
        if (ModuleRegistry.hasSpeakerDiarization) {
            logger.info("✅ Speaker Diarization: Provider already registered by external module")
        } else {
            logger.info("ℹ️ Speaker Diarization: No provider registered - include a diarization module")
        }

        logger.info("Module registration completed. Registered: ${ModuleRegistry.registeredModules}")
    }

    /**
     * Register the built-in SimpleEnergyVAD
     */
    private fun registerBuiltInVADProvider() {
        ModuleRegistry.registerVAD("SimpleEnergyVAD") { config ->
            SimpleEnergyVAD(vadConfig = config)
        }
    }

    /**
     * Initialize capabilities
     *
     * VAD is auto-initialized as it's a ServiceBasedCapability.
     * STT, TTS, LLM require explicit model loading via their respective load methods.
     */
    private suspend fun initializeCapabilities() {
        logger.debug("Initializing SDK capabilities")

        // VAD: Auto-initialize (ServiceBasedCapability pattern)
        try {
            vadCapability.initialize()
            logger.debug("✅ VAD capability initialized")
        } catch (e: Exception) {
            logger.warn("⚠️ VAD capability initialization failed: ${e.message}")
        }

        // STT, LLM, TTS: NOT initialized during bootstrap
        // They require explicit model loading via:
        // - sttCapability.loadModel(modelId)
        // - llmCapability.loadModel(modelId)
        // - ttsCapability.loadVoice(voiceId)

        logger.debug("Capability initialization completed")
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MARK: - SDK Reset (Testing)
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * Reset SDK state (for testing purposes)
     * Clears all initialization state and cached data
     */
    suspend fun reset() {
        logger.info("Resetting SDK state...")

        _isInitialized = false
        _hasCompletedServicesInit = false
        initParams = null
        currentEnvironment = null

        serviceContainer.cleanup()
        serviceContainer.reset()

        logger.info("SDK state reset completed")
    }

    /**
     * Cleanup SDK resources without full reset
     */
    suspend fun cleanup() {
        logger.info("Cleaning up SDK resources...")
        serviceContainer.cleanup()
    }
}
