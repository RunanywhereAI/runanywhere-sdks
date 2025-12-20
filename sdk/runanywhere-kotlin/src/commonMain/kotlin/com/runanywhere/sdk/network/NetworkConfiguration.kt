package com.runanywhere.sdk.network

/**
 * Comprehensive network configuration for HTTP clients
 * Provides all networking configuration options to achieve parity with iOS implementation
 */
data class NetworkConfiguration(
    // Timeout Configuration
    val connectTimeoutMs: Long = 30_000, // 30 seconds
    val readTimeoutMs: Long = 30_000, // 30 seconds
    val writeTimeoutMs: Long = 30_000, // 30 seconds
    val callTimeoutMs: Long = 60_000, // 60 seconds total call timeout
    // Retry Policy Configuration
    val maxRetryAttempts: Int = 3,
    val baseRetryDelayMs: Long = 1000, // 1 second
    val maxRetryDelayMs: Long = 30_000, // 30 seconds cap
    val retryBackoffMultiplier: Double = 2.0,
    val retryJitterPercentage: Double = 0.25, // 25% jitter
    // Connection Pool Configuration
    val maxIdleConnections: Int = 5,
    val keepAliveDurationMs: Long = 300_000, // 5 minutes
    // SSL/TLS Configuration
    val enableTlsVersions: List<String> = listOf("TLSv1.2", "TLSv1.3"),
    val certificatePinning: CertificatePinningConfig? = null,
    val hostnameVerification: Boolean = true,
    // Cache Configuration
    val enableResponseCaching: Boolean = false,
    val cacheSizeBytes: Long = 50 * 1024 * 1024, // 50MB
    val cacheDirectory: String? = null,
    // Proxy Configuration
    val proxyConfig: ProxyConfig? = null,
    // Request/Response Interceptor Configuration
    val enableLogging: Boolean = false,
    val logLevel: NetworkLogLevel = NetworkLogLevel.NONE,
    val logBodySizeLimit: Int = 8192, // 8KB
    // User-Agent Configuration
    val userAgent: String = "RunAnywhereSDK-Kotlin/0.1.0",
    val customHeaders: Map<String, String> = emptyMap(),
    // Progress Reporting Configuration
    val progressCallbackIntervalMs: Long = 100, // 100ms intervals for progress
    // Connection Behavior
    val followRedirects: Boolean = true,
    val maxRedirects: Int = 20,
    val enableHttp2: Boolean = true,
    val enableCompression: Boolean = true,
    // Advanced Configuration
    val enableDiskCaching: Boolean = true,
    val enableMemoryCaching: Boolean = true,
    val dnsCacheTimeoutMs: Long = 60_000, // 1 minute
) {
    /**
     * Validate configuration values
     */
    fun validate(): List<String> {
        val errors = mutableListOf<String>()

        if (connectTimeoutMs < 0) errors.add("connectTimeoutMs must be >= 0")
        if (readTimeoutMs < 0) errors.add("readTimeoutMs must be >= 0")
        if (writeTimeoutMs < 0) errors.add("writeTimeoutMs must be >= 0")
        if (callTimeoutMs < 0) errors.add("callTimeoutMs must be >= 0")

        if (maxRetryAttempts < 0) errors.add("maxRetryAttempts must be >= 0")
        if (baseRetryDelayMs < 0) errors.add("baseRetryDelayMs must be >= 0")
        if (maxRetryDelayMs < baseRetryDelayMs) errors.add("maxRetryDelayMs must be >= baseRetryDelayMs")
        if (retryBackoffMultiplier < 1.0) errors.add("retryBackoffMultiplier must be >= 1.0")
        if (retryJitterPercentage < 0.0 || retryJitterPercentage > 1.0) {
            errors.add("retryJitterPercentage must be between 0.0 and 1.0")
        }

        if (maxIdleConnections < 0) errors.add("maxIdleConnections must be >= 0")
        if (keepAliveDurationMs < 0) errors.add("keepAliveDurationMs must be >= 0")

        if (cacheSizeBytes < 0) errors.add("cacheSizeBytes must be >= 0")
        if (logBodySizeLimit < 0) errors.add("logBodySizeLimit must be >= 0")
        if (progressCallbackIntervalMs < 0) errors.add("progressCallbackIntervalMs must be >= 0")
        if (maxRedirects < 0) errors.add("maxRedirects must be >= 0")
        if (dnsCacheTimeoutMs < 0) errors.add("dnsCacheTimeoutMs must be >= 0")

        return errors
    }

    /**
     * Check if configuration is valid
     */
    fun isValid(): Boolean = validate().isEmpty()

    /**
     * Create a builder for this configuration
     */
    fun toBuilder() = Builder(this)

    /**
     * Builder pattern for NetworkConfiguration
     */
    class Builder(
        config: NetworkConfiguration = NetworkConfiguration(),
    ) {
        private var connectTimeoutMs = config.connectTimeoutMs
        private var readTimeoutMs = config.readTimeoutMs
        private var writeTimeoutMs = config.writeTimeoutMs
        private var callTimeoutMs = config.callTimeoutMs

        private var maxRetryAttempts = config.maxRetryAttempts
        private var baseRetryDelayMs = config.baseRetryDelayMs
        private var maxRetryDelayMs = config.maxRetryDelayMs
        private var retryBackoffMultiplier = config.retryBackoffMultiplier
        private var retryJitterPercentage = config.retryJitterPercentage

        private var maxIdleConnections = config.maxIdleConnections
        private var keepAliveDurationMs = config.keepAliveDurationMs

        private var enableTlsVersions = config.enableTlsVersions
        private var certificatePinning = config.certificatePinning
        private var hostnameVerification = config.hostnameVerification

        private var enableResponseCaching = config.enableResponseCaching
        private var cacheSizeBytes = config.cacheSizeBytes
        private var cacheDirectory = config.cacheDirectory

        private var proxyConfig = config.proxyConfig

        private var enableLogging = config.enableLogging
        private var logLevel = config.logLevel
        private var logBodySizeLimit = config.logBodySizeLimit

        private var userAgent = config.userAgent
        private var customHeaders = config.customHeaders

        private var progressCallbackIntervalMs = config.progressCallbackIntervalMs

        private var followRedirects = config.followRedirects
        private var maxRedirects = config.maxRedirects
        private var enableHttp2 = config.enableHttp2
        private var enableCompression = config.enableCompression

        private var enableDiskCaching = config.enableDiskCaching
        private var enableMemoryCaching = config.enableMemoryCaching
        private var dnsCacheTimeoutMs = config.dnsCacheTimeoutMs

        fun connectTimeout(timeoutMs: Long) = apply { this.connectTimeoutMs = timeoutMs }

        fun readTimeout(timeoutMs: Long) = apply { this.readTimeoutMs = timeoutMs }

        fun writeTimeout(timeoutMs: Long) = apply { this.writeTimeoutMs = timeoutMs }

        fun callTimeout(timeoutMs: Long) = apply { this.callTimeoutMs = timeoutMs }

        fun maxRetries(attempts: Int) = apply { this.maxRetryAttempts = attempts }

        fun retryDelay(
            baseDelayMs: Long,
            maxDelayMs: Long = this.maxRetryDelayMs,
        ) = apply {
            this.baseRetryDelayMs = baseDelayMs
            this.maxRetryDelayMs = maxDelayMs
        }

        fun retryBackoff(multiplier: Double) = apply { this.retryBackoffMultiplier = multiplier }

        fun retryJitter(percentage: Double) = apply { this.retryJitterPercentage = percentage }

        fun connectionPool(
            maxIdle: Int,
            keepAlive: Long,
        ) = apply {
            this.maxIdleConnections = maxIdle
            this.keepAliveDurationMs = keepAlive
        }

        fun tls(versions: List<String>) = apply { this.enableTlsVersions = versions }

        fun certificatePinning(config: CertificatePinningConfig?) = apply { this.certificatePinning = config }

        fun hostnameVerification(enabled: Boolean) = apply { this.hostnameVerification = enabled }

        fun caching(
            enabled: Boolean,
            sizeBytes: Long = this.cacheSizeBytes,
            directory: String? = this.cacheDirectory,
        ) = apply {
            this.enableResponseCaching = enabled
            this.cacheSizeBytes = sizeBytes
            this.cacheDirectory = directory
        }

        fun proxy(config: ProxyConfig?) = apply { this.proxyConfig = config }

        fun logging(
            enabled: Boolean,
            level: NetworkLogLevel = NetworkLogLevel.INFO,
        ) = apply {
            this.enableLogging = enabled
            this.logLevel = level
        }

        fun logBodyLimit(sizeLimit: Int) = apply { this.logBodySizeLimit = sizeLimit }

        fun userAgent(agent: String) = apply { this.userAgent = agent }

        fun headers(headers: Map<String, String>) = apply { this.customHeaders = headers }

        fun progressInterval(intervalMs: Long) = apply { this.progressCallbackIntervalMs = intervalMs }

        fun redirects(
            follow: Boolean,
            maxRedirects: Int = this.maxRedirects,
        ) = apply {
            this.followRedirects = follow
            this.maxRedirects = maxRedirects
        }

        fun http2(enabled: Boolean) = apply { this.enableHttp2 = enabled }

        fun compression(enabled: Boolean) = apply { this.enableCompression = enabled }

        fun diskCaching(enabled: Boolean) = apply { this.enableDiskCaching = enabled }

        fun memoryCaching(enabled: Boolean) = apply { this.enableMemoryCaching = enabled }

        fun dnsCache(timeoutMs: Long) = apply { this.dnsCacheTimeoutMs = timeoutMs }

        fun build() =
            NetworkConfiguration(
                connectTimeoutMs = connectTimeoutMs,
                readTimeoutMs = readTimeoutMs,
                writeTimeoutMs = writeTimeoutMs,
                callTimeoutMs = callTimeoutMs,
                maxRetryAttempts = maxRetryAttempts,
                baseRetryDelayMs = baseRetryDelayMs,
                maxRetryDelayMs = maxRetryDelayMs,
                retryBackoffMultiplier = retryBackoffMultiplier,
                retryJitterPercentage = retryJitterPercentage,
                maxIdleConnections = maxIdleConnections,
                keepAliveDurationMs = keepAliveDurationMs,
                enableTlsVersions = enableTlsVersions,
                certificatePinning = certificatePinning,
                hostnameVerification = hostnameVerification,
                enableResponseCaching = enableResponseCaching,
                cacheSizeBytes = cacheSizeBytes,
                cacheDirectory = cacheDirectory,
                proxyConfig = proxyConfig,
                enableLogging = enableLogging,
                logLevel = logLevel,
                logBodySizeLimit = logBodySizeLimit,
                userAgent = userAgent,
                customHeaders = customHeaders,
                progressCallbackIntervalMs = progressCallbackIntervalMs,
                followRedirects = followRedirects,
                maxRedirects = maxRedirects,
                enableHttp2 = enableHttp2,
                enableCompression = enableCompression,
                enableDiskCaching = enableDiskCaching,
                enableMemoryCaching = enableMemoryCaching,
                dnsCacheTimeoutMs = dnsCacheTimeoutMs,
            )
    }

    companion object {
        /**
         * Default production configuration
         */
        fun production() =
            NetworkConfiguration(
                maxRetryAttempts = 3,
                enableLogging = false,
                logLevel = NetworkLogLevel.NONE,
                enableResponseCaching = true,
                enableHttp2 = true,
                enableCompression = true,
            )

        /**
         * Development configuration with enhanced logging
         */
        fun development() =
            NetworkConfiguration(
                maxRetryAttempts = 1, // Fewer retries for faster feedback
                enableLogging = true,
                logLevel = NetworkLogLevel.BODY,
                enableResponseCaching = false, // No caching during development
                enableHttp2 = true,
                enableCompression = true,
            )

        /**
         * Testing configuration with minimal timeouts
         */
        fun testing() =
            NetworkConfiguration(
                connectTimeoutMs = 5_000, // 5 seconds
                readTimeoutMs = 5_000, // 5 seconds
                writeTimeoutMs = 5_000, // 5 seconds
                callTimeoutMs = 10_000, // 10 seconds
                maxRetryAttempts = 0, // No retries in tests
                enableLogging = false,
                enableResponseCaching = false,
                enableHttp2 = false, // Use HTTP/1.1 for simpler testing
                enableCompression = false,
            )
    }
}

/**
 * SSL Certificate pinning configuration
 */
data class CertificatePinningConfig(
    val pins: Map<String, List<String>>, // hostname -> list of SHA-256 pins
    val enforcePinning: Boolean = true,
    val includeSubdomains: Boolean = false,
)

/**
 * Proxy configuration
 */
sealed class ProxyConfig {
    data class Http(
        val host: String,
        val port: Int,
        val username: String? = null,
        val password: String? = null,
    ) : ProxyConfig()

    data class Socks(
        val host: String,
        val port: Int,
        val username: String? = null,
        val password: String? = null,
    ) : ProxyConfig()

    object Direct : ProxyConfig()
}

/**
 * Network logging levels
 */
enum class NetworkLogLevel {
    NONE, // No logging
    BASIC, // Request/response line only
    HEADERS, // Request/response line + headers
    BODY, // Request/response line + headers + body
    INFO, // HEADERS level for successful requests, BODY level for errors
    DEBUG, // Everything including internal client logs
}

/**
 * Retry policy configuration
 */
data class RetryPolicy(
    val maxAttempts: Int,
    val baseDelayMs: Long,
    val maxDelayMs: Long,
    val backoffMultiplier: Double,
    val jitterPercentage: Double,
    val retryableStatusCodes: Set<Int> = setOf(408, 429, 502, 503, 504),
    val retryableExceptions: Set<String> =
        setOf(
            "java.net.SocketTimeoutException",
            "java.net.ConnectException",
            "java.net.UnknownHostException",
        ),
) {
    companion object {
        val DEFAULT =
            RetryPolicy(
                maxAttempts = 3,
                baseDelayMs = 1000,
                maxDelayMs = 30_000,
                backoffMultiplier = 2.0,
                jitterPercentage = 0.25,
            )

        val AGGRESSIVE =
            RetryPolicy(
                maxAttempts = 5,
                baseDelayMs = 500,
                maxDelayMs = 60_000,
                backoffMultiplier = 1.5,
                jitterPercentage = 0.1,
            )

        val NO_RETRY =
            RetryPolicy(
                maxAttempts = 0,
                baseDelayMs = 0,
                maxDelayMs = 0,
                backoffMultiplier = 1.0,
                jitterPercentage = 0.0,
            )
    }
}
