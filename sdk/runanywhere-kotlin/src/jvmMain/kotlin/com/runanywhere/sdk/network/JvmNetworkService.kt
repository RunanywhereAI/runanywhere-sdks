package com.runanywhere.sdk.network

import com.runanywhere.sdk.data.models.ConfigurationData
import com.runanywhere.sdk.data.models.SDKEnvironment
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.enums.LLMFramework
import com.runanywhere.sdk.models.enums.ModelCategory
import com.runanywhere.sdk.models.enums.ModelFormat
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

/**
 * JVM implementation of network service for real API calls
 * Handles communication with RunAnywhere backend services
 */
class JvmNetworkService {
    private val logger = SDKLogger("JvmNetworkService")

    companion object {
        private const val DEFAULT_BASE_URL = "https://api.runanywhere.ai"
        private const val CONNECTION_TIMEOUT = 30_000
        private const val READ_TIMEOUT = 30_000
    }

    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
    }

    private var baseURL: String = DEFAULT_BASE_URL
    private var apiKey: String? = null
    private var accessToken: String? = null
    private var refreshToken: String? = null
    private var deviceId: String? = null

    /**
     * Initialize the network service
     */
    fun initialize(apiKey: String, baseURL: String? = null) {
        this.apiKey = apiKey
        this.baseURL = baseURL ?: DEFAULT_BASE_URL
        logger.info("Initialized JvmNetworkService with base URL: ${this.baseURL}")
    }

    /**
     * Complete authentication and device registration flow
     * This should be called during SDK initialization
     */
    suspend fun authenticateAndRegister(): Boolean = withContext(Dispatchers.IO) {
        try {
            logger.info("Starting RunAnywhere API authentication and registration flow...")

            // Step 1: Authenticate with API key
            if (!authenticateSDK()) {
                logger.error("SDK authentication failed")
                return@withContext false
            }

            // Step 2: Register device
            if (!registerDevice()) {
                logger.error("Device registration failed")
                return@withContext false
            }

            logger.info("✅ Authentication and registration completed successfully")
            return@withContext true

        } catch (e: Exception) {
            logger.error("Error during authentication and registration flow", e)
            return@withContext false
        }
    }

    /**
     * Step 1: Authenticate SDK with API key
     * POST /api/v1/auth/sdk/authenticate
     */
    private suspend fun authenticateSDK(): Boolean {
        try {
            logger.info("Authenticating SDK with RunAnywhere API...")

            val url = URL("$baseURL/api/v1/auth/sdk/authenticate")
            val requestBody = json.encodeToString(
                AuthenticateRequest.serializer(),
                AuthenticateRequest(apiKey = apiKey ?: "")
            )

            val response = makeRequest(url, "POST", requestBody)

            if (response.isSuccessful) {
                val authResponse = json.decodeFromString<AuthenticateResponse>(response.body)

                // Store tokens
                accessToken = authResponse.accessToken
                refreshToken = authResponse.refreshToken

                logger.info("✅ SDK authenticated successfully")
                return true
            } else {
                logger.error("❌ SDK authentication failed: HTTP ${response.code} - ${response.body}")
                return false
            }

        } catch (e: Exception) {
            logger.error("❌ Error during SDK authentication", e)
            return false
        }
    }

    /**
     * Step 2: Register device with RunAnywhere backend
     * POST /api/v1/devices/register
     */
    private suspend fun registerDevice(): Boolean {
        try {
            if (accessToken == null) {
                logger.error("Cannot register device: no access token available")
                return false
            }

            logger.info("Registering device with RunAnywhere backend...")

            val url = URL("$baseURL/api/v1/devices/register")
            val deviceInfo = getDeviceInfo()
            val requestBody = json.encodeToString(
                DeviceRegistrationRequest.serializer(),
                DeviceRegistrationRequest(
                    deviceName = deviceInfo["device_name"] as String? ?: "Unknown",
                    platform = deviceInfo["platform"] as String? ?: "JVM",
                    osVersion = deviceInfo["os_version"] as String? ?: "Unknown",
                    architecture = deviceInfo["os_arch"] as String? ?: "Unknown",
                    metadata = deviceInfo.mapValues { it.value.toString() }
                )
            )

            val response = makeAuthenticatedRequest(url, "POST", requestBody)

            if (response.isSuccessful) {
                val deviceResponse = json.decodeFromString<DeviceRegistrationResponse>(response.body)

                // Store device ID
                deviceId = deviceResponse.deviceId

                logger.info("✅ Device registered successfully: ${deviceResponse.deviceId}")
                return true
            } else {
                logger.error("❌ Device registration failed: HTTP ${response.code} - ${response.body}")
                return false
            }

        } catch (e: Exception) {
            logger.error("❌ Error during device registration", e)
            return false
        }
    }

    /**
     * Refresh access token using refresh token
     * POST /api/v1/auth/sdk/refresh
     */
    suspend fun refreshAccessToken(): Boolean = withContext(Dispatchers.IO) {
        try {
            if (refreshToken == null) {
                logger.warn("No refresh token available")
                return@withContext false
            }

            logger.info("Refreshing access token...")

            val url = URL("$baseURL/api/v1/auth/sdk/refresh")
            val requestBody = json.encodeToString(
                RefreshTokenRequest.serializer(),
                RefreshTokenRequest(refreshToken = refreshToken!!)
            )

            val response = makeRequest(url, "POST", requestBody)

            if (response.isSuccessful) {
                val refreshResponse = json.decodeFromString<RefreshTokenResponse>(response.body)

                // Update tokens
                accessToken = refreshResponse.accessToken
                if (refreshResponse.refreshToken != null) {
                    refreshToken = refreshResponse.refreshToken
                }

                logger.info("✅ Access token refreshed successfully")
                return@withContext true
            } else {
                logger.error("❌ Token refresh failed: HTTP ${response.code} - ${response.body}")
                return@withContext false
            }

        } catch (e: Exception) {
            logger.error("❌ Error refreshing access token", e)
            return@withContext false
        }
    }

    /**
     * Fetch available models from the API
     */
    suspend fun fetchModels(): List<ModelInfo> = withContext(Dispatchers.IO) {
        try {
            logger.info("Fetching available models from API")

            val url = URL("$baseURL/v1/models")
            val response = makeRequest(url, "GET")

            if (response.isSuccessful) {
                val modelsResponse = json.decodeFromString<ModelsResponse>(response.body)
                logger.info("Fetched ${modelsResponse.models.size} models from API")
                return@withContext modelsResponse.models.map { it.toModelInfo() }
            } else {
                logger.warn("Failed to fetch models, falling back to local models. HTTP ${response.code}: ${response.body}")
                return@withContext getLocalWhisperModels()
            }

        } catch (e: Exception) {
            logger.error("Error fetching models from API, falling back to local models", e)
            return@withContext getLocalWhisperModels()
        }
    }

    /**
     * Fetch configuration from the API
     */
    suspend fun fetchConfiguration(): ConfigurationData = withContext(Dispatchers.IO) {
        try {
            logger.info("Fetching configuration from API")

            val url = URL("$baseURL/v1/config")
            val requestBody = "{\"client_type\":\"jvm\",\"version\":\"1.0.0\"}"

            val response = makeRequest(url, "POST", requestBody)

            if (response.isSuccessful) {
                val config = json.decodeFromString<ConfigurationResponse>(response.body)
                logger.info("Fetched configuration from API")
                return@withContext config.toConfigurationData()
            } else {
                logger.warn("Failed to fetch configuration, using defaults. HTTP ${response.code}: ${response.body}")
                return@withContext ConfigurationData.default(apiKey ?: "")
            }

        } catch (e: Exception) {
            logger.error("Error fetching configuration, using defaults", e)
            return@withContext ConfigurationData.default(apiKey ?: "")
        }
    }

    /**
     * Report analytics data to the API
     */
    suspend fun reportAnalytics(analyticsData: AnalyticsData): Boolean = withContext(Dispatchers.IO) {
        try {
            logger.debug("Reporting analytics data")

            val url = URL("$baseURL/v1/analytics")
            val requestBody = json.encodeToString(AnalyticsData.serializer(), analyticsData)

            val response = makeRequest(url, "POST", requestBody)

            if (response.isSuccessful) {
                logger.debug("Analytics data reported successfully")
                return@withContext true
            } else {
                logger.warn("Failed to report analytics: HTTP ${response.code}: ${response.body}")
                return@withContext false
            }

        } catch (e: Exception) {
            logger.error("Error reporting analytics", e)
            return@withContext false
        }
    }

    /**
     * Make authenticated HTTP request
     */
    private fun makeAuthenticatedRequest(url: URL, method: String, body: String? = null): HttpResponse {
        return makeRequest(url, method, body, true)
    }

    /**
     * Make HTTP request with proper headers and authentication
     */
    private fun makeRequest(url: URL, method: String, body: String? = null, authenticated: Boolean = false): HttpResponse {
        val connection = url.openConnection() as HttpURLConnection

        try {
            // Configure connection
            connection.requestMethod = method
            connection.connectTimeout = CONNECTION_TIMEOUT
            connection.readTimeout = READ_TIMEOUT
            connection.setRequestProperty("Content-Type", "application/json")
            connection.setRequestProperty("User-Agent", "RunAnywhere-SDK-JVM/1.0")

            // Add authentication if required
            if (authenticated && accessToken != null) {
                connection.setRequestProperty("Authorization", "Bearer $accessToken")
            } else if (!authenticated && apiKey != null) {
                // For non-authenticated requests, still add API key if available
                connection.setRequestProperty("Authorization", "Bearer $apiKey")
            }

            // Add body for POST/PUT requests
            if (body != null && (method == "POST" || method == "PUT")) {
                connection.doOutput = true
                connection.outputStream.use { outputStream ->
                    outputStream.write(body.toByteArray())
                }
            }

            // Get response
            val responseCode = connection.responseCode
            val responseBody = if (responseCode in 200..299) {
                connection.inputStream.bufferedReader().use { it.readText() }
            } else {
                connection.errorStream?.bufferedReader()?.use { it.readText() } ?: ""
            }

            return HttpResponse(responseCode, responseBody)

        } finally {
            connection.disconnect()
        }
    }

    /**
     * Get default Whisper base model
     */
    private fun getLocalWhisperModels(): List<ModelInfo> {
        return listOf(
            // Whisper Base - Default model
            ModelInfo(
                id = "whisper-base",
                name = "Whisper Base",
                category = ModelCategory.SPEECH_RECOGNITION,
                format = ModelFormat.BIN,
                downloadURL = "https://huggingface.co/argmaxinc/whisperkit-coreml/resolve/main/openai_whisper-base/AudioEncoder.mlmodelc.zip",
                localPath = null,
                downloadSize = 74_000_000L, // ~74MB
                memoryRequired = 74_000_000L, // 74MB
                compatibleFrameworks = listOf(LLMFramework.WHISPER_CPP, LLMFramework.WHISPER_KIT),
                preferredFramework = LLMFramework.WHISPER_CPP,
                contextLength = 0,
                supportsThinking = false
            )
        )
    }

    /**
     * Get device information for telemetry
     */
    private fun getDeviceInfo(): Map<String, Any> {
        return mapOf(
            "device_name" to (System.getProperty("user.name") + "-" + System.getProperty("os.name")),
            "platform" to "JVM",
            "java_version" to System.getProperty("java.version"),
            "os_name" to System.getProperty("os.name"),
            "os_version" to System.getProperty("os.version"),
            "os_arch" to System.getProperty("os.arch"),
            "available_processors" to Runtime.getRuntime().availableProcessors(),
            "max_memory" to Runtime.getRuntime().maxMemory(),
            "total_memory" to Runtime.getRuntime().totalMemory()
        )
    }

    // Minimal data classes for auth flow

    @Serializable
    data class AuthenticateRequest(val apiKey: String)

    @Serializable
    data class AuthenticateResponse(
        val accessToken: String,
        val refreshToken: String,
        val expiresIn: Int
    )

    @Serializable
    data class RefreshTokenRequest(val refreshToken: String)

    @Serializable
    data class RefreshTokenResponse(
        val accessToken: String,
        val refreshToken: String? = null
    )

    @Serializable
    data class DeviceRegistrationRequest(
        val deviceName: String,
        val platform: String,
        val osVersion: String,
        val architecture: String,
        val metadata: Map<String, String>
    )

    @Serializable
    data class DeviceRegistrationResponse(
        val deviceId: String,
        val status: String
    )

    @Serializable
    data class DeviceStatusUpdate(val status: String)

    // Legacy data classes for existing functionality
    @Serializable
    private data class ModelsResponse(
        val models: List<ApiModelInfo>
    )

    @Serializable
    private data class ApiModelInfo(
        val id: String,
        val name: String,
        val category: String,
        val format: String,
        val downloadURL: String?,
        val downloadSize: Int,
        val memoryRequired: Int,
        val frameworks: List<String>
    ) {
        fun toModelInfo(): ModelInfo {
            return ModelInfo(
                id = id,
                name = name,
                category = ModelCategory.valueOf(category),
                format = ModelFormat.valueOf(format),
                downloadURL = downloadURL,
                localPath = null,
                downloadSize = downloadSize.toLong(),
                memoryRequired = memoryRequired.toLong(),
                compatibleFrameworks = frameworks.mapNotNull {
                    try { LLMFramework.valueOf(it) } catch (e: Exception) { null }
                },
                preferredFramework = frameworks.firstNotNullOfOrNull {
                    try { LLMFramework.valueOf(it) } catch (e: Exception) { null }
                } ?: LLMFramework.WHISPER_CPP,
                contextLength = 0,
                supportsThinking = false
            )
        }
    }

    @Serializable
    private data class ConfigurationResponse(
        val apiKey: String,
        val environment: String,
        val baseURL: String = "https://api.runanywhere.ai"
    ) {
        fun toConfigurationData(): ConfigurationData {
            return ConfigurationData.default(apiKey)
        }
    }

    @Serializable
    data class AnalyticsData(
        val eventType: String,
        val timestamp: Long,
        val properties: Map<String, String>
    )

    private data class HttpResponse(
        val code: Int,
        val body: String
    ) {
        val isSuccessful: Boolean
            get() = code in 200..299
    }
}
