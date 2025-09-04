package com.runanywhere.sdk.public

import com.runanywhere.sdk.data.models.SDKEnvironment
import com.runanywhere.sdk.data.models.ConfigurationData
import com.runanywhere.sdk.data.models.ModelInfo
import kotlinx.coroutines.flow.Flow

/**
 * Main public API interface for RunAnywhere SDK
 * Common logic stays here, platform-specific implementations in actual
 */
interface RunAnywhereSDK {
    val isInitialized: Boolean
    val currentEnvironment: SDKEnvironment

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
 */
abstract class BaseRunAnywhereSDK : RunAnywhereSDK {
    protected var _isInitialized = false
    protected var _currentEnvironment: SDKEnvironment = SDKEnvironment.DEVELOPMENT

    override val isInitialized: Boolean
        get() = _isInitialized

    override val currentEnvironment: SDKEnvironment
        get() = _currentEnvironment

    override suspend fun initialize(
        apiKey: String,
        baseURL: String?,
        environment: SDKEnvironment
    ) {
        if (_isInitialized) {
            println("SDK already initialized")
            return
        }

        _currentEnvironment = environment

        // Call platform-specific initialization
        initializePlatform(apiKey, baseURL, environment)

        // Common initialization logic
        initializeCommonServices()

        _isInitialized = true
        println("SDK initialized successfully in ${environment.name} mode")
    }

    /**
     * Platform-specific initialization to be implemented
     */
    protected abstract suspend fun initializePlatform(
        apiKey: String,
        baseURL: String?,
        environment: SDKEnvironment
    )

    /**
     * Common services initialization
     */
    private fun initializeCommonServices() {
        // Initialize event bus, analytics, etc.
        // Common logic that applies to all platforms
    }

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
