package com.runanywhere.sdk.data.network

import com.runanywhere.sdk.data.models.SDKEnvironment
import com.runanywhere.sdk.data.network.services.MockNetworkService
import com.runanywhere.sdk.data.network.NetworkService
import com.runanywhere.sdk.data.network.NetworkServiceImpl
import com.runanywhere.sdk.data.network.models.APIEndpoint
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.config.SDKConfig
import com.runanywhere.sdk.network.APIClient
import com.runanywhere.sdk.network.NetworkConfiguration
import com.runanywhere.sdk.network.createHttpClient
import com.runanywhere.sdk.services.AuthenticationService

/**
 * Factory for creating the appropriate NetworkService based on the environment
 * Equivalent to iOS NetworkServiceFactory with production APIClient support
 */
object NetworkServiceFactory {

    private val logger = SDKLogger("NetworkServiceFactory")

    /**
     * Create a NetworkService instance based on the SDK environment
     *
     * @param environment SDK environment (DEVELOPMENT, STAGING, PRODUCTION)
     * @param baseURL Base URL for API endpoints (required for STAGING and PRODUCTION)
     * @param apiKey API key for authentication (required for STAGING and PRODUCTION)
     * @param authenticationService Optional authentication service for token management
     * @param networkConfig Custom network configuration (optional)
     */
    fun create(
        environment: SDKEnvironment,
        baseURL: String? = null,
        apiKey: String? = null,
        authenticationService: AuthenticationService? = null,
        networkConfig: NetworkConfiguration? = null
    ): NetworkService {
        logger.info("Creating NetworkService for environment: $environment")

        return when (environment) {
            SDKEnvironment.DEVELOPMENT -> {
                logger.info("🔧 Creating MockNetworkService for DEVELOPMENT environment")
                MockNetworkService()
            }

            SDKEnvironment.STAGING -> {
                logger.info("🚀 Creating Production APIClient for STAGING environment")
                createProductionAPIClient(
                    baseURL = baseURL ?: getDefaultBaseURL(environment),
                    apiKey = apiKey ?: throw IllegalArgumentException("API key is required for STAGING environment"),
                    authenticationService = authenticationService,
                    networkConfig = networkConfig
                )
            }

            SDKEnvironment.PRODUCTION -> {
                logger.info("🚀 Creating Production APIClient for PRODUCTION environment")
                createProductionAPIClient(
                    baseURL = baseURL ?: getDefaultBaseURL(environment),
                    apiKey = apiKey ?: throw IllegalArgumentException("API key is required for PRODUCTION environment"),
                    authenticationService = authenticationService,
                    networkConfig = networkConfig
                )
            }
        }
    }

    /**
     * Create production APIClient with proper configuration
     */
    private fun createProductionAPIClient(
        baseURL: String,
        apiKey: String,
        authenticationService: AuthenticationService?,
        networkConfig: NetworkConfiguration? = null
    ): NetworkService {
        val config = networkConfig ?: when {
            baseURL.contains("staging") -> NetworkConfiguration.development()
            else -> NetworkConfiguration.production()
        }

        val httpClient = createHttpClient(config)

        val apiClient = APIClient(
            baseURL = baseURL,
            apiKey = apiKey,
            httpClient = httpClient,
            authenticationService = authenticationService,
            networkChecker = createNetworkChecker(),
            maxRetryAttempts = config.maxRetryAttempts,
            baseDelayMs = config.baseRetryDelayMs
        )

        // Use the new NetworkServiceImpl that implements all methods including generic types
        return NetworkServiceImpl(apiClient)
    }

    /**
     * Get default base URLs for different environments
     */
    private fun getDefaultBaseURL(environment: SDKEnvironment): String {
        // For open source SDK, baseURL must always be provided
        // Check if it was set during SDK initialization
        return SDKConfig.baseURL.takeIf { it.isNotBlank() }
            ?: throw IllegalArgumentException("Base URL must be provided. Call RunAnywhere.initialize(baseURL = \"your-url\") first.")
    }

    /**
     * Create platform-specific network checker
     */
    private fun createNetworkChecker(): com.runanywhere.sdk.network.NetworkChecker? {
        return try {
            createPlatformNetworkChecker()
        } catch (e: Exception) {
            logger.warn("Failed to create network checker: ${e.message}")
            null
        }
    }
}

/**
 * Platform-specific network checker creation
 */
expect fun createPlatformNetworkChecker(): com.runanywhere.sdk.network.NetworkChecker?
