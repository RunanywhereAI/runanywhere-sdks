package com.runanywhere.sdk.data.errors

/**
 * Sealed class hierarchy for repository-related errors.
 * Provides structured error handling with specific error types and recovery patterns.
 */
sealed class RepositoryError : Exception() {

    /**
     * Error code for programmatic identification
     */
    abstract val errorCode: String

    /**
     * Timestamp when the error occurred
     */
    abstract val timestamp: Long

    /**
     * Additional context about the error
     */
    abstract val context: Map<String, Any>

    /**
     * Whether this error is recoverable
     */
    abstract val isRecoverable: Boolean

    /**
     * Entity not found in storage
     */
    data class NotFound(
        val entityId: String,
        val entityType: String,
        override val message: String = "Entity '$entityId' of type '$entityType' not found",
        override val timestamp: Long = System.currentTimeMillis(),
        override val context: Map<String, Any> = mapOf(
            "entityId" to entityId,
            "entityType" to entityType
        )
    ) : RepositoryError() {
        override val errorCode = "ENTITY_NOT_FOUND"
        override val isRecoverable = false
    }

    /**
     * Network-related errors during remote operations
     */
    data class NetworkError(
        val operation: String,
        override val cause: Throwable? = null,
        override val message: String = "Network error during operation: $operation",
        override val timestamp: Long = System.currentTimeMillis(),
        override val context: Map<String, Any> = mapOf("operation" to operation)
    ) : RepositoryError() {
        override val errorCode = "NETWORK_ERROR"
        override val isRecoverable = true
    }

    /**
     * Cache-related errors
     */
    data class CacheError(
        val cacheOperation: CacheOperation,
        override val cause: Throwable? = null,
        override val message: String = "Cache error during ${cacheOperation.name.lowercase()}",
        override val timestamp: Long = System.currentTimeMillis(),
        override val context: Map<String, Any> = mapOf("operation" to cacheOperation.name)
    ) : RepositoryError() {
        override val errorCode = "CACHE_ERROR"
        override val isRecoverable = true
    }

    /**
     * Synchronization conflict errors
     */
    data class SyncConflict(
        val entityId: String,
        val conflictType: ConflictType,
        val localVersion: String? = null,
        val remoteVersion: String? = null,
        override val message: String = "Sync conflict for entity '$entityId': ${conflictType.name}",
        override val timestamp: Long = System.currentTimeMillis(),
        override val context: Map<String, Any> = mapOf(
            "entityId" to entityId,
            "conflictType" to conflictType.name,
            "localVersion" to (localVersion ?: "unknown"),
            "remoteVersion" to (remoteVersion ?: "unknown")
        )
    ) : RepositoryError() {
        override val errorCode = "SYNC_CONFLICT"
        override val isRecoverable = true
    }

    /**
     * Data validation errors
     */
    data class ValidationError(
        val field: String,
        val value: Any?,
        val validationRule: String,
        override val message: String = "Validation failed for field '$field': $validationRule",
        override val timestamp: Long = System.currentTimeMillis(),
        override val context: Map<String, Any> = mapOf(
            "field" to field,
            "value" to (value ?: "null"),
            "rule" to validationRule
        )
    ) : RepositoryError() {
        override val errorCode = "VALIDATION_ERROR"
        override val isRecoverable = false
    }

    /**
     * Storage capacity or quota exceeded
     */
    data class StorageError(
        val storageType: String,
        val availableSpace: Long,
        val requiredSpace: Long,
        override val message: String = "Storage error in $storageType: insufficient space",
        override val timestamp: Long = System.currentTimeMillis(),
        override val context: Map<String, Any> = mapOf(
            "storageType" to storageType,
            "availableSpace" to availableSpace,
            "requiredSpace" to requiredSpace
        )
    ) : RepositoryError() {
        override val errorCode = "STORAGE_ERROR"
        override val isRecoverable = true
    }

    /**
     * Serialization/deserialization errors
     */
    data class SerializationError(
        val entityType: String,
        val operation: SerializationOperation,
        override val cause: Throwable? = null,
        override val message: String = "Serialization error during ${operation.name.lowercase()} of $entityType",
        override val timestamp: Long = System.currentTimeMillis(),
        override val context: Map<String, Any> = mapOf(
            "entityType" to entityType,
            "operation" to operation.name
        )
    ) : RepositoryError() {
        override val errorCode = "SERIALIZATION_ERROR"
        override val isRecoverable = false
    }

    /**
     * Authentication and authorization errors
     */
    data class AuthenticationError(
        val operation: String,
        val reason: AuthFailureReason,
        override val message: String = "Authentication failed for operation '$operation': ${reason.description}",
        override val timestamp: Long = System.currentTimeMillis(),
        override val context: Map<String, Any> = mapOf(
            "operation" to operation,
            "reason" to reason.name
        )
    ) : RepositoryError() {
        override val errorCode = "AUTH_ERROR"
        override val isRecoverable = reason.isRecoverable
    }

    /**
     * Configuration or setup errors
     */
    data class ConfigurationError(
        val configKey: String,
        val issue: String,
        override val message: String = "Configuration error for '$configKey': $issue",
        override val timestamp: Long = System.currentTimeMillis(),
        override val context: Map<String, Any> = mapOf(
            "configKey" to configKey,
            "issue" to issue
        )
    ) : RepositoryError() {
        override val errorCode = "CONFIG_ERROR"
        override val isRecoverable = false
    }

    /**
     * Timeout errors for long-running operations
     */
    data class TimeoutError(
        val operation: String,
        val timeoutMs: Long,
        override val message: String = "Operation '$operation' timed out after ${timeoutMs}ms",
        override val timestamp: Long = System.currentTimeMillis(),
        override val context: Map<String, Any> = mapOf(
            "operation" to operation,
            "timeoutMs" to timeoutMs
        )
    ) : RepositoryError() {
        override val errorCode = "TIMEOUT_ERROR"
        override val isRecoverable = true
    }

    /**
     * Invalid state errors
     */
    data class InvalidState(
        override val message: String,
        val currentState: String? = null,
        override val timestamp: Long = System.currentTimeMillis(),
        override val context: Map<String, Any> = mapOf(
            "currentState" to (currentState ?: "unknown")
        )
    ) : RepositoryError() {
        override val errorCode = "INVALID_STATE"
        override val isRecoverable = false
    }

    /**
     * Unknown or unexpected errors
     */
    data class UnknownError(
        override val cause: Throwable? = null,
        override val message: String = "Unknown error occurred: ${cause?.message ?: "No details available"}",
        override val timestamp: Long = System.currentTimeMillis(),
        override val context: Map<String, Any> = emptyMap()
    ) : RepositoryError() {
        override val errorCode = "UNKNOWN_ERROR"
        override val isRecoverable = true
    }
}

/**
 * Cache operation types
 */
enum class CacheOperation {
    GET, PUT, REMOVE, CLEAR, EVICT
}

/**
 * Types of synchronization conflicts
 */
enum class ConflictType {
    MODIFICATION_CONFLICT,
    DELETION_CONFLICT,
    CREATION_CONFLICT,
    VERSION_CONFLICT
}

/**
 * Serialization operation types
 */
enum class SerializationOperation {
    SERIALIZE, DESERIALIZE
}

/**
 * Authentication failure reasons
 */
enum class AuthFailureReason(val description: String, val isRecoverable: Boolean) {
    INVALID_CREDENTIALS("Invalid credentials provided", false),
    EXPIRED_TOKEN("Authentication token has expired", true),
    INSUFFICIENT_PERMISSIONS("Insufficient permissions for this operation", false),
    NETWORK_UNAVAILABLE("Network unavailable for authentication", true),
    SERVICE_UNAVAILABLE("Authentication service unavailable", true),
    UNKNOWN("Unknown authentication error", true)
}

/**
 * Extensions for error recovery patterns
 */

/**
 * Check if an error indicates a temporary failure that might succeed on retry
 */
fun RepositoryError.shouldRetry(): Boolean {
    return when (this) {
        is RepositoryError.NetworkError,
        is RepositoryError.CacheError,
        is RepositoryError.StorageError,
        is RepositoryError.TimeoutError -> true
        is RepositoryError.AuthenticationError -> this.reason.isRecoverable
        else -> false
    }
}

/**
 * Get suggested delay before retry in milliseconds
 */
fun RepositoryError.getRetryDelay(): Long {
    return when (this) {
        is RepositoryError.NetworkError -> 1000L
        is RepositoryError.CacheError -> 500L
        is RepositoryError.StorageError -> 2000L
        is RepositoryError.TimeoutError -> 5000L
        is RepositoryError.AuthenticationError -> 3000L
        else -> 1000L
    }
}

/**
 * Get maximum number of retry attempts
 */
fun RepositoryError.getMaxRetries(): Int {
    return when (this) {
        is RepositoryError.NetworkError -> 3
        is RepositoryError.CacheError -> 2
        is RepositoryError.StorageError -> 1
        is RepositoryError.TimeoutError -> 2
        is RepositoryError.AuthenticationError -> 1
        else -> 1
    }
}

/**
 * Convert exception to appropriate RepositoryError
 */
fun Throwable.toRepositoryError(): RepositoryError {
    return when (this) {
        is RepositoryError -> this
        is IllegalArgumentException -> RepositoryError.ValidationError(
            field = "unknown",
            value = null,
            validationRule = message ?: "Invalid argument"
        )
        is IllegalStateException -> RepositoryError.ConfigurationError(
            configKey = "state",
            issue = message ?: "Invalid state"
        )
        else -> RepositoryError.UnknownError(cause = this)
    }
}
