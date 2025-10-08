package com.runanywhere.sdk.data.network

import com.runanywhere.sdk.data.network.models.APIEndpoint
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.network.HttpClient
import com.runanywhere.sdk.network.HttpResponse
import com.runanywhere.sdk.services.AuthenticationService
import kotlinx.coroutines.test.runTest
import kotlin.test.*

/**
 * Test suite for RealNetworkService
 * Verifies that real networking calls work correctly with proper error handling
 */
class RealNetworkServiceTest {

    private lateinit var mockHttpClient: MockHttpClient
    private lateinit var mockAuthService: MockAuthenticationService
    private lateinit var networkService: RealNetworkService

    @BeforeTest
    fun setup() {
        mockHttpClient = MockHttpClient()
        mockAuthService = MockAuthenticationService()
        networkService = RealNetworkService(
            httpClient = mockHttpClient,
            baseURL = "https://api.runanywhere.ai",
            authenticationService = mockAuthService,
            maxRetryAttempts = 3,
            baseDelayMs = 100 // Fast retries for testing
        )
    }

    @Test
    fun `should make successful GET request`() = runTest {
        // Arrange
        val endpoint = APIEndpoint.models
        val expectedResponse = """{"models": []}"""
        mockHttpClient.setResponse(HttpResponse(200, expectedResponse.encodeToByteArray()))
        mockAuthService.setAccessToken("test-token")

        // Act
        val result = networkService.getRaw(endpoint, requiresAuth = true)

        // Assert
        assertEquals(expectedResponse, result.decodeToString())
        assertEquals("GET", mockHttpClient.lastRequest?.method)
        assertTrue(mockHttpClient.lastRequest?.headers?.get("Authorization")?.contains("Bearer test-token") == true)
    }

    @Test
    fun `should make successful POST request`() = runTest {
        // Arrange
        val endpoint = APIEndpoint.telemetry
        val payload = """{"event": "test"}""".encodeToByteArray()
        val expectedResponse = """{"success": true}"""
        mockHttpClient.setResponse(HttpResponse(200, expectedResponse.encodeToByteArray()))
        mockAuthService.setAccessToken("test-token")

        // Act
        val result = networkService.postRaw(endpoint, payload, requiresAuth = true)

        // Assert
        assertEquals(expectedResponse, result.decodeToString())
        assertEquals("POST", mockHttpClient.lastRequest?.method)
        assertTrue(mockHttpClient.lastRequest?.body?.contentEquals(payload) == true)
    }

    @Test
    fun `should skip auth header for authentication endpoints`() = runTest {
        // Arrange
        val endpoint = APIEndpoint.authenticate
        val payload = """{"apiKey": "test"}""".encodeToByteArray()
        mockHttpClient.setResponse(HttpResponse(200, """{"token": "abc"}""".encodeToByteArray()))

        // Act
        networkService.postRaw(endpoint, payload, requiresAuth = true)

        // Assert
        assertNull(mockHttpClient.lastRequest?.headers?.get("Authorization"))
    }

    @Test
    fun `should retry on server errors`() = runTest {
        // Arrange
        val endpoint = APIEndpoint.models
        mockAuthService.setAccessToken("test-token")

        // First call fails with 503, second succeeds
        mockHttpClient.setResponses(
            HttpResponse(503, "Service Unavailable".encodeToByteArray()),
            HttpResponse(200, """{"models": []}""".encodeToByteArray())
        )

        // Act
        val result = networkService.getRaw(endpoint, requiresAuth = true)

        // Assert
        assertEquals("""{"models": []}""", result.decodeToString())
        assertEquals(2, mockHttpClient.callCount)
    }

    @Test
    fun `should not retry on client errors`() = runTest {
        // Arrange
        val endpoint = APIEndpoint.models
        mockAuthService.setAccessToken("test-token")
        mockHttpClient.setResponse(HttpResponse(404, "Not Found".encodeToByteArray()))

        // Act & Assert
        assertFailsWith<SDKError.NetworkError> {
            networkService.getRaw(endpoint, requiresAuth = true)
        }
        assertEquals(1, mockHttpClient.callCount) // No retries for 404
    }

    @Test
    fun `should throw authentication error when no token available`() = runTest {
        // Arrange
        val endpoint = APIEndpoint.models
        mockAuthService.setAccessToken(null) // No token available

        // Act & Assert
        assertFailsWith<SDKError.InvalidAPIKey> {
            networkService.getRaw(endpoint, requiresAuth = true)
        }
    }

    @Test
    fun `should handle authentication failure response`() = runTest {
        // Arrange
        val endpoint = APIEndpoint.models
        mockAuthService.setAccessToken("invalid-token")
        mockHttpClient.setResponse(HttpResponse(401, "Unauthorized".encodeToByteArray()))

        // Act & Assert
        val exception = assertFailsWith<SDKError.InvalidAPIKey> {
            networkService.getRaw(endpoint, requiresAuth = true)
        }
        assertTrue(exception.message?.contains("Authentication failed") == true)
    }

    @Test
    fun `should build correct URLs`() = runTest {
        // Arrange
        val endpoint = APIEndpoint.models
        mockHttpClient.setResponse(HttpResponse(200, "{}".encodeToByteArray()))
        mockAuthService.setAccessToken("test-token")

        // Act
        networkService.getRaw(endpoint, requiresAuth = true)

        // Assert
        assertEquals("https://api.runanywhere.ai${endpoint.url}", mockHttpClient.lastRequest?.url)
    }

    @Test
    fun `should set correct headers`() = runTest {
        // Arrange
        val endpoint = APIEndpoint.models
        mockHttpClient.setResponse(HttpResponse(200, "{}".encodeToByteArray()))
        mockAuthService.setAccessToken("test-token")

        // Act
        networkService.getRaw(endpoint, requiresAuth = true)

        // Assert
        val headers = mockHttpClient.lastRequest?.headers ?: fail("No headers found")
        assertEquals("application/json", headers["Accept"])
        assertEquals("RunAnywhere-Kotlin-SDK/0.1.0", headers["User-Agent"])
        assertEquals("RunAnywhereKotlinSDK", headers["X-SDK-Client"])
        assertEquals("Bearer test-token", headers["Authorization"])
    }
}

/**
 * Mock HTTP client for testing
 */
class MockHttpClient : HttpClient {
    private val responses = mutableListOf<HttpResponse>()
    private var responseIndex = 0

    var lastRequest: MockRequest? = null
        private set

    var callCount = 0
        private set

    fun setResponse(response: HttpResponse) {
        responses.clear()
        responses.add(response)
        responseIndex = 0
    }

    fun setResponses(vararg responses: HttpResponse) {
        this.responses.clear()
        this.responses.addAll(responses)
        responseIndex = 0
    }

    override suspend fun get(url: String, headers: Map<String, String>): HttpResponse {
        lastRequest = MockRequest("GET", url, headers, null)
        callCount++
        return getNextResponse()
    }

    override suspend fun post(url: String, body: ByteArray, headers: Map<String, String>): HttpResponse {
        lastRequest = MockRequest("POST", url, headers, body)
        callCount++
        return getNextResponse()
    }

    override suspend fun put(url: String, body: ByteArray, headers: Map<String, String>): HttpResponse {
        lastRequest = MockRequest("PUT", url, headers, body)
        callCount++
        return getNextResponse()
    }

    override suspend fun delete(url: String, headers: Map<String, String>): HttpResponse {
        lastRequest = MockRequest("DELETE", url, headers, null)
        callCount++
        return getNextResponse()
    }

    override suspend fun download(
        url: String,
        headers: Map<String, String>,
        onProgress: ((bytesDownloaded: Long, totalBytes: Long) -> Unit)?
    ): ByteArray {
        lastRequest = MockRequest("GET", url, headers, null)
        callCount++
        val response = getNextResponse()
        onProgress?.invoke(response.body.size.toLong(), response.body.size.toLong())
        return response.body
    }

    override suspend fun upload(
        url: String,
        data: ByteArray,
        headers: Map<String, String>,
        onProgress: ((bytesUploaded: Long, totalBytes: Long) -> Unit)?
    ): HttpResponse {
        lastRequest = MockRequest("POST", url, headers, data)
        callCount++
        onProgress?.invoke(data.size.toLong(), data.size.toLong())
        return getNextResponse()
    }

    override fun setDefaultTimeout(timeoutMillis: Long) {
        // No-op for mock
    }

    override fun setDefaultHeaders(headers: Map<String, String>) {
        // No-op for mock
    }

    private fun getNextResponse(): HttpResponse {
        if (responses.isEmpty()) {
            return HttpResponse(500, "No mock response configured".encodeToByteArray())
        }

        val response = responses[responseIndex.coerceAtMost(responses.size - 1)]
        if (responseIndex < responses.size - 1) {
            responseIndex++
        }
        return response
    }
}

/**
 * Mock request data for verification
 */
data class MockRequest(
    val method: String,
    val url: String,
    val headers: Map<String, String>,
    val body: ByteArray?
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is MockRequest) return false
        return method == other.method &&
                url == other.url &&
                headers == other.headers &&
                body?.contentEquals(other.body ?: ByteArray(0)) == true
    }

    override fun hashCode(): Int {
        var result = method.hashCode()
        result = 31 * result + url.hashCode()
        result = 31 * result + headers.hashCode()
        result = 31 * result + (body?.contentHashCode() ?: 0)
        return result
    }
}

/**
 * Mock authentication service for testing
 */
class MockAuthenticationService : AuthenticationService {
    private var accessToken: String? = null

    fun setAccessToken(token: String?) {
        this.accessToken = token
    }

    override suspend fun getAccessToken(): String {
        return accessToken ?: throw SDKError.InvalidAPIKey("No access token available")
    }

    // Other methods not needed for this test
    override suspend fun authenticate(apiKey: String) = throw NotImplementedError()
    override suspend fun healthCheck() = throw NotImplementedError()
    override fun isAuthenticated() = accessToken != null
    override fun getDeviceId() = null
    override fun getOrganizationId() = null
    override fun getUserId() = null
    override suspend fun clearAuthentication() = Unit
    override suspend fun loadStoredTokens() = Unit
}
