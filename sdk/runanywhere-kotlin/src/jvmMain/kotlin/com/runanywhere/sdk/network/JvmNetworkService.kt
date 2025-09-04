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

    /**
     * Initialize the network service
     */
    fun initialize(apiKey: String, baseURL: String? = null) {
        this.apiKey = apiKey
        this.baseURL = baseURL ?: DEFAULT_BASE_URL
        logger.info("Initialized JvmNetworkService with base URL: ${this.baseURL}")
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
     * Make HTTP request with proper headers and authentication
     */
    private fun makeRequest(url: URL, method: String, body: String? = null): HttpResponse {
        val connection = url.openConnection() as HttpURLConnection

        try {
            // Configure connection
            connection.requestMethod = method
            connection.connectTimeout = CONNECTION_TIMEOUT
            connection.readTimeout = READ_TIMEOUT
            connection.setRequestProperty("Content-Type", "application/json")
            connection.setRequestProperty("User-Agent", "RunAnywhere-SDK-JVM/1.0")

            // Add authentication if available
            apiKey?.let { key ->
                connection.setRequestProperty("Authorization", "Bearer $key")
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
     * Get local Whisper models as fallback
     */
    private fun getLocalWhisperModels(): List<ModelInfo> {
        return listOf(
            ModelInfo(
                id = "whisper-tiny-en",
                name = "Whisper Tiny English",
                category = ModelCategory.SPEECH_RECOGNITION,
                format = ModelFormat.GGUF,
                downloadURL = "https://huggingface.co/ggml-org/whisper.cpp/resolve/main/ggml-tiny.en.bin",
                localPath = null,
                downloadSize = 39_000_000L, // ~39MB
                memoryRequired = 50_000_000L, // 50MB
                compatibleFrameworks = listOf(LLMFramework.WHISPER_CPP),
                preferredFramework = LLMFramework.WHISPER_CPP,
                contextLength = 0,
                supportsThinking = false
            ),
            ModelInfo(
                id = "whisper-base-en",
                name = "Whisper Base English",
                category = ModelCategory.SPEECH_RECOGNITION,
                format = ModelFormat.GGUF,
                downloadURL = "https://huggingface.co/ggml-org/whisper.cpp/resolve/main/ggml-base.en.bin",
                localPath = null,
                downloadSize = 142_000_000L, // ~142MB
                memoryRequired = 200_000_000L, // 200MB
                compatibleFrameworks = listOf(LLMFramework.WHISPER_CPP),
                preferredFramework = LLMFramework.WHISPER_CPP,
                contextLength = 0,
                supportsThinking = false
            ),
            ModelInfo(
                id = "whisper-small-en",
                name = "Whisper Small English",
                category = ModelCategory.SPEECH_RECOGNITION,
                format = ModelFormat.GGUF,
                downloadURL = "https://huggingface.co/ggml-org/whisper.cpp/resolve/main/ggml-small.en.bin",
                localPath = null,
                downloadSize = 488_000_000L, // ~488MB
                memoryRequired = 600_000_000L, // 600MB
                compatibleFrameworks = listOf(LLMFramework.WHISPER_CPP),
                preferredFramework = LLMFramework.WHISPER_CPP,
                contextLength = 0,
                supportsThinking = false
            )
        )
    }

    // Data classes for API responses

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
