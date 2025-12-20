package com.runanywhere.sdk.events

import com.runanywhere.sdk.foundation.currentTimeMillis
import kotlin.uuid.ExperimentalUuidApi
import kotlin.uuid.Uuid

// MARK: - Event Destination

/**
 * Where an event should be routed.
 * Mirrors iOS EventDestination enum.
 */
enum class EventDestination {
    /** Only to public EventBus (app developers) */
    PUBLIC_ONLY,

    /** Only to analytics/telemetry (backend) */
    ANALYTICS_ONLY,

    /** Both destinations (default) */
    ALL,
}

// MARK: - Event Category

/**
 * Event categories for filtering/grouping.
 * Mirrors iOS EventCategory enum.
 */
enum class EventCategory(
    val value: String,
) {
    SDK("sdk"),
    MODEL("model"),
    LLM("llm"),
    STT("stt"),
    TTS("tts"),
    VOICE("voice"),
    STORAGE("storage"),
    DEVICE("device"),
    NETWORK("network"),
    ERROR("error"),
    CONFIGURATION("configuration"),
    PERFORMANCE("performance"),
    FRAMEWORK("framework"),
    LOGGING("logging"),
}

// MARK: - SDK Event Protocol

/**
 * Single protocol for ALL SDK events.
 * Mirrors iOS SDKEvent protocol.
 *
 * Every event in the SDK conforms to this interface. The `destination` property
 * tells the router where to send the event:
 * - `.ALL` (default) → EventBus + Analytics
 * - `.PUBLIC_ONLY` → EventBus only
 * - `.ANALYTICS_ONLY` → Analytics only
 *
 * Usage:
 * ```kotlin
 * EventPublisher.track(LLMEvent.GenerationCompleted(...))
 * ```
 */
interface SDKEvent {
    /** Unique identifier for this event instance */
    val id: String

    /** Event type string (used for analytics categorization) */
    val type: String

    /** Category for filtering/routing */
    val category: EventCategory

    /** When the event occurred (epoch millis) */
    val timestamp: Long

    /** Optional session ID for grouping related events */
    val sessionId: String?

    /** Where to route this event */
    val destination: EventDestination

    /** Event properties as key-value pairs (for analytics serialization) */
    val properties: Map<String, String>
}

// Legacy compatibility
@Deprecated("Use EventCategory instead", ReplaceWith("EventCategory"))
enum class SDKEventType {
    INITIALIZATION,
    CONFIGURATION,
    GENERATION,
    MODEL,
    VOICE,
    STORAGE,
    FRAMEWORK,
    DEVICE,
    ERROR,
    PERFORMANCE,
    NETWORK,
    LOGGING,
    ;

    fun toCategory(): EventCategory =
        when (this) {
            INITIALIZATION -> EventCategory.SDK
            CONFIGURATION -> EventCategory.CONFIGURATION
            GENERATION -> EventCategory.LLM
            MODEL -> EventCategory.MODEL
            VOICE -> EventCategory.VOICE
            STORAGE -> EventCategory.STORAGE
            FRAMEWORK -> EventCategory.FRAMEWORK
            DEVICE -> EventCategory.DEVICE
            ERROR -> EventCategory.ERROR
            PERFORMANCE -> EventCategory.PERFORMANCE
            NETWORK -> EventCategory.NETWORK
            LOGGING -> EventCategory.LOGGING
        }
}

// Legacy compat property
@Suppress("DEPRECATION")
val SDKEvent.eventType: SDKEventType
    get() =
        when (category) {
            EventCategory.SDK -> SDKEventType.INITIALIZATION
            EventCategory.CONFIGURATION -> SDKEventType.CONFIGURATION
            EventCategory.LLM -> SDKEventType.GENERATION
            EventCategory.MODEL -> SDKEventType.MODEL
            EventCategory.VOICE -> SDKEventType.VOICE
            EventCategory.STORAGE -> SDKEventType.STORAGE
            EventCategory.FRAMEWORK -> SDKEventType.FRAMEWORK
            EventCategory.DEVICE -> SDKEventType.DEVICE
            EventCategory.ERROR -> SDKEventType.ERROR
            EventCategory.PERFORMANCE -> SDKEventType.PERFORMANCE
            EventCategory.NETWORK -> SDKEventType.NETWORK
            EventCategory.LOGGING -> SDKEventType.LOGGING
            EventCategory.STT -> SDKEventType.VOICE
            EventCategory.TTS -> SDKEventType.VOICE
        }

/**
 * Helper to generate unique event IDs
 */
@OptIn(ExperimentalUuidApi::class)
fun generateEventId(): String = Uuid.random().toString()

/**
 * Base implementation with automatic timestamp and ID generation.
 * Provides sensible defaults matching iOS pattern.
 */
abstract class BaseSDKEvent(
    override val category: EventCategory,
    override val timestamp: Long = currentTimeMillis(),
    override val id: String = generateEventId(),
    override val sessionId: String? = null,
    override val destination: EventDestination = EventDestination.ALL,
) : SDKEvent {
    override val type: String get() = this::class.simpleName ?: "Unknown"
    override val properties: Map<String, String> get() = emptyMap()
}

/**
 * SDK Initialization Events for public API
 */
sealed class SDKInitializationEvent : BaseSDKEvent(EventCategory.SDK) {
    data object Started : SDKInitializationEvent()

    data class ConfigurationLoaded(
        val source: String,
    ) : SDKInitializationEvent()

    data object ServicesBootstrapped : SDKInitializationEvent()

    data object Completed : SDKInitializationEvent()

    data class Failed(
        val error: Throwable,
    ) : SDKInitializationEvent()

    data class StepStarted(
        val step: Int,
        val description: String,
    ) : SDKInitializationEvent()

    data class StepCompleted(
        val step: Int,
        val description: String,
        val durationMs: Long,
    ) : SDKInitializationEvent()
}

/**
 * SDK Configuration Events for public API
 */
sealed class SDKConfigurationEvent : BaseSDKEvent(EventCategory.CONFIGURATION) {
    data object FetchStarted : SDKConfigurationEvent()

    data class FetchCompleted(
        val source: String,
    ) : SDKConfigurationEvent()

    data class FetchFailed(
        val error: Throwable,
    ) : SDKConfigurationEvent()

    data class Loaded(
        val configuration: Map<String, Any>?,
    ) : SDKConfigurationEvent()

    data class Updated(
        val changes: List<String>,
    ) : SDKConfigurationEvent()

    data object SyncStarted : SDKConfigurationEvent()

    data object SyncCompleted : SDKConfigurationEvent()

    data class SyncFailed(
        val error: Throwable,
    ) : SDKConfigurationEvent()

    // Configuration read events - analytics only (internal polling)
    data object SettingsRequested : SDKConfigurationEvent() {
        override val destination: EventDestination = EventDestination.ANALYTICS_ONLY
    }

    data class SettingsRetrieved(
        val settings: Map<String, Any>,
    ) : SDKConfigurationEvent() {
        override val destination: EventDestination = EventDestination.ANALYTICS_ONLY
    }

    data object RoutingPolicyRequested : SDKConfigurationEvent() {
        override val destination: EventDestination = EventDestination.ANALYTICS_ONLY
    }

    data class RoutingPolicyRetrieved(
        val policy: String,
    ) : SDKConfigurationEvent() {
        override val destination: EventDestination = EventDestination.ANALYTICS_ONLY
    }

    data object PrivacyModeRequested : SDKConfigurationEvent() {
        override val destination: EventDestination = EventDestination.ANALYTICS_ONLY
    }

    data class PrivacyModeRetrieved(
        val mode: String,
    ) : SDKConfigurationEvent() {
        override val destination: EventDestination = EventDestination.ANALYTICS_ONLY
    }

    data object AnalyticsStatusRequested : SDKConfigurationEvent() {
        override val destination: EventDestination = EventDestination.ANALYTICS_ONLY
    }

    data class AnalyticsStatusRetrieved(
        val enabled: Boolean,
    ) : SDKConfigurationEvent() {
        override val destination: EventDestination = EventDestination.ANALYTICS_ONLY
    }

    data object SyncRequested : SDKConfigurationEvent() {
        override val destination: EventDestination = EventDestination.ANALYTICS_ONLY
    }
}

/**
 * SDK Generation Events (LLM) for public API
 */
sealed class SDKGenerationEvent : BaseSDKEvent(EventCategory.LLM) {
    // Session events
    data class SessionStarted(
        val generationSessionId: String,
    ) : SDKGenerationEvent()

    data class SessionEnded(
        val generationSessionId: String,
    ) : SDKGenerationEvent()

    // Generation lifecycle
    data class Started(
        val prompt: String,
        val generationSessionId: String? = null,
    ) : SDKGenerationEvent()

    data class FirstTokenGenerated(
        val token: String,
        val latencyMs: Double,
    ) : SDKGenerationEvent()

    // Streaming updates - analytics only (too chatty for public)
    data class TokenGenerated(
        val token: String,
    ) : SDKGenerationEvent() {
        override val destination: EventDestination = EventDestination.ANALYTICS_ONLY
    }

    data class StreamingUpdate(
        val text: String,
        val tokensCount: Int,
    ) : SDKGenerationEvent() {
        override val destination: EventDestination = EventDestination.ANALYTICS_ONLY
    }

    data class Completed(
        val response: String,
        val tokensUsed: Int,
        val latencyMs: Double,
    ) : SDKGenerationEvent()

    data class Failed(
        val error: Throwable,
    ) : SDKGenerationEvent()

    data class Cancelled(
        val generationSessionId: String,
    ) : SDKGenerationEvent()

    // Model events
    data class ModelLoaded(
        val modelId: String,
    ) : SDKGenerationEvent()

    data class ModelUnloaded(
        val modelId: String,
    ) : SDKGenerationEvent()

    // Cost and routing
    data class CostCalculated(
        val amount: Double,
        val savedAmount: Double,
    ) : SDKGenerationEvent()

    data class RoutingDecision(
        val target: String,
        val reason: String,
    ) : SDKGenerationEvent()
}

/**
 * SDK Model Events for public API
 */
sealed class SDKModelEvent : BaseSDKEvent(EventCategory.MODEL) {
    data class LoadStarted(
        val modelId: String,
    ) : SDKModelEvent()

    // Progress events are analytics-only (too frequent for public)
    data class LoadProgress(
        val modelId: String,
        val progress: Double,
    ) : SDKModelEvent() {
        override val destination: EventDestination = EventDestination.ANALYTICS_ONLY
    }

    data class LoadCompleted(
        val modelId: String,
    ) : SDKModelEvent()

    data class LoadFailed(
        val modelId: String,
        val error: Throwable,
    ) : SDKModelEvent()

    data object UnloadStarted : SDKModelEvent()

    data object UnloadCompleted : SDKModelEvent()

    data class UnloadFailed(
        val error: Throwable,
    ) : SDKModelEvent()

    data class DownloadStarted(
        val modelId: String,
    ) : SDKModelEvent()

    // Progress events are analytics-only (too frequent for public)
    data class DownloadProgress(
        val modelId: String,
        val progress: Double,
    ) : SDKModelEvent() {
        override val destination: EventDestination = EventDestination.ANALYTICS_ONLY
    }

    data class DownloadCompleted(
        val modelId: String,
    ) : SDKModelEvent()

    data class DownloadFailed(
        val modelId: String,
        val error: Throwable,
    ) : SDKModelEvent()

    data class DownloadCancelled(
        val modelId: String,
    ) : SDKModelEvent()

    data object ListRequested : SDKModelEvent()

    data class ListCompleted(
        val models: List<com.runanywhere.sdk.models.ModelInfo>,
    ) : SDKModelEvent()

    data class ListFailed(
        val error: Throwable,
    ) : SDKModelEvent()

    data class CatalogLoaded(
        val models: List<String>,
    ) : SDKModelEvent()

    data class DeleteStarted(
        val modelId: String,
    ) : SDKModelEvent()

    data class DeleteCompleted(
        val modelId: String,
    ) : SDKModelEvent()

    data class DeleteFailed(
        val modelId: String,
        val error: Throwable,
    ) : SDKModelEvent()

    data class CustomModelAdded(
        val name: String,
        val url: String,
    ) : SDKModelEvent()

    data class CustomModelRegistered(
        val modelId: String,
        val url: String,
    ) : SDKModelEvent()

    data class CustomModelFailed(
        val name: String,
        val url: String,
        val error: String,
    ) : SDKModelEvent()

    data class BuiltInModelRegistered(
        val modelId: String,
    ) : SDKModelEvent()
}

/**
 * Voice Events (Voice Agent Pipeline)
 */
sealed class SDKVoiceEvent : BaseSDKEvent(EventCategory.VOICE) {
    data object ListeningStarted : SDKVoiceEvent()

    data object ListeningEnded : SDKVoiceEvent()

    data object SpeechDetected : SDKVoiceEvent()

    data object TranscriptionStarted : SDKVoiceEvent()

    // Partial transcriptions are analytics-only (too frequent)
    data class TranscriptionPartial(
        val text: String,
    ) : SDKVoiceEvent() {
        override val destination: EventDestination = EventDestination.ANALYTICS_ONLY
    }

    data class TranscriptionFinal(
        val text: String,
    ) : SDKVoiceEvent()

    data class ResponseGenerated(
        val text: String,
    ) : SDKVoiceEvent()

    data object SynthesisStarted : SDKVoiceEvent()

    // Audio chunks are analytics-only (too frequent)
    data class AudioGenerated(
        val data: ByteArray,
    ) : SDKVoiceEvent() {
        override val destination: EventDestination = EventDestination.ANALYTICS_ONLY
    }

    data object SynthesisCompleted : SDKVoiceEvent()

    data class PipelineError(
        val error: Throwable,
    ) : SDKVoiceEvent()

    data object PipelineStarted : SDKVoiceEvent()

    data object PipelineCompleted : SDKVoiceEvent()

    // VAD events are analytics-only (too frequent for public bus)
    data object VadStarted : SDKVoiceEvent() {
        override val destination: EventDestination = EventDestination.ANALYTICS_ONLY
    }

    data object VadDetected : SDKVoiceEvent() {
        override val destination: EventDestination = EventDestination.ANALYTICS_ONLY
    }

    data object VadEnded : SDKVoiceEvent() {
        override val destination: EventDestination = EventDestination.ANALYTICS_ONLY
    }

    // Processing stage events are analytics-only
    data object SttProcessing : SDKVoiceEvent() {
        override val destination: EventDestination = EventDestination.ANALYTICS_ONLY
    }

    data object LlmProcessing : SDKVoiceEvent() {
        override val destination: EventDestination = EventDestination.ANALYTICS_ONLY
    }

    data object TtsProcessing : SDKVoiceEvent() {
        override val destination: EventDestination = EventDestination.ANALYTICS_ONLY
    }
}

/**
 * SDK Performance Events - mostly analytics-only
 */
sealed class SDKPerformanceEvent : BaseSDKEvent(EventCategory.PERFORMANCE) {
    // Memory and thermal warnings go to public (apps may want to react)
    data class MemoryWarning(
        val usage: Long,
    ) : SDKPerformanceEvent()

    data class ThermalStateChanged(
        val state: String,
    ) : SDKPerformanceEvent()

    // Detailed metrics are analytics-only
    data class LatencyMeasured(
        val operation: String,
        val milliseconds: Double,
    ) : SDKPerformanceEvent() {
        override val destination: EventDestination = EventDestination.ANALYTICS_ONLY
    }

    data class ThroughputMeasured(
        val tokensPerSecond: Double,
    ) : SDKPerformanceEvent() {
        override val destination: EventDestination = EventDestination.ANALYTICS_ONLY
    }
}

/**
 * SDK Network Events - mostly analytics-only
 */
sealed class SDKNetworkEvent : BaseSDKEvent(EventCategory.NETWORK) {
    // Individual request events are analytics-only
    data class RequestStarted(
        val url: String,
    ) : SDKNetworkEvent() {
        override val destination: EventDestination = EventDestination.ANALYTICS_ONLY
    }

    data class RequestCompleted(
        val url: String,
        val statusCode: Int,
    ) : SDKNetworkEvent() {
        override val destination: EventDestination = EventDestination.ANALYTICS_ONLY
    }

    data class RequestFailed(
        val url: String,
        val error: Throwable,
    ) : SDKNetworkEvent() {
        override val destination: EventDestination = EventDestination.ANALYTICS_ONLY
    }

    // Connectivity changes go to public (apps may want to react)
    data class ConnectivityChanged(
        val isOnline: Boolean,
    ) : SDKNetworkEvent()
}

/**
 * SDK Storage Events for public API
 */
sealed class SDKStorageEvent : BaseSDKEvent(EventCategory.STORAGE) {
    data object InfoRequested : SDKStorageEvent()

    data class InfoRetrieved(
        val info: Map<String, Any>,
    ) : SDKStorageEvent()

    data object ModelsRequested : SDKStorageEvent()

    data class ModelsRetrieved(
        val models: List<String>,
    ) : SDKStorageEvent()

    data object ClearCacheStarted : SDKStorageEvent()

    data object ClearCacheCompleted : SDKStorageEvent()

    data class ClearCacheFailed(
        val error: Throwable,
    ) : SDKStorageEvent()

    data object CleanTempStarted : SDKStorageEvent()

    data object CleanTempCompleted : SDKStorageEvent()

    data class CleanTempFailed(
        val error: Throwable,
    ) : SDKStorageEvent()

    data class DeleteModelStarted(
        val modelId: String,
    ) : SDKStorageEvent()

    data class DeleteModelCompleted(
        val modelId: String,
    ) : SDKStorageEvent()

    data class DeleteModelFailed(
        val modelId: String,
        val error: Throwable,
    ) : SDKStorageEvent()
}

/**
 * SDK Framework Events - mostly analytics-only (internal SDK operations)
 */
sealed class SDKFrameworkEvent : BaseSDKEvent(EventCategory.FRAMEWORK, destination = EventDestination.ANALYTICS_ONLY) {
    data class AdapterRegistered(
        val framework: String,
        val name: String,
    ) : SDKFrameworkEvent()

    data object AdaptersRequested : SDKFrameworkEvent()

    data class AdaptersRetrieved(
        val count: Int,
    ) : SDKFrameworkEvent()

    data object FrameworksRequested : SDKFrameworkEvent()

    data class FrameworksRetrieved(
        val frameworks: List<String>,
    ) : SDKFrameworkEvent()

    data object AvailabilityRequested : SDKFrameworkEvent()

    data class AvailabilityRetrieved(
        val availability: List<String>,
    ) : SDKFrameworkEvent()

    data class ModelsForFrameworkRequested(
        val framework: String,
    ) : SDKFrameworkEvent()

    data class ModelsForFrameworkRetrieved(
        val framework: String,
        val models: List<String>,
    ) : SDKFrameworkEvent()

    data class FrameworksForModalityRequested(
        val modality: String,
    ) : SDKFrameworkEvent()

    data class FrameworksForModalityRetrieved(
        val modality: String,
        val frameworks: List<String>,
    ) : SDKFrameworkEvent()
}

/**
 * SDK Device Events - mostly analytics-only (internal SDK operations)
 */
sealed class SDKDeviceEvent : BaseSDKEvent(EventCategory.DEVICE, destination = EventDestination.ANALYTICS_ONLY) {
    data class DeviceInfoCollected(
        val deviceInfo: Map<String, Any>,
    ) : SDKDeviceEvent()

    data class DeviceInfoCollectionFailed(
        val error: Throwable,
    ) : SDKDeviceEvent()

    data class DeviceInfoRefreshed(
        val deviceInfo: Map<String, Any>,
    ) : SDKDeviceEvent()

    data object DeviceInfoSyncStarted : SDKDeviceEvent()

    data object DeviceInfoSyncCompleted : SDKDeviceEvent()

    data class DeviceInfoSyncFailed(
        val error: Throwable,
    ) : SDKDeviceEvent()

    data class DeviceStateChanged(
        val property: String,
        val newValue: String,
    ) : SDKDeviceEvent()
}

/**
 * SDK Logging Events - analytics-only (internal SDK operations)
 */
sealed class SDKLoggingEvent : BaseSDKEvent(EventCategory.LOGGING, destination = EventDestination.ANALYTICS_ONLY) {
    data class ConfigurationUpdated(
        val level: String,
        val consoleEnabled: Boolean,
    ) : SDKLoggingEvent()

    data class LocalLoggingConfigured(
        val enabled: Boolean,
        val maxSizeMB: Int,
        val maxFileCount: Int,
    ) : SDKLoggingEvent()

    data class ComponentLogLevelChanged(
        val component: String,
        val level: String,
    ) : SDKLoggingEvent()

    data class DebugModeChanged(
        val enabled: Boolean,
    ) : SDKLoggingEvent()

    data object FlushStarted : SDKLoggingEvent()

    data object FlushCompleted : SDKLoggingEvent()

    data class FlushFailed(
        val error: String,
    ) : SDKLoggingEvent()
}

/**
 * Events for component initialization lifecycle
 */
sealed class ComponentInitializationEvent : BaseSDKEvent(EventCategory.SDK) {
    // Overall initialization
    data class InitializationStarted(
        val components: List<String>,
    ) : ComponentInitializationEvent()

    data class InitializationCompleted(
        val result: String,
    ) : ComponentInitializationEvent()

    // Component-specific events
    data class ComponentStateChanged(
        val component: String,
        val oldState: String,
        val newState: String,
    ) : ComponentInitializationEvent()

    data class ComponentChecking(
        val component: String,
        val modelId: String?,
    ) : ComponentInitializationEvent()

    data class ComponentDownloadRequired(
        val component: String,
        val modelId: String,
        val sizeBytes: Long,
    ) : ComponentInitializationEvent()

    data class ComponentDownloadStarted(
        val component: String,
        val modelId: String,
    ) : ComponentInitializationEvent()

    // Progress events are analytics-only (too frequent)
    data class ComponentDownloadProgress(
        val component: String,
        val modelId: String,
        val progress: Double,
    ) : ComponentInitializationEvent() {
        override val destination: EventDestination = EventDestination.ANALYTICS_ONLY
    }

    data class ComponentDownloadCompleted(
        val component: String,
        val modelId: String,
    ) : ComponentInitializationEvent()

    data class ComponentDownloadFailed(
        val component: String,
        val modelId: String,
        val error: String,
    ) : ComponentInitializationEvent()

    data class ComponentInitializing(
        val component: String,
        val modelId: String?,
    ) : ComponentInitializationEvent()

    data class ComponentReady(
        val component: String,
        val modelId: String?,
    ) : ComponentInitializationEvent()

    data class ComponentFailed(
        val component: String,
        val error: Throwable,
    ) : ComponentInitializationEvent()

    data class ComponentUnloaded(
        val component: String,
        val modelId: String,
        override val timestamp: Long = currentTimeMillis(),
    ) : ComponentInitializationEvent()

    // Batch events
    data class ParallelInitializationStarted(
        val components: List<String>,
    ) : ComponentInitializationEvent()

    data class SequentialInitializationStarted(
        val components: List<String>,
    ) : ComponentInitializationEvent()

    data object AllComponentsReady : ComponentInitializationEvent()

    data class SomeComponentsReady(
        val ready: List<String>,
        val pending: List<String>,
    ) : ComponentInitializationEvent()

    /**
     * Extract component from event if applicable
     */
    val componentName: String?
        get() =
            when (this) {
                is ComponentStateChanged -> component
                is ComponentChecking -> component
                is ComponentDownloadRequired -> component
                is ComponentDownloadStarted -> component
                is ComponentDownloadProgress -> component
                is ComponentDownloadCompleted -> component
                is ComponentDownloadFailed -> component
                is ComponentInitializing -> component
                is ComponentReady -> component
                is ComponentFailed -> component
                else -> null
            }
}

// Type aliases for compatibility - only include ones that exist
// Note: Some types may not exist yet, they will be implemented as needed
