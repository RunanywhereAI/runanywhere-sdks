package com.runanywhere.sdk.features.wakeword

import com.runanywhere.sdk.core.capabilities.*
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.utils.getCurrentTimeMillis

// MARK: - Wake Word Configuration

/**
 * Configuration for Wake Word Detection component
 * Matches iOS WakeWordConfiguration exactly
 */
data class WakeWordConfiguration(
    // Component type
    override val componentType: SDKComponent = SDKComponent.WAKEWORD,

    // Model ID (if using ML-based detection)
    override val modelId: String? = null,

    // Wake words to detect
    val wakeWords: List<String> = listOf("Hey Siri", "OK Google"),

    // Detection sensitivity (0.0 to 1.0)
    val sensitivity: Float = 0.5f,

    // Audio buffer size
    val bufferSize: Int = 16000,

    // Sample rate
    val sampleRate: Int = 16000,

    // Confidence threshold for detection
    val confidenceThreshold: Float = 0.7f,

    // Whether to continue listening after detection
    val continuousListening: Boolean = true
) : ComponentConfiguration, ComponentInitParameters {

    override fun validate() {
        if (wakeWords.isEmpty()) {
            throw SDKError.ValidationFailed("At least one wake word must be specified")
        }
        if (sensitivity < 0f || sensitivity > 1f) {
            throw SDKError.ValidationFailed("Sensitivity must be between 0 and 1")
        }
        if (confidenceThreshold < 0f || confidenceThreshold > 1f) {
            throw SDKError.ValidationFailed("Confidence threshold must be between 0 and 1")
        }
    }
}

// MARK: - Wake Word Input

/**
 * Input for Wake Word Detection
 * Matches iOS WakeWordInput exactly
 */
data class WakeWordInput(
    // Audio buffer to process
    val audioBuffer: FloatArray,

    // Optional timestamp
    val timestamp: Long? = null
) : ComponentInput {

    override fun validate() {
        if (audioBuffer.isEmpty()) {
            throw SDKError.ValidationFailed("Audio buffer cannot be empty")
        }
    }

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is WakeWordInput) return false
        return audioBuffer.contentEquals(other.audioBuffer) && timestamp == other.timestamp
    }

    override fun hashCode(): Int {
        var result = audioBuffer.contentHashCode()
        result = 31 * result + (timestamp?.hashCode() ?: 0)
        return result
    }
}

// MARK: - Wake Word Output

/**
 * Output from Wake Word Detection
 * Matches iOS WakeWordOutput exactly
 */
data class WakeWordOutput(
    // Whether a wake word was detected
    val detected: Boolean,

    // Detected wake word (if any)
    val wakeWord: String? = null,

    // Confidence score (0.0 to 1.0)
    val confidence: Float,

    // Detection metadata
    val metadata: WakeWordMetadata,

    // Timestamp (required by ComponentOutput)
    override val timestamp: Long = getCurrentTimeMillis()
) : ComponentOutput

// MARK: - Wake Word Metadata

/**
 * Wake word detection metadata
 * Matches iOS WakeWordMetadata exactly
 */
data class WakeWordMetadata(
    val processingTime: Double, // In seconds
    val bufferSize: Int,
    val sampleRate: Int
)

// MARK: - Wake Word Service Protocol

/**
 * Protocol for wake word detection services
 * Matches iOS WakeWordService protocol exactly
 */
interface WakeWordService {
    // Initialize the service
    suspend fun initialize()

    // Start listening for wake words
    fun startListening()

    // Stop listening for wake words
    fun stopListening()

    // Process audio buffer and check for wake words
    fun processAudioBuffer(buffer: FloatArray): Boolean

    // Check if currently listening
    val isListening: Boolean

    // Cleanup resources
    suspend fun cleanup()
}

// MARK: - Default Wake Word Service

/**
 * Default implementation that always returns false (no detection)
 * Matches iOS DefaultWakeWordService exactly
 */
class DefaultWakeWordService : WakeWordService {
    private var _isListening = false

    override suspend fun initialize() {
        // No initialization needed for default implementation
    }

    override fun startListening() {
        _isListening = true
    }

    override fun stopListening() {
        _isListening = false
    }

    override fun processAudioBuffer(buffer: FloatArray): Boolean {
        // Default implementation always returns false (no detection)
        return false
    }

    override val isListening: Boolean
        get() = _isListening

    override suspend fun cleanup() {
        _isListening = false
    }
}

// MARK: - Wake Word Service Wrapper

/**
 * Wrapper class to allow protocol-based WakeWord service to work with BaseComponent
 */
class WakeWordServiceWrapper(service: WakeWordService? = null) : ServiceWrapper<WakeWordService> {
    override var wrappedService: WakeWordService? = service
}

// MARK: - Wake Word Service Provider Protocol

/**
 * Protocol for registering external Wake Word implementations
 * Matches iOS WakeWordServiceProvider exactly
 */
interface WakeWordServiceProvider {
    // Create a wake word service for the given configuration
    suspend fun createWakeWordService(configuration: WakeWordConfiguration): WakeWordService

    // Check if this provider can handle the given model
    fun canHandle(modelId: String?): Boolean

    // Provider name for identification
    val name: String
}

// MARK: - Wake Word Errors

/**
 * Wake word specific errors
 */
sealed class WakeWordError : Exception() {
    data object ServiceNotInitialized : WakeWordError()
    data class ProcessingFailed(override val cause: Throwable) : WakeWordError()
    data object InvalidAudioFormat : WakeWordError()
    data object ConfigurationError : WakeWordError()

    override val message: String
        get() = when (this) {
            is ServiceNotInitialized -> "Wake word service is not initialized"
            is ProcessingFailed -> "Wake word processing failed: ${cause.message}"
            is InvalidAudioFormat -> "Invalid audio format for wake word detection"
            is ConfigurationError -> "Wake word configuration error"
        }
}
