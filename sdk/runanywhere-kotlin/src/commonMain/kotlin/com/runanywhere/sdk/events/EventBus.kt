package com.runanywhere.sdk.events

import com.runanywhere.sdk.data.models.ConfigurationData
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch

/**
 * Central event bus for SDK-wide event distribution
 * Thread-safe event bus mirroring iOS EventBus functionality
 */
object EventBus {

    // Event publishers for each event type
    private val _initializationEvents = MutableSharedFlow<SDKInitializationEvent>()
    val initializationEvents: SharedFlow<SDKInitializationEvent> = _initializationEvents.asSharedFlow()

    private val _configurationEvents = MutableSharedFlow<SDKConfigurationEvent>()
    val configurationEvents: SharedFlow<SDKConfigurationEvent> = _configurationEvents.asSharedFlow()

    private val _generationEvents = MutableSharedFlow<SDKGenerationEvent>()
    val generationEvents: SharedFlow<SDKGenerationEvent> = _generationEvents.asSharedFlow()

    private val _modelEvents = MutableSharedFlow<SDKModelEvent>()
    val modelEvents: SharedFlow<SDKModelEvent> = _modelEvents.asSharedFlow()

    private val _voiceEvents = MutableSharedFlow<SDKVoiceEvent>()
    val voiceEvents: SharedFlow<SDKVoiceEvent> = _voiceEvents.asSharedFlow()

    private val _performanceEvents = MutableSharedFlow<SDKPerformanceEvent>()
    val performanceEvents: SharedFlow<SDKPerformanceEvent> = _performanceEvents.asSharedFlow()

    private val _networkEvents = MutableSharedFlow<SDKNetworkEvent>()
    val networkEvents: SharedFlow<SDKNetworkEvent> = _networkEvents.asSharedFlow()

    private val _storageEvents = MutableSharedFlow<SDKStorageEvent>()
    val storageEvents: SharedFlow<SDKStorageEvent> = _storageEvents.asSharedFlow()

    private val _frameworkEvents = MutableSharedFlow<SDKFrameworkEvent>()
    val frameworkEvents: SharedFlow<SDKFrameworkEvent> = _frameworkEvents.asSharedFlow()

    private val _deviceEvents = MutableSharedFlow<SDKDeviceEvent>()
    val deviceEvents: SharedFlow<SDKDeviceEvent> = _deviceEvents.asSharedFlow()

    private val _componentEvents = MutableSharedFlow<ComponentInitializationEvent>()
    val componentEvents: SharedFlow<ComponentInitializationEvent> = _componentEvents.asSharedFlow()

    // All events publisher
    private val _allEvents = MutableSharedFlow<SDKEvent>()
    val allEvents: SharedFlow<SDKEvent> = _allEvents.asSharedFlow()

    // Legacy support - Speaker Diarization Events
    private val _speakerDiarizationEvents = MutableSharedFlow<com.runanywhere.sdk.components.speakerdiarization.SpeakerDiarizationEvent>()
    val speakerDiarizationEvents: SharedFlow<com.runanywhere.sdk.components.speakerdiarization.SpeakerDiarizationEvent> = _speakerDiarizationEvents.asSharedFlow()

    // Legacy support - Bootstrap Events
    private val _bootstrapEvents = MutableSharedFlow<SDKBootstrapEvent>()
    val bootstrapEvents: SharedFlow<SDKBootstrapEvent> = _bootstrapEvents.asSharedFlow()

    // MARK: - Event Publishing

    /**
     * Publish an initialization event
     */
    fun publish(event: SDKInitializationEvent) {
        _initializationEvents.tryEmit(event)
        _allEvents.tryEmit(event as SDKEvent)
    }

    /**
     * Publish a configuration event
     */
    fun publish(event: SDKConfigurationEvent) {
        _configurationEvents.tryEmit(event)
        _allEvents.tryEmit(event as SDKEvent)
    }

    /**
     * Publish a generation event
     */
    fun publish(event: SDKGenerationEvent) {
        _generationEvents.tryEmit(event)
        _allEvents.tryEmit(event as SDKEvent)
    }

    /**
     * Publish a model event
     */
    fun publish(event: SDKModelEvent) {
        _modelEvents.tryEmit(event)
        _allEvents.tryEmit(event as SDKEvent)
    }

    /**
     * Publish a voice event
     */
    fun publish(event: SDKVoiceEvent) {
        _voiceEvents.tryEmit(event)
        _allEvents.tryEmit(event as SDKEvent)
    }

    /**
     * Publish a performance event
     */
    fun publish(event: SDKPerformanceEvent) {
        _performanceEvents.tryEmit(event)
        _allEvents.tryEmit(event as SDKEvent)
    }

    /**
     * Publish a network event
     */
    fun publish(event: SDKNetworkEvent) {
        _networkEvents.tryEmit(event)
        _allEvents.tryEmit(event as SDKEvent)
    }

    /**
     * Publish a storage event
     */
    fun publish(event: SDKStorageEvent) {
        _storageEvents.tryEmit(event)
        _allEvents.tryEmit(event as SDKEvent)
    }

    /**
     * Publish a framework event
     */
    fun publish(event: SDKFrameworkEvent) {
        _frameworkEvents.tryEmit(event)
        _allEvents.tryEmit(event as SDKEvent)
    }

    /**
     * Publish a device event
     */
    fun publish(event: SDKDeviceEvent) {
        _deviceEvents.tryEmit(event)
        _allEvents.tryEmit(event as SDKEvent)
    }

    /**
     * Publish a component initialization event
     */
    fun publish(event: ComponentInitializationEvent) {
        _componentEvents.tryEmit(event)
        _allEvents.tryEmit(event as SDKEvent)
    }

    /**
     * Generic event publisher - avoid overload conflicts by using explicit types
     */
    fun publishSDKEvent(event: SDKEvent) {
        when (event) {
            is SDKInitializationEvent -> publish(event)
            is SDKConfigurationEvent -> publish(event)
            is SDKGenerationEvent -> publish(event)
            is SDKModelEvent -> publish(event)
            is SDKVoiceEvent -> publish(event)
            is SDKPerformanceEvent -> publish(event)
            is SDKNetworkEvent -> publish(event)
            is SDKStorageEvent -> publish(event)
            is SDKFrameworkEvent -> publish(event)
            is SDKDeviceEvent -> publish(event)
            is ComponentInitializationEvent -> publish(event)
            else -> _allEvents.tryEmit(event)
        }
    }

    // Legacy support method for ComponentEvent (excluding ComponentInitializationEvent)
    fun publishComponentEvent(event: ComponentEvent) {
        // For ComponentEvent types, just emit to all events
        _allEvents.tryEmit(object : BaseSDKEvent(SDKEventType.INITIALIZATION) {})
    }

    fun publish(event: com.runanywhere.sdk.components.speakerdiarization.SpeakerDiarizationEvent) {
        _speakerDiarizationEvents.tryEmit(event)
    }

    fun publish(event: SDKBootstrapEvent) {
        _bootstrapEvents.tryEmit(event)
    }

    val shared = EventBus
}

// MARK: - Convenience Extensions

/**
 * Subscribe to events with a closure
 */
inline fun <reified T : SDKEvent> EventBus.on(
    scope: CoroutineScope,
    crossinline handler: (T) -> Unit
): Job {
    return scope.launch {
        allEvents
            .filterIsInstance<T>()
            .collect { event ->
                handler(event)
            }
    }
}

/**
 * Subscribe to specific initialization events
 */
fun EventBus.onInitialization(
    scope: CoroutineScope,
    handler: (SDKInitializationEvent) -> Unit
): Job {
    return scope.launch {
        initializationEvents.collect { event ->
            handler(event)
        }
    }
}

/**
 * Subscribe to specific generation events
 */
fun EventBus.onGeneration(
    scope: CoroutineScope,
    handler: (SDKGenerationEvent) -> Unit
): Job {
    return scope.launch {
        generationEvents.collect { event ->
            handler(event)
        }
    }
}

/**
 * Subscribe to specific model events
 */
fun EventBus.onModel(
    scope: CoroutineScope,
    handler: (SDKModelEvent) -> Unit
): Job {
    return scope.launch {
        modelEvents.collect { event ->
            handler(event)
        }
    }
}

/**
 * Subscribe to specific voice events
 */
fun EventBus.onVoice(
    scope: CoroutineScope,
    handler: (SDKVoiceEvent) -> Unit
): Job {
    return scope.launch {
        voiceEvents.collect { event ->
            handler(event)
        }
    }
}

/**
 * Subscribe to specific performance events
 */
fun EventBus.onPerformance(
    scope: CoroutineScope,
    handler: (SDKPerformanceEvent) -> Unit
): Job {
    return scope.launch {
        performanceEvents.collect { event ->
            handler(event)
        }
    }
}

/**
 * Subscribe to specific network events
 */
fun EventBus.onNetwork(
    scope: CoroutineScope,
    handler: (SDKNetworkEvent) -> Unit
): Job {
    return scope.launch {
        networkEvents.collect { event ->
            handler(event)
        }
    }
}

/**
 * Subscribe to specific storage events
 */
fun EventBus.onStorage(
    scope: CoroutineScope,
    handler: (SDKStorageEvent) -> Unit
): Job {
    return scope.launch {
        storageEvents.collect { event ->
            handler(event)
        }
    }
}

/**
 * Subscribe to specific framework events
 */
fun EventBus.onFramework(
    scope: CoroutineScope,
    handler: (SDKFrameworkEvent) -> Unit
): Job {
    return scope.launch {
        frameworkEvents.collect { event ->
            handler(event)
        }
    }
}

/**
 * Subscribe to specific device events
 */
fun EventBus.onDevice(
    scope: CoroutineScope,
    handler: (SDKDeviceEvent) -> Unit
): Job {
    return scope.launch {
        deviceEvents.collect { event ->
            handler(event)
        }
    }
}

/**
 * Subscribe to component initialization events
 */
fun EventBus.onComponentInitialization(
    scope: CoroutineScope,
    handler: (ComponentInitializationEvent) -> Unit
): Job {
    return scope.launch {
        componentEvents.collect { event ->
            handler(event)
        }
    }
}

/**
 * Subscribe to specific component events
 */
fun EventBus.onComponent(
    componentName: String,
    scope: CoroutineScope,
    handler: (ComponentInitializationEvent) -> Unit
): Job {
    return scope.launch {
        componentEvents
            .filter { it.componentName == componentName }
            .collect { event ->
                handler(event)
            }
    }
}

// All event definitions have been moved to SDKEvent.kt for better organization

/**
 * Bootstrap Events - For detailed 8-step initialization tracking
 * Matches iOS bootstrap process events
 */
sealed class SDKBootstrapEvent {
    // Step 1: Network Services Configuration
    object NetworkServicesConfigured : SDKBootstrapEvent()
    data class NetworkServicesConfigurationFailed(val error: String) : SDKBootstrapEvent()

    // Step 2: Device Information Collection and Sync
    data class DeviceInfoCollected(val deviceInfo: com.runanywhere.sdk.data.models.DeviceInfoData) : SDKBootstrapEvent()
    data class DeviceInfoCollectionFailed(val error: String) : SDKBootstrapEvent()
    data class DeviceInfoSynced(val deviceInfo: com.runanywhere.sdk.data.models.DeviceInfoData) : SDKBootstrapEvent()
    data class DeviceInfoSyncFailed(val error: String) : SDKBootstrapEvent()

    // Step 3: Configuration Service with Repository Pattern
    data class ConfigurationLoaded(val config: ConfigurationData) : SDKBootstrapEvent()
    data class ConfigurationLoadFailed(val error: String) : SDKBootstrapEvent()

    // Step 4: Model Catalog Sync from Backend
    data class ModelCatalogSynced(val models: List<com.runanywhere.sdk.models.ModelInfo>) : SDKBootstrapEvent()
    data class ModelCatalogSyncFailed(val error: String) : SDKBootstrapEvent()

    // Step 5: Model Registry Initialization
    object ModelRegistryInitialized : SDKBootstrapEvent()
    data class ModelRegistryInitializationFailed(val error: String) : SDKBootstrapEvent()

    // Step 6: Memory Management Configuration
    data class MemoryConfigured(val threshold: Long) : SDKBootstrapEvent()
    data class MemoryConfigurationFailed(val error: String) : SDKBootstrapEvent()

    // Step 7: Voice Services Initialization (Optional)
    object VoiceServicesInitialized : SDKBootstrapEvent()
    data class VoiceServicesInitializationFailed(val error: String) : SDKBootstrapEvent()

    // Step 8: Analytics Initialization
    object AnalyticsInitialized : SDKBootstrapEvent()
    data class AnalyticsInitializationFailed(val error: String) : SDKBootstrapEvent()

    // Bootstrap start/completion
    object BootstrapStarted : SDKBootstrapEvent()
    object BootstrapCompleted : SDKBootstrapEvent()
    data class BootstrapFailed(val step: String, val error: String) : SDKBootstrapEvent()
}

// Device Events are now defined in SDKEvent.kt to avoid duplication

// Import ComponentEvent from STTEvents for use in EventBus
// Note: ComponentEvent and related classes are defined in STTEvents.kt
