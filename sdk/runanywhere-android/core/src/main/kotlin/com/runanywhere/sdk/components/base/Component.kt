package com.runanywhere.sdk.components.base

import com.runanywhere.sdk.events.EventBus
import com.runanywhere.sdk.events.ComponentEvent
import com.runanywhere.sdk.components.stt.STTConfiguration
import com.runanywhere.sdk.components.stt.STTService
import com.runanywhere.sdk.components.vad.VADConfiguration
import com.runanywhere.sdk.components.vad.VADService
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.FlowCollector
import kotlinx.coroutines.flow.flow
import java.util.Date

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
    val timestamp: Date
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
    WAKEWORD
}

// MARK: - Component Health

data class ComponentHealth(
    val isHealthy: Boolean,
    val details: String
)

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
    protected var serviceContainer: ServiceContainer? = null
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
     * Current processing stage
     */
    protected var currentStage: String? = null

    // MARK: - Initialization

    init {
        if (serviceContainer == null) {
            serviceContainer = ServiceContainer.instance
        }
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
            throw SDKError.InvalidState("Cannot initialize from state: $state")
        }

        // Emit state change event
        updateState(ComponentState.INITIALIZING)

        try {
            // Stage: Validation
            currentStage = "validation"
            // Note: Component events need proper EventBus integration
            // TODO: Add component-specific event publishing when EventBus supports ComponentEvents
            configuration.validate()

            // Stage: Service Creation
            currentStage = "service_creation"
            // TODO: Add component initialization event publishing
            service = createService()

            // Stage: Service Initialization
            currentStage = "service_initialization"
            initializeService()

            // Component ready
            currentStage = null
            updateState(ComponentState.READY)
            // TODO: Add component ready event publishing
        } catch (e: Exception) {
            updateState(ComponentState.FAILED)
            // TODO: Add component failure event publishing
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
     * Cleanup
     */
    override suspend fun cleanup() {
        if (state == ComponentState.NOT_INITIALIZED) return

        state = ComponentState.NOT_INITIALIZED

        // Allow subclass to perform cleanup
        performCleanup()

        // Clear service reference
        service = null

        state = ComponentState.NOT_INITIALIZED
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
        // TODO: Add component state change event publishing
    }

    // MARK: - Component Protocol Requirements

    /**
     * Health check implementation
     */
    override suspend fun healthCheck(): ComponentHealth {
        return ComponentHealth(isReady, "Component state: ${state.name}")
    }

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

// MARK: - SDK Errors

sealed class SDKError : Exception() {
    data class InvalidState(override val message: String) : SDKError()
    data class ComponentNotReady(override val message: String) : SDKError()
    data class ComponentNotInitialized(override val message: String) : SDKError()
    data class ValidationFailed(override val message: String) : SDKError()
    data class ServiceNotAvailable(override val message: String) : SDKError()
    data class ModelNotFound(override val message: String) : SDKError()
}

// MARK: - Service Container

object ServiceContainer {
    val instance: ServiceContainer = this
    private val services = mutableMapOf<String, Any>()

    fun <T : Any> register(key: String, service: T) {
        services[key] = service
    }

    @Suppress("UNCHECKED_CAST")
    fun <T : Any> get(key: String): T? {
        return services[key] as? T
    }
}

// MARK: - Module Registry

object ModuleRegistry {
    private var sttProvider: STTServiceProvider? = null
    private var vadProvider: VADServiceProvider? = null

    fun registerSTTProvider(provider: STTServiceProvider) {
        sttProvider = provider
    }

    fun registerVADProvider(provider: VADServiceProvider) {
        vadProvider = provider
    }

    fun sttProvider(modelId: String?): STTServiceProvider? {
        return sttProvider?.takeIf { it.canHandle(modelId) }
    }

    fun vadProvider(modelId: String?): VADServiceProvider? {
        return vadProvider?.takeIf { it.canHandle(modelId) }
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
    val timestamp: Long = System.currentTimeMillis()
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
    val timestamp: Long = System.currentTimeMillis()
)
