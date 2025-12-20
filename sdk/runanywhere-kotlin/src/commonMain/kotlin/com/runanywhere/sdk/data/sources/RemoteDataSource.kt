package com.runanywhere.sdk.data.sources

import com.runanywhere.sdk.data.config.RetryConfiguration
import com.runanywhere.sdk.data.config.TimeoutConfiguration
import com.runanywhere.sdk.data.errors.RepositoryError
import com.runanywhere.sdk.data.errors.shouldRetry
import io.ktor.client.*
import io.ktor.client.call.*
import io.ktor.client.plugins.*
import io.ktor.client.plugins.contentnegotiation.*
import io.ktor.client.plugins.logging.*
import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.http.*
import io.ktor.serialization.kotlinx.json.*
import kotlinx.coroutines.delay
import kotlinx.serialization.KSerializer
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.minutes
import kotlin.time.Duration.Companion.seconds

/**
 * Remote data source implementation for network-based operations.
 * Provides HTTP-based CRUD operations with retry logic and error handling.
 */
class HttpRemoteDataSource<T : Any>(
    private val baseUrl: String,
    private val httpClient: HttpClient,
    private val serializer: KSerializer<T>,
    override val configuration: DataSourceConfiguration,
    private val retryConfig: RetryConfiguration = RetryConfiguration(),
    private val timeoutConfig: TimeoutConfiguration = TimeoutConfiguration(),
    private val apiKeyProvider: () -> String? = { null },
) : RemoteDataSource<T> {
    constructor(
        baseUrl: String,
        entityName: String,
        serializer: KSerializer<T>,
        apiKeyProvider: () -> String? = { null },
        retryConfig: RetryConfiguration = RetryConfiguration(),
        timeoutConfig: TimeoutConfiguration = TimeoutConfiguration(),
    ) : this(
        baseUrl = baseUrl,
        httpClient = createDefaultHttpClient(timeoutConfig),
        serializer = serializer,
        configuration =
            DataSourceConfiguration(
                name = "${entityName}RemoteDataSource",
                type = DataSourceType.NETWORK,
                version = "1.0.0",
                capabilities =
                    setOf(
                        DataSourceCapability.CRUD,
                        DataSourceCapability.BATCH_OPERATIONS,
                        DataSourceCapability.SYNC,
                    ),
            ),
        retryConfig = retryConfig,
        timeoutConfig = timeoutConfig,
        apiKeyProvider = apiKeyProvider,
    )

    private val json =
        Json {
            ignoreUnknownKeys = true
            prettyPrint = false
        }

    override suspend fun isAvailable(): Boolean =
        try {
            val response = httpClient.get("$baseUrl/health")
            response.status.isSuccess()
        } catch (e: Exception) {
            false
        }

    override suspend fun healthCheck(): DataSourceHealth =
        try {
            val startTime = System.currentTimeMillis()
            val response = httpClient.get("$baseUrl/health")
            val duration = System.currentTimeMillis() - startTime

            if (response.status.isSuccess()) {
                DataSourceHealth(
                    isHealthy = true,
                    status = HealthStatus.HEALTHY,
                    lastCheckTime = System.currentTimeMillis(),
                    errors = emptyList(),
                    metrics =
                        mapOf(
                            "response_time_ms" to duration,
                            "status_code" to response.status.value,
                        ),
                )
            } else {
                DataSourceHealth(
                    isHealthy = false,
                    status = HealthStatus.DEGRADED,
                    lastCheckTime = System.currentTimeMillis(),
                    errors = listOf("HTTP ${response.status.value}: ${response.status.description}"),
                    metrics =
                        mapOf(
                            "response_time_ms" to duration,
                            "status_code" to response.status.value,
                        ),
                )
            }
        } catch (e: Exception) {
            DataSourceHealth(
                isHealthy = false,
                status = HealthStatus.UNHEALTHY,
                lastCheckTime = System.currentTimeMillis(),
                errors = listOf(e.message ?: "Network error"),
                metrics = emptyMap(),
            )
        }

    override suspend fun fetchRemote(id: String): Result<T?> =
        executeWithRetry {
            try {
                val response =
                    httpClient.get("$baseUrl/entities/$id") {
                        addApiKey()
                    }

                when (response.status) {
                    HttpStatusCode.OK -> {
                        val entity = json.decodeFromString(serializer, response.body())
                        Result.success(entity)
                    }
                    HttpStatusCode.NotFound -> Result.success(null)
                    else ->
                        Result.failure(
                            RepositoryError.NetworkError(
                                operation = "fetchRemote",
                                cause = Exception("HTTP ${response.status.value}: ${response.status.description}"),
                            ),
                        )
                }
            } catch (e: Exception) {
                Result.failure(mapNetworkError(e, "fetchRemote"))
            }
        }

    override suspend fun fetchAllRemote(ids: List<String>): Result<List<T>> =
        executeWithRetry {
            try {
                val response =
                    httpClient.post("$baseUrl/entities/batch") {
                        addApiKey()
                        contentType(ContentType.Application.Json)
                        setBody(json.encodeToString(mapOf("ids" to ids)))
                    }

                if (response.status.isSuccess()) {
                    val entities =
                        json
                            .decodeFromString<List<String>>(response.body())
                            .map { json.decodeFromString(serializer, it) }
                    Result.success(entities)
                } else {
                    Result.failure(
                        RepositoryError.NetworkError(
                            operation = "fetchAllRemote",
                            cause = Exception("HTTP ${response.status.value}: ${response.status.description}"),
                        ),
                    )
                }
            } catch (e: Exception) {
                Result.failure(mapNetworkError(e, "fetchAllRemote"))
            }
        }

    override suspend fun fetchAllRemote(): Result<List<T>> =
        executeWithRetry {
            try {
                val response =
                    httpClient.get("$baseUrl/entities") {
                        addApiKey()
                    }

                if (response.status.isSuccess()) {
                    val entities =
                        json
                            .decodeFromString<List<String>>(response.body())
                            .map { json.decodeFromString(serializer, it) }
                    Result.success(entities)
                } else {
                    Result.failure(
                        RepositoryError.NetworkError(
                            operation = "fetchAllRemote",
                            cause = Exception("HTTP ${response.status.value}: ${response.status.description}"),
                        ),
                    )
                }
            } catch (e: Exception) {
                Result.failure(mapNetworkError(e, "fetchAllRemote"))
            }
        }

    override suspend fun pushRemote(entity: T): Result<T> =
        executeWithRetry {
            try {
                val serializedEntity = json.encodeToString(serializer, entity)
                val response =
                    httpClient.post("$baseUrl/entities") {
                        addApiKey()
                        contentType(ContentType.Application.Json)
                        setBody(serializedEntity)
                    }

                if (response.status.isSuccess()) {
                    val updatedEntity = json.decodeFromString(serializer, response.body())
                    Result.success(updatedEntity)
                } else {
                    Result.failure(
                        RepositoryError.NetworkError(
                            operation = "pushRemote",
                            cause = Exception("HTTP ${response.status.value}: ${response.status.description}"),
                        ),
                    )
                }
            } catch (e: Exception) {
                Result.failure(mapNetworkError(e, "pushRemote"))
            }
        }

    override suspend fun pushAllRemote(entities: List<T>): Result<List<T>> =
        executeWithRetry {
            try {
                val serializedEntities = entities.map { json.encodeToString(serializer, it) }
                val response =
                    httpClient.post("$baseUrl/entities/batch") {
                        addApiKey()
                        contentType(ContentType.Application.Json)
                        setBody(json.encodeToString(serializedEntities))
                    }

                if (response.status.isSuccess()) {
                    val updatedEntities =
                        json
                            .decodeFromString<List<String>>(response.body())
                            .map { json.decodeFromString(serializer, it) }
                    Result.success(updatedEntities)
                } else {
                    Result.failure(
                        RepositoryError.NetworkError(
                            operation = "pushAllRemote",
                            cause = Exception("HTTP ${response.status.value}: ${response.status.description}"),
                        ),
                    )
                }
            } catch (e: Exception) {
                Result.failure(mapNetworkError(e, "pushAllRemote"))
            }
        }

    override suspend fun deleteRemote(id: String): Result<Unit> =
        executeWithRetry {
            try {
                val response =
                    httpClient.delete("$baseUrl/entities/$id") {
                        addApiKey()
                    }

                if (response.status.isSuccess()) {
                    Result.success(Unit)
                } else {
                    Result.failure(
                        RepositoryError.NetworkError(
                            operation = "deleteRemote",
                            cause = Exception("HTTP ${response.status.value}: ${response.status.description}"),
                        ),
                    )
                }
            } catch (e: Exception) {
                Result.failure(mapNetworkError(e, "deleteRemote"))
            }
        }

    override suspend fun sync(localEntities: List<T>): Result<SyncResult<T>> =
        executeWithRetry {
            try {
                // Get local entity IDs for comparison
                val localIds = localEntities.map { extractEntityId(it) }
                val serializedEntities = localEntities.map { json.encodeToString(serializer, it) }

                val syncRequest =
                    mapOf(
                        "localIds" to localIds,
                        "entities" to serializedEntities,
                        "timestamp" to System.currentTimeMillis(),
                    )

                val response =
                    httpClient.post("$baseUrl/sync") {
                        addApiKey()
                        contentType(ContentType.Application.Json)
                        setBody(json.encodeToString(syncRequest))
                    }

                if (response.status.isSuccess()) {
                    val syncResponse = json.decodeFromString<Map<String, Any>>(response.body())

                    val synced =
                        (syncResponse["synced"] as? List<String>)
                            ?.map { json.decodeFromString(serializer, it) } ?: emptyList()

                    val conflicts =
                        (syncResponse["conflicts"] as? List<Map<String, Any>>)
                            ?.mapNotNull { parseConflict(it) } ?: emptyList()

                    val errors =
                        (syncResponse["errors"] as? List<String>)
                            ?.map { RepositoryError.NetworkError("sync", Exception(it)) } ?: emptyList()

                    val statistics = parseSyncStatistics(syncResponse["statistics"] as? Map<String, Any>)

                    Result.success(
                        SyncResult(
                            synced = synced,
                            conflicts = conflicts,
                            errors = errors,
                            statistics = statistics,
                        ),
                    )
                } else {
                    Result.failure(
                        RepositoryError.NetworkError(
                            operation = "sync",
                            cause = Exception("HTTP ${response.status.value}: ${response.status.description}"),
                        ),
                    )
                }
            } catch (e: Exception) {
                Result.failure(mapNetworkError(e, "sync"))
            }
        }

    override suspend fun getNetworkStatus(): Result<NetworkStatus> =
        try {
            val startTime = System.currentTimeMillis()
            val response =
                httpClient.get("$baseUrl/status") {
                    addApiKey()
                }
            val latency = System.currentTimeMillis() - startTime

            Result.success(
                NetworkStatus(
                    isConnected = response.status.isSuccess(),
                    connectionType = ConnectionType.UNKNOWN, // Would need platform-specific detection
                    latency = latency,
                    bandwidth = -1, // Would need network speed test
                ),
            )
        } catch (e: Exception) {
            Result.success(
                NetworkStatus(
                    isConnected = false,
                    connectionType = ConnectionType.NONE,
                    latency = -1,
                    bandwidth = -1,
                ),
            )
        }

    /**
     * Execute operation with retry logic
     */
    private suspend fun <R> executeWithRetry(operation: suspend () -> Result<R>): Result<R> {
        if (!retryConfig.enabled) {
            return operation()
        }

        var lastException: Exception? = null

        repeat(retryConfig.maxAttempts) { attempt ->
            try {
                val result = operation()
                if (result.isSuccess) {
                    return result
                }

                val failure = result.exceptionOrNull()
                if (failure is RepositoryError && failure.shouldRetry()) {
                    if (attempt < retryConfig.maxAttempts - 1) {
                        val delay = retryConfig.calculateDelay(attempt)
                        delay(delay.inWholeMilliseconds)
                        lastException = failure
                        return@repeat
                    }
                }

                return result
            } catch (e: Exception) {
                lastException = e
                if (attempt < retryConfig.maxAttempts - 1) {
                    val delay = retryConfig.calculateDelay(attempt)
                    delay(delay.inWholeMilliseconds)
                }
            }
        }

        return Result.failure(lastException ?: Exception("Operation failed after ${retryConfig.maxAttempts} attempts"))
    }

    /**
     * Add API key to request if available
     */
    private fun HttpRequestBuilder.addApiKey() {
        apiKeyProvider()?.let { apiKey ->
            header("Authorization", "Bearer $apiKey")
        }
    }

    /**
     * Map network exceptions to RepositoryError
     */
    private fun mapNetworkError(
        exception: Exception,
        operation: String,
    ): RepositoryError =
        when (exception) {
            is RepositoryError -> exception
            is HttpRequestTimeoutException ->
                RepositoryError.TimeoutError(
                    operation = operation,
                    timeoutMs = timeoutConfig.total.inWholeMilliseconds,
                )
            else ->
                RepositoryError.NetworkError(
                    operation = operation,
                    cause = exception,
                )
        }

    /**
     * Parse conflict from sync response
     */
    private fun parseConflict(conflictData: Map<String, Any>): SyncConflict<T>? {
        return try {
            val localEntityStr = conflictData["local"] as? String ?: return null
            val remoteEntityStr = conflictData["remote"] as? String ?: return null
            val conflictTypeStr = conflictData["type"] as? String ?: return null

            val localEntity = json.decodeFromString(serializer, localEntityStr)
            val remoteEntity = json.decodeFromString(serializer, remoteEntityStr)
            val conflictType = ConflictType.valueOf(conflictTypeStr)

            SyncConflict(
                localEntity = localEntity,
                remoteEntity = remoteEntity,
                conflictType = conflictType,
                field = conflictData["field"] as? String,
            )
        } catch (e: Exception) {
            null
        }
    }

    /**
     * Parse sync statistics from response
     */
    private fun parseSyncStatistics(statsData: Map<String, Any>?): SyncStatistics =
        if (statsData != null) {
            SyncStatistics(
                totalProcessed = (statsData["totalProcessed"] as? Number)?.toInt() ?: 0,
                successful = (statsData["successful"] as? Number)?.toInt() ?: 0,
                failed = (statsData["failed"] as? Number)?.toInt() ?: 0,
                conflicts = (statsData["conflicts"] as? Number)?.toInt() ?: 0,
                duration = (statsData["duration"] as? Number)?.toLong() ?: 0,
                timestamp = (statsData["timestamp"] as? Number)?.toLong() ?: System.currentTimeMillis(),
            )
        } else {
            SyncStatistics(0, 0, 0, 0, 0, System.currentTimeMillis())
        }

    /**
     * Extract entity ID - this would need to be customized for specific entity types
     */
    private fun extractEntityId(entity: T): String {
        // Similar to LocalDataSource implementation
        val entityClass = entity::class
        val idProperties = listOf("id", "identifier", "key", "uuid")

        for (propertyName in idProperties) {
            try {
                val property = entityClass.members.find { it.name == propertyName }
                if (property != null) {
                    val value = property.call(entity)
                    if (value != null) {
                        return value.toString()
                    }
                }
            } catch (e: Exception) {
                // Continue to next property
            }
        }

        return entity.hashCode().toString()
    }

    companion object {
        /**
         * Create default HTTP client with timeout configuration
         */
        fun createDefaultHttpClient(timeoutConfig: TimeoutConfiguration): HttpClient =
            HttpClient {
                install(ContentNegotiation) {
                    json(
                        Json {
                            ignoreUnknownKeys = true
                            prettyPrint = false
                        },
                    )
                }

                install(HttpTimeout) {
                    requestTimeoutMillis = timeoutConfig.total.inWholeMilliseconds
                    connectTimeoutMillis = timeoutConfig.connect.inWholeMilliseconds
                    socketTimeoutMillis = timeoutConfig.read.inWholeMilliseconds
                }

                install(Logging) {
                    level = LogLevel.INFO
                }
            }
    }
}

/**
 * Factory functions for common remote data source configurations
 */

/**
 * Create a standard HTTP remote data source
 */
fun <T : Any> createHttpRemoteDataSource(
    baseUrl: String,
    entityName: String,
    serializer: KSerializer<T>,
    apiKeyProvider: () -> String? = { null },
): RemoteDataSource<T> =
    HttpRemoteDataSource(
        baseUrl = baseUrl,
        entityName = entityName,
        serializer = serializer,
        apiKeyProvider = apiKeyProvider,
    )

/**
 * Create a remote data source optimized for high-throughput operations
 */
fun <T : Any> createHighThroughputRemoteDataSource(
    baseUrl: String,
    entityName: String,
    serializer: KSerializer<T>,
    apiKeyProvider: () -> String? = { null },
): RemoteDataSource<T> =
    HttpRemoteDataSource(
        baseUrl = baseUrl,
        entityName = entityName,
        serializer = serializer,
        apiKeyProvider = apiKeyProvider,
        retryConfig =
            RetryConfiguration(
                maxAttempts = 5,
                baseDelay = 100.milliseconds,
                backoffStrategy = com.runanywhere.sdk.data.config.BackoffStrategy.EXPONENTIAL,
            ),
        timeoutConfig =
            TimeoutConfiguration(
                read = 10.seconds,
                write = 15.seconds,
                total = 30.seconds,
            ),
    )

/**
 * Create a remote data source optimized for unreliable networks
 */
fun <T : Any> createRobustRemoteDataSource(
    baseUrl: String,
    entityName: String,
    serializer: KSerializer<T>,
    apiKeyProvider: () -> String? = { null },
): RemoteDataSource<T> =
    HttpRemoteDataSource(
        baseUrl = baseUrl,
        entityName = entityName,
        serializer = serializer,
        apiKeyProvider = apiKeyProvider,
        retryConfig =
            RetryConfiguration(
                maxAttempts = 5,
                baseDelay = 2.seconds,
                maxDelay = 1.minutes,
                backoffStrategy = com.runanywhere.sdk.data.config.BackoffStrategy.EXPONENTIAL,
                jitterEnabled = true,
            ),
        timeoutConfig =
            TimeoutConfiguration(
                read = 60.seconds,
                write = 60.seconds,
                total = 5.minutes,
            ),
    )
