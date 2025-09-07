package com.runanywhere.sdk.public

import com.runanywhere.sdk.data.models.SDKEnvironment
import com.runanywhere.sdk.data.models.ConfigurationData
import com.runanywhere.sdk.data.models.SDKInitParams
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.events.EventBus
import com.runanywhere.sdk.events.SDKInitializationEvent
import com.runanywhere.sdk.foundation.ServiceContainer
import com.runanywhere.sdk.foundation.SDKLogger
import kotlinx.coroutines.flow.Flow

/**
 * Main public API interface for RunAnywhere SDK
 * Common logic stays here, platform-specific implementations in actual
 */
interface RunAnywhereSDK {
    val isInitialized: Boolean
    val currentEnvironment: SDKEnvironment
    val events: EventBus

    suspend fun initialize(
        apiKey: String,
        baseURL: String? = null,
        environment: SDKEnvironment = SDKEnvironment.DEVELOPMENT
    )

    suspend fun availableModels(): List<ModelInfo>
    suspend fun downloadModel(modelId: String): Flow<Float>
    suspend fun transcribe(audioData: ByteArray): String
    suspend fun cleanup()
}

/**
 * Common SDK implementation with shared logic
 * Follows iOS 8-step initialization pattern
 */
abstract class BaseRunAnywhereSDK : RunAnywhereSDK {
    protected var _isInitialized = false
    protected var _currentEnvironment: SDKEnvironment = SDKEnvironment.DEVELOPMENT
    protected var _configurationData: ConfigurationData? = null
    protected var _initParams: SDKInitParams? = null

    private val logger = SDKLogger("RunAnywhere.Init")
    protected val serviceContainer: ServiceContainer = ServiceContainer.shared

    override val isInitialized: Boolean
        get() = _isInitialized

    override val currentEnvironment: SDKEnvironment
        get() = _currentEnvironment

    override val events: EventBus
        get() = EventBus.shared

    /**
     * Initialize the RunAnywhere SDK
     *
     * This method performs a comprehensive initialization sequence:
     *
     * 1. **Validation**: Validate API key and parameters
     * 2. **Logging**: Initialize logging system based on environment
     * 3. **Storage**: Store credentials securely in keychain/keystore
     * 4. **Database**: Set up local database for caching
     * 5. **Authentication**: Exchange API key for access token with backend
     * 6. **Health Check**: Verify backend connectivity and service health
     * 7. **Bootstrap**: Initialize all services and sync with backend
     * 8. **Configuration**: Load and apply configuration
     *
     * The initialization is atomic - if any step fails, the entire process
     * is rolled back and the SDK remains uninitialized.
     */
    override suspend fun initialize(
        apiKey: String,
        baseURL: String?,
        environment: SDKEnvironment
    ) {
        if (_isInitialized) {
            logger.info("SDK already initialized")
            return
        }

        val params = SDKInitParams(
            apiKey = apiKey,
            baseURL = baseURL,
            environment = environment
        )

        EventBus.shared.publish(SDKInitializationEvent.Started)

        try {
            // Step 1: Validate API key (skip in development mode)
            if (environment != SDKEnvironment.DEVELOPMENT) {
                logger.info("Step 1/8: Validating API key")
                if (apiKey.isEmpty()) {
                    throw SDKError.InvalidAPIKey("API key cannot be empty")
                }
            } else {
                logger.info("Step 1/8: Skipping API key validation in development mode")
            }

            // Step 2: Initialize logging system
            logger.info("Step 2/8: Initializing logging system")
            initializeLogging(environment)

            // Step 3: Store parameters securely
            logger.info("Step 3/8: Storing credentials securely")
            _initParams = params
            _currentEnvironment = environment

            // Only store in secure storage for non-development environments
            if (environment != SDKEnvironment.DEVELOPMENT) {
                storeCredentialsSecurely(params)
            }

            // Step 4: Initialize database
            logger.info("Step 4/8: Initializing local database")
            initializeDatabase()

            // Development mode: Skip API authentication and use local/mock services
            if (environment == SDKEnvironment.DEVELOPMENT) {
                logger.info("🚀 Running in DEVELOPMENT mode - using local/mock services")
                logger.info("Step 5/8: Skipping API authentication in development mode")
                logger.info("Step 6/8: Skipping health check in development mode")
                logger.info("Step 7/8: Bootstrapping SDK services with local data")

                // Bootstrap without API client for development mode
                val loadedConfig = serviceContainer.bootstrapDevelopmentMode(params)

                // Step 8: Store the configuration
                logger.info("Step 8/8: Loading configuration")
                _configurationData = loadedConfig

                // Mark as initialized
                _isInitialized = true
                logger.info("✅ SDK initialization completed successfully (Development Mode)")
                EventBus.shared.publish(SDKInitializationEvent.Completed)

            } else {
                // Production/Staging mode: Full API authentication flow

                // Step 5: Initialize API client and authentication service
                logger.info("Step 5/8: Authenticating with backend")
                authenticateWithBackend(params)

                // Step 6: Perform health check
                logger.info("Step 6/8: Performing health check")
                performHealthCheck()

                // Step 7: Bootstrap SDK services and sync with backend
                logger.info("Step 7/8: Bootstrapping SDK services and syncing with backend")
                val loadedConfig = serviceContainer.bootstrap(params)

                // Step 8: Store the configuration
                logger.info("Step 8/8: Loading configuration")
                _configurationData = loadedConfig

                // Mark as initialized
                _isInitialized = true
                logger.info("✅ SDK initialization completed successfully")
                EventBus.shared.publish(SDKInitializationEvent.Completed)
            }

        } catch (error: Exception) {
            logger.error("❌ SDK initialization failed: ${error.message}")
            _configurationData = null
            _initParams = null
            _isInitialized = false
            EventBus.shared.publish(SDKInitializationEvent.Failed(error))
            throw error
        }
    }

    /**
     * Initialize logging system based on environment
     */
    protected open fun initializeLogging(environment: SDKEnvironment) {
        // Set log level based on environment
        val logLevel = when (environment) {
            SDKEnvironment.DEVELOPMENT -> SDKLogger.Companion.LogLevel.DEBUG
            SDKEnvironment.STAGING -> SDKLogger.Companion.LogLevel.INFO
            SDKEnvironment.PRODUCTION -> SDKLogger.Companion.LogLevel.WARNING
        }
        SDKLogger.setLogLevel(logLevel)
    }

    /**
     * Store credentials securely (platform-specific)
     */
    protected abstract suspend fun storeCredentialsSecurely(params: SDKInitParams)

    /**
     * Initialize local database (platform-specific)
     */
    protected abstract suspend fun initializeDatabase()

    /**
     * Authenticate with backend API
     */
    protected abstract suspend fun authenticateWithBackend(params: SDKInitParams)

    /**
     * Perform health check on backend services
     */
    protected abstract suspend fun performHealthCheck()

    override suspend fun cleanup() {
        if (!_isInitialized) return

        cleanupPlatform()
        _isInitialized = false
        println("SDK cleaned up")
    }

    /**
     * Platform-specific cleanup to be implemented
     */
    protected abstract suspend fun cleanupPlatform()

    protected fun requireInitialized() {
        if (!_isInitialized) {
            throw IllegalStateException("SDK not initialized. Call initialize() first")
        }
    }
}

/**
 * Platform-specific singleton instance
 */
expect object RunAnywhere : BaseRunAnywhereSDK
