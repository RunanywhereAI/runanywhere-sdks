package com.runanywhere.sdk.public

import com.runanywhere.sdk.data.models.SDKEnvironment
import com.runanywhere.sdk.data.models.SDKInitParams
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.events.EventBus
import com.runanywhere.sdk.events.EventPublisher
import com.runanywhere.sdk.events.SDKInitializationEvent
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.ServiceContainer
import com.runanywhere.sdk.capabilities.stt.STTCapability
import com.runanywhere.sdk.capabilities.tts.TTSCapability
import com.runanywhere.sdk.capabilities.llm.LLMCapability
import com.runanywhere.sdk.capabilities.vad.VADCapability
import com.runanywhere.sdk.capabilities.speakerdiarization.SpeakerDiarizationCapability
import com.runanywhere.sdk.capabilities.voiceagent.VoiceAgentCapability
import com.runanywhere.sdk.core.SDKConstants
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

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
//     ├─ Setup API Client
//     │    ├─ Development: Use Supabase
//     │    └─ Production/Staging: Authenticate with backend
//     ├─ Create Core Services
//     │    ├─ SyncCoordinator
//     │    ├─ TelemetryRepository
//     │    ├─ ModelInfoService
//     │    └─ ModelAssignmentService
//     ├─ Load Models (sync from remote + load from DB)
//     ├─ Initialize Analytics & EventPublisher
//     └─ Register Device with Backend
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

    /** Access to service container */
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
    val sttCapability: STTCapability?
        get() = serviceContainer.sttCapability

    /**
     * TTS Capability for text-to-speech operations
     * Use via extension functions: RunAnywhere.synthesize(), RunAnywhere.loadTTSVoice()
     */
    val ttsCapability: TTSCapability?
        get() = serviceContainer.ttsCapability

    /**
     * LLM Capability for language model operations
     * Use via extension functions: RunAnywhere.chat(), RunAnywhere.generate()
     */
    val llmCapability: LLMCapability?
        get() = serviceContainer.llmCapability

    /**
     * VAD Capability for voice activity detection operations
     * Use via extension functions: RunAnywhere.detectSpeech(), etc.
     */
    val vadCapability: VADCapability?
        get() = serviceContainer.vadCapability

    /**
     * Speaker Diarization Capability for speaker identification operations
     * Use via extension functions: RunAnywhere.identifySpeaker(), etc.
     */
    val speakerDiarizationCapability: SpeakerDiarizationCapability?
        get() = serviceContainer.speakerDiarizationCapability

    /**
     * VoiceAgent Capability for end-to-end voice AI pipeline
     * Use via extension functions: RunAnywhere.initializeVoiceAgent(), RunAnywhere.processVoiceTurn()
     */
    val voiceAgentCapability: VoiceAgentCapability?
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
        environment: SDKEnvironment = SDKEnvironment.DEVELOPMENT
    ) {
        val params: SDKInitParams

        if (environment == SDKEnvironment.DEVELOPMENT) {
            // Development mode - no auth needed
            params = SDKInitParams(
                apiKey = apiKey ?: "",
                baseURL = baseURL,
                environment = environment
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
            val logLevel = when (params.environment) {
                SDKEnvironment.DEVELOPMENT -> SDKLogger.Companion.LogLevel.DEBUG
                SDKEnvironment.STAGING -> SDKLogger.Companion.LogLevel.INFO
                SDKEnvironment.PRODUCTION -> SDKLogger.Companion.LogLevel.WARNING
            }
            SDKLogger.setLogLevel(logLevel)

            // Step 2: Store parameters
            initParams = params
            currentEnvironment = params.environment

            // Step 3: Persist to secure storage (production/staging only)
            if (params.environment != SDKEnvironment.DEVELOPMENT) {
                // Note: Keychain storage handled by platform-specific code
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
     * 1. Sets up API client (with authentication for production/staging)
     * 2. Creates core services (telemetry, models, sync)
     * 3. Loads model catalog from remote + local storage
     * 4. Initializes analytics pipeline
     * 5. Registers device with backend
     */
    suspend fun completeServicesInitialization() {
        // Fast path: already completed
        if (_hasCompletedServicesInit) {
            return
        }

        val params = initParams ?: throw SDKError.NotInitialized
        val environment = currentEnvironment ?: throw SDKError.NotInitialized

        initMutex.withLock {
            // Double-check after acquiring lock
            if (_hasCompletedServicesInit) {
                return
            }

            logger.info("Initializing services for ${environment.name} mode...")

            try {
                // Bootstrap based on environment
                if (environment == SDKEnvironment.DEVELOPMENT) {
                    serviceContainer.bootstrapDevelopmentMode(params)
                } else {
                    serviceContainer.bootstrap(params)
                }

                // Mark Phase 2 complete
                _hasCompletedServicesInit = true
                logger.info("✅ Services initialized")

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
