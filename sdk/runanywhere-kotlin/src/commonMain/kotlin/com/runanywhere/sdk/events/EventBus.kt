package com.runanywhere.sdk.events

import com.runanywhere.sdk.data.models.ConfigurationData
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch

/**
 * Central event bus for SDK-wide event distribution.
 * Mirrors iOS EventBus functionality.
 *
 * Consumer-facing pub/sub system. App developers subscribe here to receive SDK events.
 * Events are filtered by their `destination` property before being published here.
 *
 * Usage:
 * ```kotlin
 * // Subscribe to all events
 * EventBus.events.collect { event -> ... }
 *
 * // Subscribe to a specific category
 * EventBus.events(EventCategory.LLM).collect { event -> ... }
 *
 * // Closure-based subscription
 * EventBus.on<SDKGenerationEvent>(scope) { event -> ... }
 * ```
 */
object EventBus {
    // Main events publisher - only events with PUBLIC_ONLY or ALL destination
    private val _events = MutableSharedFlow<SDKEvent>()

    /**
     * All public events stream.
     * Only events with destination != ANALYTICS_ONLY are published here.
     */
    val events: SharedFlow<SDKEvent> = _events.asSharedFlow()

    /**
     * Get events filtered by category.
     */
    fun events(category: EventCategory): Flow<SDKEvent> = events.filter { it.category == category }

    // MARK: - Legacy typed event publishers (for backwards compatibility)

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

    private val _loggingEvents = MutableSharedFlow<SDKLoggingEvent>()
    val loggingEvents: SharedFlow<SDKLoggingEvent> = _loggingEvents.asSharedFlow()

    private val _componentEvents = MutableSharedFlow<ComponentInitializationEvent>()
    val componentEvents: SharedFlow<ComponentInitializationEvent> = _componentEvents.asSharedFlow()

    // Legacy: All events publisher (now just an alias)
    @Deprecated("Use 'events' instead", ReplaceWith("events"))
    val allEvents: SharedFlow<SDKEvent> get() = events

    // Legacy support - Speaker Diarization Events
    private val _speakerDiarizationEvents = MutableSharedFlow<com.runanywhere.sdk.features.speakerdiarization.SpeakerDiarizationEvent>()
    val speakerDiarizationEvents: SharedFlow<com.runanywhere.sdk.features.speakerdiarization.SpeakerDiarizationEvent> =
        _speakerDiarizationEvents
            .asSharedFlow()

    // Legacy support - Bootstrap Events
    private val _bootstrapEvents = MutableSharedFlow<SDKBootstrapEvent>()
    val bootstrapEvents: SharedFlow<SDKBootstrapEvent> = _bootstrapEvents.asSharedFlow()

    // MARK: - Internal Event Publishing
    // Note: Components should use EventPublisher.track() instead of calling these directly

    /**
     * Internal: Publish an event to the main events stream.
     * This is called by EventPublisher after routing checks.
     */
    internal fun publish(event: SDKEvent) {
        _events.tryEmit(event)
    }

    /**
     * Publish an initialization event
     */
    fun publish(event: SDKInitializationEvent) {
        _initializationEvents.tryEmit(event)
        _events.tryEmit(event as SDKEvent)
    }

    /**
     * Publish a configuration event
     */
    fun publish(event: SDKConfigurationEvent) {
        _configurationEvents.tryEmit(event)
        _events.tryEmit(event as SDKEvent)
    }

    /**
     * Publish a generation event
     */
    fun publish(event: SDKGenerationEvent) {
        _generationEvents.tryEmit(event)
        _events.tryEmit(event as SDKEvent)
    }

    /**
     * Publish a model event
     */
    fun publish(event: SDKModelEvent) {
        _modelEvents.tryEmit(event)
        _events.tryEmit(event as SDKEvent)
    }

    /**
     * Publish a voice event
     */
    fun publish(event: SDKVoiceEvent) {
        _voiceEvents.tryEmit(event)
        _events.tryEmit(event as SDKEvent)
    }

    /**
     * Publish a performance event
     */
    fun publish(event: SDKPerformanceEvent) {
        _performanceEvents.tryEmit(event)
        _events.tryEmit(event as SDKEvent)
    }

    /**
     * Publish a network event
     */
    fun publish(event: SDKNetworkEvent) {
        _networkEvents.tryEmit(event)
        _events.tryEmit(event as SDKEvent)
    }

    /**
     * Publish a storage event
     */
    fun publish(event: SDKStorageEvent) {
        _storageEvents.tryEmit(event)
        _events.tryEmit(event as SDKEvent)
    }

    /**
     * Publish a framework event
     */
    fun publish(event: SDKFrameworkEvent) {
        _frameworkEvents.tryEmit(event)
        _events.tryEmit(event as SDKEvent)
    }

    /**
     * Publish a device event
     */
    fun publish(event: SDKDeviceEvent) {
        _deviceEvents.tryEmit(event)
        _events.tryEmit(event as SDKEvent)
    }

    /**
     * Publish a logging event
     */
    fun publish(event: SDKLoggingEvent) {
        _loggingEvents.tryEmit(event)
        _events.tryEmit(event as SDKEvent)
    }

    /**
     * Publish a component initialization event
     */
    fun publish(event: ComponentInitializationEvent) {
        _componentEvents.tryEmit(event)
        _events.tryEmit(event as SDKEvent)
    }

    /**
     * Generic event publisher - routes to typed publisher + main events
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
            is SDKLoggingEvent -> publish(event)
            is ComponentInitializationEvent -> publish(event)
            else -> _events.tryEmit(event)
        }
    }

    // Legacy support method for ComponentEvent (excluding ComponentInitializationEvent)
    @Suppress("DEPRECATION", "UNUSED_PARAMETER")
    fun publishComponentEvent(event: ComponentEvent) {
        // For ComponentEvent types, emit a generic SDK event
        _events.tryEmit(object : BaseSDKEvent(EventCategory.SDK) {})
    }

    fun publish(event: com.runanywhere.sdk.features.speakerdiarization.SpeakerDiarizationEvent) {
        _speakerDiarizationEvents.tryEmit(event)
    }

    fun publish(event: SDKBootstrapEvent) {
        _bootstrapEvents.tryEmit(event)
    }

    val shared = EventBus
}

// MARK: - Convenience Extensions

/**
 * Subscribe to events with a closure.
 * Only receives events with destination != ANALYTICS_ONLY.
 */
inline fun <reified T : SDKEvent> EventBus.on(
    scope: CoroutineScope,
    crossinline handler: (T) -> Unit,
): Job =
    scope.launch {
        events
            .filterIsInstance<T>()
            .collect { event ->
                handler(event)
            }
    }

/**
 * Subscribe to events by category with a closure.
 */
fun EventBus.on(
    category: EventCategory,
    scope: CoroutineScope,
    handler: (SDKEvent) -> Unit,
): Job =
    scope.launch {
        events(category).collect { event ->
            handler(event)
        }
    }

/**
 * Subscribe to specific initialization events
 */
fun EventBus.onInitialization(
    scope: CoroutineScope,
    handler: (SDKInitializationEvent) -> Unit,
): Job =
    scope.launch {
        initializationEvents.collect { event ->
            handler(event)
        }
    }

/**
 * Subscribe to specific generation events
 */
fun EventBus.onGeneration(
    scope: CoroutineScope,
    handler: (SDKGenerationEvent) -> Unit,
): Job =
    scope.launch {
        generationEvents.collect { event ->
            handler(event)
        }
    }

/**
 * Subscribe to specific model events
 */
fun EventBus.onModel(
    scope: CoroutineScope,
    handler: (SDKModelEvent) -> Unit,
): Job =
    scope.launch {
        modelEvents.collect { event ->
            handler(event)
        }
    }

/**
 * Subscribe to specific voice events
 */
fun EventBus.onVoice(
    scope: CoroutineScope,
    handler: (SDKVoiceEvent) -> Unit,
): Job =
    scope.launch {
        voiceEvents.collect { event ->
            handler(event)
        }
    }

/**
 * Subscribe to specific performance events
 */
fun EventBus.onPerformance(
    scope: CoroutineScope,
    handler: (SDKPerformanceEvent) -> Unit,
): Job =
    scope.launch {
        performanceEvents.collect { event ->
            handler(event)
        }
    }

/**
 * Subscribe to specific network events
 */
fun EventBus.onNetwork(
    scope: CoroutineScope,
    handler: (SDKNetworkEvent) -> Unit,
): Job =
    scope.launch {
        networkEvents.collect { event ->
            handler(event)
        }
    }

/**
 * Subscribe to specific storage events
 */
fun EventBus.onStorage(
    scope: CoroutineScope,
    handler: (SDKStorageEvent) -> Unit,
): Job =
    scope.launch {
        storageEvents.collect { event ->
            handler(event)
        }
    }

/**
 * Subscribe to specific framework events
 */
fun EventBus.onFramework(
    scope: CoroutineScope,
    handler: (SDKFrameworkEvent) -> Unit,
): Job =
    scope.launch {
        frameworkEvents.collect { event ->
            handler(event)
        }
    }

/**
 * Subscribe to specific device events
 */
fun EventBus.onDevice(
    scope: CoroutineScope,
    handler: (SDKDeviceEvent) -> Unit,
): Job =
    scope.launch {
        deviceEvents.collect { event ->
            handler(event)
        }
    }

/**
 * Subscribe to component initialization events
 */
fun EventBus.onComponentInitialization(
    scope: CoroutineScope,
    handler: (ComponentInitializationEvent) -> Unit,
): Job =
    scope.launch {
        componentEvents.collect { event ->
            handler(event)
        }
    }

/**
 * Subscribe to specific component events
 */
fun EventBus.onComponent(
    componentName: String,
    scope: CoroutineScope,
    handler: (ComponentInitializationEvent) -> Unit,
): Job =
    scope.launch {
        componentEvents
            .filter { it.componentName == componentName }
            .collect { event ->
                handler(event)
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

    data class NetworkServicesConfigurationFailed(
        val error: String,
    ) : SDKBootstrapEvent()

    // Step 2: Device Information Collection and Sync
    data class DeviceInfoCollected(
        val deviceInfo: com.runanywhere.sdk.data.models.DeviceInfoData,
    ) : SDKBootstrapEvent()

    data class DeviceInfoCollectionFailed(
        val error: String,
    ) : SDKBootstrapEvent()

    data class DeviceInfoSynced(
        val deviceInfo: com.runanywhere.sdk.data.models.DeviceInfoData,
    ) : SDKBootstrapEvent()

    data class DeviceInfoSyncFailed(
        val error: String,
    ) : SDKBootstrapEvent()

    // Step 3: Configuration Service with Repository Pattern
    data class ConfigurationLoaded(
        val config: ConfigurationData,
    ) : SDKBootstrapEvent()

    data class ConfigurationLoadFailed(
        val error: String,
    ) : SDKBootstrapEvent()

    // Step 4: Model Catalog Sync from Backend
    data class ModelCatalogSynced(
        val models: List<com.runanywhere.sdk.models.ModelInfo>,
    ) : SDKBootstrapEvent()

    data class ModelCatalogSyncFailed(
        val error: String,
    ) : SDKBootstrapEvent()

    // Step 5: Model Registry Initialization
    object ModelRegistryInitialized : SDKBootstrapEvent()

    data class ModelRegistryInitializationFailed(
        val error: String,
    ) : SDKBootstrapEvent()

    // Step 6: Memory Management Configuration
    data class MemoryConfigured(
        val threshold: Long,
    ) : SDKBootstrapEvent()

    data class MemoryConfigurationFailed(
        val error: String,
    ) : SDKBootstrapEvent()

    // Step 7: Voice Services Initialization (Optional)
    object VoiceServicesInitialized : SDKBootstrapEvent()

    data class VoiceServicesInitializationFailed(
        val error: String,
    ) : SDKBootstrapEvent()

    // Step 8: Analytics Initialization
    object AnalyticsInitialized : SDKBootstrapEvent()

    data class AnalyticsInitializationFailed(
        val error: String,
    ) : SDKBootstrapEvent()

    // Bootstrap start/completion
    object BootstrapStarted : SDKBootstrapEvent()

    object BootstrapCompleted : SDKBootstrapEvent()

    data class BootstrapFailed(
        val step: String,
        val error: String,
    ) : SDKBootstrapEvent()
}

// Device Events are now defined in SDKEvent.kt to avoid duplication

// Import ComponentEvent from STTEvents for use in EventBus
// Note: ComponentEvent and related classes are defined in STTEvents.kt
