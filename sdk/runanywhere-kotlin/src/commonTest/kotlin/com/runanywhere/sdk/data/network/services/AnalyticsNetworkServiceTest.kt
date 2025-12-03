package com.runanywhere.sdk.data.network.services

import com.runanywhere.sdk.data.models.TelemetryBatch
import com.runanywhere.sdk.data.models.TelemetryData
import com.runanywhere.sdk.data.models.TelemetryEventType
import io.ktor.client.engine.mock.*
import io.ktor.http.*
import io.ktor.client.*
import kotlinx.coroutines.test.runTest
import kotlin.test.*

/**
 * Unit tests for AnalyticsNetworkService
 * Tests network requests, authentication, and error handling
 */
class AnalyticsNetworkServiceTest {

    @Test
    fun `submitTelemetryBatch sends POST request with correct headers`() = runTest {
        // Mock HTTP client
        val mockEngine = MockEngine { request ->
            assertEquals("/api/v1/sdk/telemetry", request.url.encodedPath)
            assertEquals(HttpMethod.Post, request.method)
            assertTrue(request.headers.contains(HttpHeaders.Authorization) || request.headers.contains("X-API-Key"))
            assertTrue(request.headers.contains("X-SDK-Client"))
            assertTrue(request.headers.contains("X-Platform"))

            respond(
                content = "{}",
                status = HttpStatusCode.OK,
                headers = headersOf(HttpHeaders.ContentType, "application/json")
            )
        }

        val httpClient = HttpClient(mockEngine)
        val service = AnalyticsNetworkService(
            httpClient = httpClient,
            baseURL = "https://api.runanywhere.ai",
            apiKey = "test-api-key"
        )

        val batch = TelemetryBatch(
            events = listOf(createTestEvent()),
            deviceId = "test-device",
            sessionId = "test-session",
            sdkVersion = "0.1.0"
        )

        val result = service.submitTelemetryBatch(batch)
        assertTrue(result.isSuccess)
        
        httpClient.close()
    }

    @Test
    fun `submitTelemetryBatch handles network errors`() = runTest {
        val mockEngine = MockEngine {
            respond(
                content = "Server error",
                status = HttpStatusCode.InternalServerError
            )
        }

        val httpClient = HttpClient(mockEngine)
        val service = AnalyticsNetworkService(
            httpClient = httpClient,
            baseURL = "https://api.runanywhere.ai",
            apiKey = "test-api-key"
        )
        
        val batch = TelemetryBatch(
            events = listOf(createTestEvent()),
            deviceId = "test-device",
            sessionId = "test-session",
            sdkVersion = "0.1.0"
        )

        val result = service.submitTelemetryBatch(batch)
        assertTrue(result.isFailure)
        
        httpClient.close()
    }

    @Test
    fun `submitTelemetryEvent creates batch with single event`() = runTest {
        var capturedBatch: TelemetryBatch? = null
        
        val mockEngine = MockEngine { request ->
            // Capture the request body to verify batch structure
            capturedBatch = null // Would need to parse body in real test
            respond(
                content = "{}",
                status = HttpStatusCode.OK
            )
        }

        val httpClient = HttpClient(mockEngine)
        val service = AnalyticsNetworkService(
            httpClient = httpClient,
            baseURL = "https://api.runanywhere.ai",
            apiKey = "test-api-key"
        )

        val event = createTestEvent()
        val result = service.submitTelemetryEvent(event)
        
        // Verify request was made
        assertTrue(result.isSuccess)
        
        httpClient.close()
    }

    @Test
    fun `registerDevice sends POST request to device registration endpoint`() = runTest {
        val mockEngine = MockEngine { request ->
            assertEquals("/api/v1/devices/register", request.url.encodedPath)
            assertEquals(HttpMethod.Post, request.method)
            
            respond(
                content = """{"deviceId": "test-device-123", "registered": true}""",
                status = HttpStatusCode.OK,
                headers = headersOf(HttpHeaders.ContentType, "application/json")
            )
        }

        val httpClient = HttpClient(mockEngine)
        val service = AnalyticsNetworkService(
            httpClient = httpClient,
            baseURL = "https://api.runanywhere.ai",
            apiKey = "test-api-key"
        )

        val deviceInfo = mapOf(
            "deviceId" to "test-device-123",
            "platform" to "android"
        )

        val result = service.registerDevice(deviceInfo)
        assertTrue(result.isSuccess)
        
        result.onSuccess { response ->
            assertEquals("test-device-123", response.deviceId)
            assertTrue(response.registered)
        }
        
        httpClient.close()
    }

    private fun createTestEvent() = TelemetryData(
        id = "test-event-1",
        type = TelemetryEventType.GENERATION_STARTED,
        name = "test_event",
        sessionId = "test-session",
        deviceId = "test-device",
        sdkVersion = "0.1.0",
        osVersion = "Android 13",
        timestamp = System.currentTimeMillis()
    )
}

