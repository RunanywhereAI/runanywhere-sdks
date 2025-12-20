package com.runanywhere.sdk.data.config

import kotlin.math.pow
import kotlin.time.Duration
import kotlin.time.Duration.Companion.hours
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.minutes
import kotlin.time.Duration.Companion.seconds

/**
 * Comprehensive configuration for repository behavior including caching, sync, and retry policies.
 * Provides sensible defaults while allowing fine-grained control over repository operations.
 */
data class RepositoryConfiguration(
    val cache: CacheConfiguration = CacheConfiguration(),
    val sync: SyncConfiguration = SyncConfiguration(),
    val retry: RetryConfiguration = RetryConfiguration(),
    val timeout: TimeoutConfiguration = TimeoutConfiguration(),
    val security: SecurityConfiguration = SecurityConfiguration(),
) {
    companion object {
        /**
         * Default configuration optimized for general use cases
         */
        val default = RepositoryConfiguration()

        /**
         * Configuration optimized for high-performance scenarios
         */
        val highPerformance =
            RepositoryConfiguration(
                cache =
                    CacheConfiguration(
                        maxSize = 1000,
                        ttl = 1.hours,
                        evictionPolicy = EvictionPolicy.LRU,
                    ),
                sync =
                    SyncConfiguration(
                        strategy = SyncStrategy.IMMEDIATE,
                        batchSize = 100,
                    ),
            )

        /**
         * Configuration optimized for low-memory environments
         */
        val lowMemory =
            RepositoryConfiguration(
                cache =
                    CacheConfiguration(
                        maxSize = 100,
                        ttl = 30.minutes,
                        evictionPolicy = EvictionPolicy.LRU,
                    ),
                sync =
                    SyncConfiguration(
                        strategy = SyncStrategy.BATCH,
                        batchSize = 20,
                    ),
            )

        /**
         * Configuration optimized for offline-first scenarios
         */
        val offlineFirst =
            RepositoryConfiguration(
                cache =
                    CacheConfiguration(
                        maxSize = 500,
                        ttl = 24.hours,
                        evictionPolicy = EvictionPolicy.LFU,
                    ),
                sync =
                    SyncConfiguration(
                        strategy = SyncStrategy.PERIODIC,
                        batchSize = 50,
                        conflictResolution = ConflictResolution.LAST_WRITE_WINS,
                    ),
            )
    }
}

/**
 * Cache configuration settings
 */
data class CacheConfiguration(
    val enabled: Boolean = true,
    val maxSize: Int = 500,
    val ttl: Duration = 1.hours,
    val evictionPolicy: EvictionPolicy = EvictionPolicy.LRU,
    val preloadStrategy: PreloadStrategy = PreloadStrategy.LAZY,
    val compressionEnabled: Boolean = false,
    val encryptionEnabled: Boolean = false,
) {
    init {
        require(maxSize > 0) { "Cache max size must be positive" }
        require(ttl > Duration.ZERO) { "Cache TTL must be positive" }
    }

    /**
     * Calculate memory usage estimate in bytes
     */
    fun estimateMemoryUsage(avgEntitySize: Int): Long = maxSize * avgEntitySize * (if (compressionEnabled) 0.7 else 1.0).toLong()
}

/**
 * Cache eviction policies
 */
enum class EvictionPolicy {
    LRU, // Least Recently Used
    LFU, // Least Frequently Used
    FIFO, // First In, First Out
    RANDOM, // Random eviction
    TTL_BASED, // Time-to-live based
}

/**
 * Cache preload strategies
 */
enum class PreloadStrategy {
    LAZY, // Load on demand
    EAGER, // Load immediately
    BACKGROUND, // Load in background
    PREDICTIVE, // Predictive preloading
}

/**
 * Synchronization configuration settings
 */
data class SyncConfiguration(
    val enabled: Boolean = true,
    val strategy: SyncStrategy = SyncStrategy.BATCH,
    val batchSize: Int = 50,
    val syncInterval: Duration = 5.minutes,
    val conflictResolution: ConflictResolution = ConflictResolution.MANUAL,
    val priority: SyncPriority = SyncPriority.NORMAL,
    val networkRequirement: NetworkRequirement = NetworkRequirement.ANY,
    val maxSyncRetries: Int = 3,
) {
    init {
        require(batchSize > 0) { "Sync batch size must be positive" }
        require(syncInterval > Duration.ZERO) { "Sync interval must be positive" }
        require(maxSyncRetries >= 0) { "Max sync retries cannot be negative" }
    }
}

/**
 * Synchronization strategies
 */
enum class SyncStrategy {
    IMMEDIATE, // Sync immediately on changes
    BATCH, // Batch changes and sync periodically
    PERIODIC, // Sync at regular intervals
    MANUAL, // Sync only when explicitly requested
    ADAPTIVE, // Adaptive strategy based on network and usage
}

/**
 * Conflict resolution strategies
 */
enum class ConflictResolution {
    LAST_WRITE_WINS, // Most recent change wins
    FIRST_WRITE_WINS, // First change wins
    MERGE, // Attempt to merge changes
    MANUAL, // Require manual resolution
    LOCAL_WINS, // Local changes always win
    REMOTE_WINS, // Remote changes always win
}

/**
 * Sync priority levels
 */
enum class SyncPriority {
    LOW,
    NORMAL,
    HIGH,
    CRITICAL,
}

/**
 * Network requirements for sync operations
 */
enum class NetworkRequirement {
    ANY, // Any network connection
    WIFI, // WiFi only
    HIGH_SPEED, // High-speed connection required
    UNMETERED, // Unmetered connection only
}

/**
 * Retry configuration settings
 */
data class RetryConfiguration(
    val enabled: Boolean = true,
    val maxAttempts: Int = 3,
    val baseDelay: Duration = 1.seconds,
    val maxDelay: Duration = 30.seconds,
    val backoffStrategy: BackoffStrategy = BackoffStrategy.EXPONENTIAL,
    val jitterEnabled: Boolean = true,
    val retryableErrors: Set<String> =
        setOf(
            "NETWORK_ERROR",
            "TIMEOUT_ERROR",
            "SERVICE_UNAVAILABLE",
        ),
) {
    init {
        require(maxAttempts > 0) { "Max retry attempts must be positive" }
        require(baseDelay > Duration.ZERO) { "Base delay must be positive" }
        require(maxDelay >= baseDelay) { "Max delay must be >= base delay" }
    }

    /**
     * Calculate delay for a given attempt number
     */
    fun calculateDelay(attempt: Int): Duration {
        val delay =
            when (backoffStrategy) {
                BackoffStrategy.FIXED -> baseDelay
                BackoffStrategy.LINEAR -> baseDelay * attempt
                BackoffStrategy.EXPONENTIAL -> (baseDelay.inWholeMilliseconds * 2.0.pow(attempt.toDouble())).toLong().milliseconds
            }

        val actualDelay = minOf(delay, maxDelay)

        return if (jitterEnabled) {
            val jitter = actualDelay.inWholeMilliseconds * 0.1 * kotlin.random.Random.nextDouble()
            actualDelay + jitter.toLong().milliseconds
        } else {
            actualDelay
        }
    }
}

/**
 * Backoff strategies for retry operations
 */
enum class BackoffStrategy {
    FIXED, // Fixed delay between retries
    LINEAR, // Linear increase in delay
    EXPONENTIAL, // Exponential backoff
}

/**
 * Timeout configuration settings
 */
data class TimeoutConfiguration(
    val read: Duration = 30.seconds,
    val write: Duration = 30.seconds,
    val sync: Duration = 2.minutes,
    val connect: Duration = 10.seconds,
    val total: Duration = 5.minutes,
) {
    init {
        require(read > Duration.ZERO) { "Read timeout must be positive" }
        require(write > Duration.ZERO) { "Write timeout must be positive" }
        require(sync > Duration.ZERO) { "Sync timeout must be positive" }
        require(connect > Duration.ZERO) { "Connect timeout must be positive" }
        require(total > Duration.ZERO) { "Total timeout must be positive" }
    }
}

/**
 * Security configuration settings
 */
data class SecurityConfiguration(
    val encryptionEnabled: Boolean = false,
    val encryptionAlgorithm: String = "AES-256-GCM",
    val keyRotationInterval: Duration = 24.hours,
    val auditLoggingEnabled: Boolean = false,
    val sensitiveDataMasking: Boolean = true,
    val accessLoggingEnabled: Boolean = false,
)

/**
 * Builder pattern for creating custom repository configurations
 */
class RepositoryConfigurationBuilder {
    private var cache = CacheConfiguration()
    private var sync = SyncConfiguration()
    private var retry = RetryConfiguration()
    private var timeout = TimeoutConfiguration()
    private var security = SecurityConfiguration()

    fun cache(block: CacheConfigurationBuilder.() -> Unit): RepositoryConfigurationBuilder {
        cache = CacheConfigurationBuilder().apply(block).build()
        return this
    }

    fun sync(block: SyncConfigurationBuilder.() -> Unit): RepositoryConfigurationBuilder {
        sync = SyncConfigurationBuilder().apply(block).build()
        return this
    }

    fun retry(block: RetryConfigurationBuilder.() -> Unit): RepositoryConfigurationBuilder {
        retry = RetryConfigurationBuilder().apply(block).build()
        return this
    }

    fun timeout(block: TimeoutConfigurationBuilder.() -> Unit): RepositoryConfigurationBuilder {
        timeout = TimeoutConfigurationBuilder().apply(block).build()
        return this
    }

    fun security(block: SecurityConfigurationBuilder.() -> Unit): RepositoryConfigurationBuilder {
        security = SecurityConfigurationBuilder().apply(block).build()
        return this
    }

    fun build(): RepositoryConfiguration = RepositoryConfiguration(cache, sync, retry, timeout, security)
}

// Configuration builders for each section
class CacheConfigurationBuilder {
    var enabled = true
    var maxSize = 500
    var ttl = 1.hours
    var evictionPolicy = EvictionPolicy.LRU
    var preloadStrategy = PreloadStrategy.LAZY
    var compressionEnabled = false
    var encryptionEnabled = false

    fun build() =
        CacheConfiguration(
            enabled,
            maxSize,
            ttl,
            evictionPolicy,
            preloadStrategy,
            compressionEnabled,
            encryptionEnabled,
        )
}

class SyncConfigurationBuilder {
    var enabled = true
    var strategy = SyncStrategy.BATCH
    var batchSize = 50
    var syncInterval = 5.minutes
    var conflictResolution = ConflictResolution.MANUAL
    var priority = SyncPriority.NORMAL
    var networkRequirement = NetworkRequirement.ANY
    var maxSyncRetries = 3

    fun build() =
        SyncConfiguration(
            enabled,
            strategy,
            batchSize,
            syncInterval,
            conflictResolution,
            priority,
            networkRequirement,
            maxSyncRetries,
        )
}

class RetryConfigurationBuilder {
    var enabled = true
    var maxAttempts = 3
    var baseDelay = 1.seconds
    var maxDelay = 30.seconds
    var backoffStrategy = BackoffStrategy.EXPONENTIAL
    var jitterEnabled = true
    var retryableErrors = setOf("NETWORK_ERROR", "TIMEOUT_ERROR", "SERVICE_UNAVAILABLE")

    fun build() =
        RetryConfiguration(
            enabled,
            maxAttempts,
            baseDelay,
            maxDelay,
            backoffStrategy,
            jitterEnabled,
            retryableErrors,
        )
}

class TimeoutConfigurationBuilder {
    var read = 30.seconds
    var write = 30.seconds
    var sync = 2.minutes
    var connect = 10.seconds
    var total = 5.minutes

    fun build() = TimeoutConfiguration(read, write, sync, connect, total)
}

class SecurityConfigurationBuilder {
    var encryptionEnabled = false
    var encryptionAlgorithm = "AES-256-GCM"
    var keyRotationInterval = 24.hours
    var auditLoggingEnabled = false
    var sensitiveDataMasking = true
    var accessLoggingEnabled = false

    fun build() =
        SecurityConfiguration(
            encryptionEnabled,
            encryptionAlgorithm,
            keyRotationInterval,
            auditLoggingEnabled,
            sensitiveDataMasking,
            accessLoggingEnabled,
        )
}

/**
 * DSL function for creating repository configurations
 */
fun repositoryConfiguration(block: RepositoryConfigurationBuilder.() -> Unit): RepositoryConfiguration =
    RepositoryConfigurationBuilder().apply(block).build()
