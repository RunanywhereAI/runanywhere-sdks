package com.runanywhere.sdk.data.network

import com.runanywhere.sdk.data.models.SDKEnvironment
import com.runanywhere.sdk.data.network.models.APIEndpoint
import kotlinx.coroutines.test.runTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotNull
import kotlin.test.assertNotSame
import kotlin.test.assertSame
import kotlin.test.assertTrue

/**
 * Integration test for networking components
 * Tests the complete networking stack including factory, circuit breakers, and real services
 */
class NetworkIntegrationTest {
    @BeforeTest
    fun setup() {
        // Reset circuit breakers before each test
        runTest {
            CircuitBreakerRegistry.resetAll()
        }
    }

    @Test
    fun `should create mock network service for development environment`() {
        // Act
        val networkService =
            NetworkServiceFactory.create(
                environment = SDKEnvironment.DEVELOPMENT,
            )

        // Assert
        assertTrue(networkService is MockNetworkService)
    }

    @Test
    fun `should create real network service for production environment`() {
        // Act
        assertFailsWith<IllegalArgumentException> {
            NetworkServiceFactory.create(
                environment = SDKEnvironment.PRODUCTION,
            )
        }
    }

    @Test
    fun `should create real network service with proper configuration`() {
        // Act
        val networkService =
            NetworkServiceFactory.create(
                environment = SDKEnvironment.PRODUCTION,
                baseURL = "https://api.test.com",
                apiKey = "test-api-key",
            )

        // Assert
        assertTrue(networkService is CircuitBreakerNetworkService)
    }

    @Test
    fun `should make mock requests successfully in development mode`() =
        runTest {
            // Arrange
            val networkService =
                NetworkServiceFactory.create(
                    environment = SDKEnvironment.DEVELOPMENT,
                )

            // Act
            val result = networkService.getRaw(APIEndpoint.models, requiresAuth = false)

            // Assert
            assertTrue(result.isNotEmpty())
            val responseString = result.decodeToString()
            assertTrue(responseString.contains("models"))
        }

    @Test
    fun `circuit breaker should be created and accessible`() =
        runTest {
            // Arrange
            val networkService =
                NetworkServiceFactory.create(
                    environment = SDKEnvironment.STAGING,
                    baseURL = "https://staging.api.test.com",
                    apiKey = "test-api-key",
                ) as CircuitBreakerNetworkService

            // Act
            val status = networkService.getCircuitBreakerStatus()

            // Assert
            assertEquals(com.runanywhere.sdk.network.CircuitBreakerState.CLOSED, status.state)
            assertEquals(0, status.failureCount)
            assertTrue(status.isHealthy)
        }

    @Test
    fun `should handle different API endpoints correctly`() =
        runTest {
            // Arrange
            val networkService =
                NetworkServiceFactory.create(
                    environment = SDKEnvironment.DEVELOPMENT,
                )

            // Act & Assert - Test various endpoints
            assertNotNull(networkService.getRaw(APIEndpoint.models, requiresAuth = false))
            assertNotNull(networkService.getRaw(APIEndpoint.configuration, requiresAuth = false))
            assertNotNull(networkService.getRaw(APIEndpoint.healthCheck, requiresAuth = false))

            // Telemetry should accept POST requests
            val telemetryPayload = """{"event": "test"}""".encodeToByteArray()
            val telemetryResult = networkService.postRaw(APIEndpoint.telemetry, telemetryPayload, requiresAuth = false)
            assertNotNull(telemetryResult)
        }

    @Test
    fun `circuit breaker registry should track multiple services`() =
        runTest {
            // Arrange & Act
            val circuitBreaker1 = CircuitBreakerRegistry.getOrCreate("service1")
            val circuitBreaker2 = CircuitBreakerRegistry.getOrCreate("service2")
            val circuitBreaker1Again = CircuitBreakerRegistry.getOrCreate("service1")

            // Assert
            assertSame(circuitBreaker1, circuitBreaker1Again) // Should reuse existing instance
            assertNotSame(circuitBreaker1, circuitBreaker2) // Should be different instances

            val allStatuses = CircuitBreakerRegistry.getAllStatuses()
            assertTrue(allStatuses.containsKey("service1"))
            assertTrue(allStatuses.containsKey("service2"))
        }

    @Test
    fun `network service factory should validate required parameters`() {
        // Test missing API key for production
        assertFailsWith<IllegalArgumentException> {
            NetworkServiceFactory.create(
                environment = SDKEnvironment.PRODUCTION,
                baseURL = "https://api.test.com",
                // Missing apiKey
            )
        }

        // Test missing base URL for production
        assertFailsWith<IllegalArgumentException> {
            NetworkServiceFactory.create(
                environment = SDKEnvironment.PRODUCTION,
                apiKey = "test-key",
                // Missing baseURL - should fail when SDK config is not initialized
            )
        }
    }

    @Test
    fun `should create different network configurations for different environments`() {
        // Arrange & Act
        val devService = NetworkServiceFactory.create(SDKEnvironment.DEVELOPMENT)
        val stagingService =
            NetworkServiceFactory.create(
                SDKEnvironment.STAGING,
                baseURL = "https://staging.api.test.com",
                apiKey = "test-key",
            )
        val prodService =
            NetworkServiceFactory.create(
                SDKEnvironment.PRODUCTION,
                baseURL = "https://api.test.com",
                apiKey = "test-key",
            )

        // Assert
        assertTrue(devService is MockNetworkService)
        assertTrue(stagingService is CircuitBreakerNetworkService)
        assertTrue(prodService is CircuitBreakerNetworkService)
    }
}

/**
 * Test for verifying APIEndpoint URL construction
 */
class APIEndpointTest {
    @Test
    fun `should have correct endpoint URLs`() {
        assertEquals("/v1/models", APIEndpoint.models.url)
        assertEquals("/v1/configuration", APIEndpoint.configuration.url)
        assertEquals("/v1/telemetry", APIEndpoint.telemetry.url)
        assertEquals("/v1/health", APIEndpoint.healthCheck.url)
        assertEquals("/v1/device", APIEndpoint.deviceInfo.url)
        assertEquals("/v1/history", APIEndpoint.history.url)
        assertEquals("/v1/preferences", APIEndpoint.preferences.url)
    }

    @Test
    fun `should construct correct authentication URLs`() {
        assertEquals("/api/v1/auth/sdk/authenticate", APIEndpoint.authenticate.url)
        assertEquals("/api/v1/auth/sdk/refresh", APIEndpoint.refreshToken.url)
        assertEquals("/api/v1/devices/register", APIEndpoint.registerDevice.url)
    }
}
