package com.runanywhere.sdk.components.base

import com.runanywhere.sdk.components.stt.STTConfiguration
import com.runanywhere.sdk.components.stt.STTService
import com.runanywhere.sdk.components.vad.VADConfiguration
import com.runanywhere.sdk.components.vad.VADService
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.events.EventBus
import com.runanywhere.sdk.events.ComponentInitializationEvent
import com.runanywhere.sdk.foundation.ServiceContainer
import com.runanywhere.sdk.utils.getCurrentTimeMillis
import kotlinx.coroutines.flow.Flow

// MARK: - Base Protocols

/**
 * Base protocol for component inputs
 */
interface ComponentInput {
    fun validate()
}

/**
 * Base protocol for component outputs
 */
interface ComponentOutput {
    val timestamp: Long
}

/**
 * Base protocol for component configurations
 */
interface ComponentConfiguration {
    fun validate()
}

/**
 * Component initialization parameters
 */
interface ComponentInitParameters : ComponentConfiguration {
    val componentType: SDKComponent
    val modelId: String?
}

/**
 * Base protocol for component adapters
 */
interface ComponentAdapter<ServiceType : Any> {
    suspend fun createService(configuration: ComponentConfiguration): ServiceType
}

// MARK: - Component State

enum class ComponentState {
    NOT_INITIALIZED,
    CHECKING,
    DOWNLOAD_REQUIRED,
    DOWNLOADING,
    DOWNLOADED,
    INITIALIZING,
    READY,
    PROCESSING,
    FAILED
}

// MARK: - SDK Component Types

enum class SDKComponent {
    STT,
    VAD,
    TTS,
    LLM,
    VLM,
    WAKEWORD,
    SPEAKER_DIARIZATION
}

// MARK: - Component Health and Status

data class ComponentHealth(
    val isHealthy: Boolean,
    val details: String
)

/**
 * Comprehensive component status matching iOS ComponentStatus
 */
data class ComponentStatus(
    val state: ComponentState,
    val progress: Float? = null,
    val error: Throwable? = null,
    val timestamp: Long = getCurrentTimeMillis(),
    val currentStage: String? = null,
    val metadata: Map<String, Any>? = null
) {
    val isHealthy: Boolean
        get() = state != ComponentState.FAILED && error == null
}

// MARK: - Component Protocol

interface Component {
    val state: ComponentState
    val parameters: ComponentInitParameters

    suspend fun initialize(parameters: ComponentInitParameters)
    suspend fun cleanup()
    suspend fun healthCheck(): ComponentHealth
    suspend fun transitionTo(state: ComponentState)
}

// MARK: - Service Wrapper

/**
 * Service wrapper protocol that allows protocol types to be used with BaseComponent
 */
interface ServiceWrapper<ServiceProtocol : Any> {
    var wrappedService: ServiceProtocol?
}

/**
 * Generic service wrapper for any protocol
 */
class AnyServiceWrapper<T : Any> : ServiceWrapper<T> {
    override var wrappedService: T? = null

    constructor(service: T? = null) {
        this.wrappedService = service
    }
}

// MARK: - Base Component Implementation

/**
 * Simplified base component for all SDK components
 */
abstract class BaseComponent<TService : Any>(
    protected val configuration: ComponentConfiguration,
    serviceContainer: ServiceContainer? = null
) : Component {

    // MARK: - Core Properties

    /**
     * Component type identifier
     */
    abstract val componentType: SDKComponent

    /**
     * Current state
     */
    override var state: ComponentState = ComponentState.NOT_INITIALIZED
        protected set

    /**
     * The service that performs the actual work
     */
    protected var service: TService? = null

    /**
     * Parameters for Component protocol (bridge to configuration)
     */
    override val parameters: ComponentInitParameters
        get() = (configuration as? ComponentInitParameters) ?: EmptyComponentParameters()

    /**
     * Event bus for publishing events
     */
    protected val eventBus = EventBus

    /**
     * Service container reference (can be null for better memory management)
     */
    private var serviceContainer: ServiceContainer? = null

    /**
     * Current processing stage
     */
    protected var currentStage: String? = null

    /**
     * Component status with metadata tracking
     */
    private var _status: ComponentStatus = ComponentStatus(ComponentState.NOT_INITIALIZED)
    val status: ComponentStatus get() = _status

    // MARK: - Initialization

    init {
        this.serviceContainer = serviceContainer ?: ServiceContainer.shared
    }

    // MARK: - Lifecycle

    /**
     * Initialize the component (Component protocol)
     */
    override suspend fun initialize(parameters: ComponentInitParameters) {
        // For now, ignore the parameters since we already have configuration
        initialize()
    }

    /**
     * Initialize the component
     */
    suspend fun initialize() {
        if (state != ComponentState.NOT_INITIALIZED) {
            if (state == ComponentState.READY) {
                return // Already initialized
            }
            throw SDKError.InvalidState("Cannot initialize from state: ${state.name}")
        }

        // Emit state change event
        updateState(ComponentState.INITIALIZING)

        try {
            // Stage: Validation
            currentStage = "validation"
            eventBus.publish(ComponentInitializationEvent.ComponentChecking(
                component = componentType.name,
                modelId = parameters.modelId
            ))
            configuration.validate()

            // Stage: Service Creation
            currentStage = "service_creation"
            eventBus.publish(ComponentInitializationEvent.ComponentInitializing(
                component = componentType.name,
                modelId = parameters.modelId
            ))
            service = createService()

            // Stage: Service Initialization
            currentStage = "service_initialization"
            initializeService()

            // Component ready
            currentStage = null
            updateState(ComponentState.READY)
            eventBus.publish(ComponentInitializationEvent.ComponentReady(
                component = componentType.name,
                modelId = parameters.modelId
            ))
        } catch (e: Exception) {
            // Update status with error information
            _status = ComponentStatus(
                state = ComponentState.FAILED,
                error = e,
                currentStage = currentStage,
                timestamp = getCurrentTimeMillis()
            )
            updateState(ComponentState.FAILED)
            eventBus.publish(ComponentInitializationEvent.ComponentFailed(
                component = componentType.name,
                error = e
            ))
            throw e
        }
    }

    /**
     * Create the service (override in subclass)
     */
    protected abstract suspend fun createService(): TService

    /**
     * Initialize the service (override if needed)
     */
    protected open suspend fun initializeService() {
        // Default: no-op
        // Override in subclass if service needs initialization
    }

    /**
     * Cleanup - Enhanced with proper resource management
     */
    override suspend fun cleanup() {
        if (state == ComponentState.NOT_INITIALIZED) return

        updateState(ComponentState.NOT_INITIALIZED)

        // Allow subclass to perform cleanup
        performCleanup()

        // Clear service reference
        service = null

        // Clear service container reference for better memory management
        serviceContainer = null

        // Reset current stage
        currentStage = null
    }

    /**
     * Perform cleanup (override in subclass if needed)
     */
    protected open suspend fun performCleanup() {
        // Default: no-op
        // Override in subclass for custom cleanup
    }

    // MARK: - State Management

    /**
     * Check if component is ready
     */
    val isReady: Boolean
        get() = state == ComponentState.READY

    /**
     * Ensure component is ready for processing
     */
    @Throws(SDKError::class)
    fun ensureReady() {
        if (state != ComponentState.READY) {
            throw SDKError.ComponentNotReady("$componentType is not ready. Current state: $state")
        }
    }

    /**
     * Update state and emit event
     */
    private fun updateState(newState: ComponentState) {
        val oldState = state
        state = newState

        // Update component status with metadata
        _status = ComponentStatus(
            state = newState,
            currentStage = currentStage,
            timestamp = getCurrentTimeMillis()
        )

        eventBus.publish(ComponentInitializationEvent.ComponentStateChanged(
            component = componentType.name,
            oldState = oldState.name,
            newState = newState.name
        ))
    }

    // MARK: - Component Protocol Requirements

    /**
     * Health check implementation - Enhanced with comprehensive status
     */
    override suspend fun healthCheck(): ComponentHealth {
        return ComponentHealth(
            isHealthy = status.isHealthy,
            details = buildString {
                append("Component: $componentType, ")
                append("State: ${state.name}")
                if (currentStage != null) {
                    append(", Stage: $currentStage")
                }
                if (status.error != null) {
                    append(", Error: ${status.error?.message}")
                }
            }
        )
    }

    /**
     * Get detailed component status
     */
    fun getDetailedStatus(): ComponentStatus = status

    /**
     * Safely get service container (null if cleaned up)
     */
    protected fun getServiceContainer(): ServiceContainer? = serviceContainer

    /**
     * State transition handler
     */
    override suspend fun transitionTo(state: ComponentState) {
        updateState(state)
    }
}

// MARK: - Empty Component Parameters

/**
 * Empty parameters for components that don't need configuration
 */
private class EmptyComponentParameters : ComponentInitParameters {
    override val componentType: SDKComponent = SDKComponent.VAD // Default, not used
    override val modelId: String? = null
    override fun validate() {}
}

// MARK: - Component Events moved to events package

// MARK: - SDK Errors - using the central SDKError from data.models package


// MARK: - Module Registry

/**
 * Enhanced Module Registry supporting multiple providers per component type
 * Matches iOS ModuleRegistry architecture with plugin support
 */
object ModuleRegistry {
    private val sttProviders = mutableListOf<STTServiceProvider>()
    private val vadProviders = mutableListOf<VADServiceProvider>()

    /**
     * Register STT provider (supports multiple providers)
     */
    fun registerSTTProvider(provider: STTServiceProvider) {
        sttProviders.add(provider)
    }

    /**
     * Register VAD provider (supports multiple providers)
     */
    fun registerVADProvider(provider: VADServiceProvider) {
        vadProviders.add(provider)
    }

    /**
     * Get STT provider for specific model (returns first matching provider)
     */
    fun sttProvider(modelId: String? = null): STTServiceProvider? {
        return if (modelId != null) {
            sttProviders.firstOrNull { it.canHandle(modelId) }
        } else {
            sttProviders.firstOrNull()
        }
    }

    /**
     * Get VAD provider for specific model (returns first matching provider)
     */
    fun vadProvider(modelId: String? = null): VADServiceProvider? {
        return if (modelId != null) {
            vadProviders.firstOrNull { it.canHandle(modelId) }
        } else {
            vadProviders.firstOrNull()
        }
    }

    /**
     * Get all STT providers
     */
    fun sttProviders(): List<STTServiceProvider> = sttProviders.toList()

    /**
     * Get all VAD providers
     */
    fun vadProviders(): List<VADServiceProvider> = vadProviders.toList()

    /**
     * Clear all providers (for testing)
     */
    fun clear() {
        sttProviders.clear()
        vadProviders.clear()
    }
}

// MARK: - Service Provider Protocols

interface STTServiceProvider {
    suspend fun createSTTService(configuration: STTConfiguration): STTService
    fun canHandle(modelId: String?): Boolean
    val name: String
}

interface VADServiceProvider {
    suspend fun createVADService(configuration: VADConfiguration): VADService
    fun canHandle(modelId: String?): Boolean
    val name: String
}

// MARK: - VAD Component

/**
 * VAD Component interface
 */
interface VADComponent : Component {
    fun processAudioChunk(audio: FloatArray): VADResult
}

// MARK: - STT Component

/**
 * STT Component interface
 */
interface STTComponent : Component {
    suspend fun transcribe(audioData: ByteArray): TranscriptionResult
    fun transcribeStream(audioFlow: Flow<ByteArray>): Flow<TranscriptionUpdate>
}

// MARK: - VAD Result

/**
 * VAD Result data class
 */
data class VADResult(
    val isSpeech: Boolean,
    val confidence: Float,
    val timestamp: Long = getCurrentTimeMillis()
)

// MARK: - Transcription Result

/**
 * Transcription result data class
 */
data class TranscriptionResult(
    val text: String,
    val confidence: Float,
    val language: String,
    val duration: Double
)

// MARK: - Transcription Update

/**
 * Transcription update for streaming
 */
data class TranscriptionUpdate(
    val text: String,
    val isFinal: Boolean,
    val timestamp: Long = getCurrentTimeMillis()
)
