package com.runanywhere.sdk.events

import kotlinx.datetime.Instant
import com.runanywhere.sdk.foundation.currentTimeMillis

/**
 * Base interface for all SDK events
 * Mirrors iOS SDKEvent protocol
 */
interface SDKEvent {
    val timestamp: Long  // Use epoch millis instead of Instant to avoid kotlin.time issues
    val eventType: SDKEventType
}

/**
 * Event types for categorization
 * Mirrors iOS SDKEventType enum
 */
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
    NETWORK
}

/**
 * Base implementation with automatic timestamp generation
 */
abstract class BaseSDKEvent(
    override val eventType: SDKEventType,
    override val timestamp: Long = currentTimeMillis()
) : SDKEvent

/**
 * SDK Initialization Events for public API
 */
sealed class SDKInitializationEvent : BaseSDKEvent(SDKEventType.INITIALIZATION) {
    object Started : SDKInitializationEvent()
    data class ConfigurationLoaded(val source: String) : SDKInitializationEvent()
    object ServicesBootstrapped : SDKInitializationEvent()
    object Completed : SDKInitializationEvent()
    data class Failed(val error: Throwable) : SDKInitializationEvent()
    data class StepStarted(val step: Int, val description: String) : SDKInitializationEvent()
    data class StepCompleted(val step: Int, val description: String, val durationMs: Long) : SDKInitializationEvent()
}

/**
 * SDK Configuration Events for public API
 */
sealed class SDKConfigurationEvent : BaseSDKEvent(SDKEventType.CONFIGURATION) {
    object FetchStarted : SDKConfigurationEvent()
    data class FetchCompleted(val source: String) : SDKConfigurationEvent()
    data class FetchFailed(val error: Throwable) : SDKConfigurationEvent()
    data class Loaded(val configuration: Map<String, Any>?) : SDKConfigurationEvent()
    data class Updated(val changes: List<String>) : SDKConfigurationEvent()
    object SyncStarted : SDKConfigurationEvent()
    object SyncCompleted : SDKConfigurationEvent()
    data class SyncFailed(val error: Throwable) : SDKConfigurationEvent()

    // Configuration read events
    object SettingsRequested : SDKConfigurationEvent()
    data class SettingsRetrieved(val settings: Map<String, Any>) : SDKConfigurationEvent()
    object RoutingPolicyRequested : SDKConfigurationEvent()
    data class RoutingPolicyRetrieved(val policy: String) : SDKConfigurationEvent()
    object PrivacyModeRequested : SDKConfigurationEvent()
    data class PrivacyModeRetrieved(val mode: String) : SDKConfigurationEvent()
    object AnalyticsStatusRequested : SDKConfigurationEvent()
    data class AnalyticsStatusRetrieved(val enabled: Boolean) : SDKConfigurationEvent()
    object SyncRequested : SDKConfigurationEvent()
}

/**
 * SDK Generation Events for public API
 */
sealed class SDKGenerationEvent : BaseSDKEvent(SDKEventType.GENERATION) {
    // Session events
    data class SessionStarted(val sessionId: String) : SDKGenerationEvent()
    data class SessionEnded(val sessionId: String) : SDKGenerationEvent()

    // Generation lifecycle
    data class Started(val prompt: String, val sessionId: String? = null) : SDKGenerationEvent()
    data class FirstTokenGenerated(val token: String, val latencyMs: Double) : SDKGenerationEvent()
    data class TokenGenerated(val token: String) : SDKGenerationEvent()
    data class StreamingUpdate(val text: String, val tokensCount: Int) : SDKGenerationEvent()
    data class Completed(val response: String, val tokensUsed: Int, val latencyMs: Double) : SDKGenerationEvent()
    data class Failed(val error: Throwable) : SDKGenerationEvent()
    data class Cancelled(val sessionId: String) : SDKGenerationEvent()

    // Model events
    data class ModelLoaded(val modelId: String) : SDKGenerationEvent()
    data class ModelUnloaded(val modelId: String) : SDKGenerationEvent()

    // Cost and routing
    data class CostCalculated(val amount: Double, val savedAmount: Double) : SDKGenerationEvent()
    data class RoutingDecision(val target: String, val reason: String) : SDKGenerationEvent()
}

/**
 * SDK Model Events for public API
 */
sealed class SDKModelEvent : BaseSDKEvent(SDKEventType.MODEL) {
    data class LoadStarted(val modelId: String) : SDKModelEvent()
    data class LoadProgress(val modelId: String, val progress: Double) : SDKModelEvent()
    data class LoadCompleted(val modelId: String) : SDKModelEvent()
    data class LoadFailed(val modelId: String, val error: Throwable) : SDKModelEvent()
    object UnloadStarted : SDKModelEvent()
    object UnloadCompleted : SDKModelEvent()
    data class UnloadFailed(val error: Throwable) : SDKModelEvent()
    data class DownloadStarted(val modelId: String) : SDKModelEvent()
    data class DownloadProgress(val modelId: String, val progress: Double) : SDKModelEvent()
    data class DownloadCompleted(val modelId: String) : SDKModelEvent()
    data class DownloadFailed(val modelId: String, val error: Throwable) : SDKModelEvent()
    data class DownloadCancelled(val modelId: String) : SDKModelEvent()
    object ListRequested : SDKModelEvent()
    data class ListCompleted(val models: List<com.runanywhere.sdk.models.ModelInfo>) : SDKModelEvent()
    data class ListFailed(val error: Throwable) : SDKModelEvent()
    data class CatalogLoaded(val models: List<String>) : SDKModelEvent()
    data class DeleteStarted(val modelId: String) : SDKModelEvent()
    data class DeleteCompleted(val modelId: String) : SDKModelEvent()
    data class DeleteFailed(val modelId: String, val error: Throwable) : SDKModelEvent()
    data class CustomModelAdded(val name: String, val url: String) : SDKModelEvent()
    data class CustomModelRegistered(val modelId: String, val url: String) : SDKModelEvent()
    data class CustomModelFailed(val name: String, val url: String, val error: String) : SDKModelEvent()
    data class BuiltInModelRegistered(val modelId: String) : SDKModelEvent()
}

/**
 * Voice Events
 */
sealed class SDKVoiceEvent : BaseSDKEvent(SDKEventType.VOICE) {
    object ListeningStarted : SDKVoiceEvent()
    object ListeningEnded : SDKVoiceEvent()
    object SpeechDetected : SDKVoiceEvent()
    object TranscriptionStarted : SDKVoiceEvent()
    data class TranscriptionPartial(val text: String) : SDKVoiceEvent()
    data class TranscriptionFinal(val text: String) : SDKVoiceEvent()
    data class ResponseGenerated(val text: String) : SDKVoiceEvent()
    object SynthesisStarted : SDKVoiceEvent()
    data class AudioGenerated(val data: ByteArray) : SDKVoiceEvent()
    object SynthesisCompleted : SDKVoiceEvent()
    data class PipelineError(val error: Throwable) : SDKVoiceEvent()
    object PipelineStarted : SDKVoiceEvent()
    object PipelineCompleted : SDKVoiceEvent()
    object VadStarted : SDKVoiceEvent()
    object VadDetected : SDKVoiceEvent()
    object VadEnded : SDKVoiceEvent()
    object SttProcessing : SDKVoiceEvent()
    object LlmProcessing : SDKVoiceEvent()
    object TtsProcessing : SDKVoiceEvent()
}

/**
 * SDK Performance Events for public API
 */
sealed class SDKPerformanceEvent : BaseSDKEvent(SDKEventType.PERFORMANCE) {
    data class MemoryWarning(val usage: Long) : SDKPerformanceEvent()
    data class ThermalStateChanged(val state: String) : SDKPerformanceEvent()
    data class LatencyMeasured(val operation: String, val milliseconds: Double) : SDKPerformanceEvent()
    data class ThroughputMeasured(val tokensPerSecond: Double) : SDKPerformanceEvent()
}

/**
 * SDK Network Events for public API
 */
sealed class SDKNetworkEvent : BaseSDKEvent(SDKEventType.NETWORK) {
    data class RequestStarted(val url: String) : SDKNetworkEvent()
    data class RequestCompleted(val url: String, val statusCode: Int) : SDKNetworkEvent()
    data class RequestFailed(val url: String, val error: Throwable) : SDKNetworkEvent()
    data class ConnectivityChanged(val isOnline: Boolean) : SDKNetworkEvent()
}

/**
 * SDK Storage Events for public API
 */
sealed class SDKStorageEvent : BaseSDKEvent(SDKEventType.STORAGE) {
    object InfoRequested : SDKStorageEvent()
    data class InfoRetrieved(val info: Map<String, Any>) : SDKStorageEvent()
    object ModelsRequested : SDKStorageEvent()
    data class ModelsRetrieved(val models: List<String>) : SDKStorageEvent()
    object ClearCacheStarted : SDKStorageEvent()
    object ClearCacheCompleted : SDKStorageEvent()
    data class ClearCacheFailed(val error: Throwable) : SDKStorageEvent()
    object CleanTempStarted : SDKStorageEvent()
    object CleanTempCompleted : SDKStorageEvent()
    data class CleanTempFailed(val error: Throwable) : SDKStorageEvent()
    data class DeleteModelStarted(val modelId: String) : SDKStorageEvent()
    data class DeleteModelCompleted(val modelId: String) : SDKStorageEvent()
    data class DeleteModelFailed(val modelId: String, val error: Throwable) : SDKStorageEvent()
}

/**
 * SDK Framework Events for public API
 */
sealed class SDKFrameworkEvent : BaseSDKEvent(SDKEventType.FRAMEWORK) {
    data class AdapterRegistered(val framework: String, val name: String) : SDKFrameworkEvent()
    object AdaptersRequested : SDKFrameworkEvent()
    data class AdaptersRetrieved(val count: Int) : SDKFrameworkEvent()
    object FrameworksRequested : SDKFrameworkEvent()
    data class FrameworksRetrieved(val frameworks: List<String>) : SDKFrameworkEvent()
    object AvailabilityRequested : SDKFrameworkEvent()
    data class AvailabilityRetrieved(val availability: List<String>) : SDKFrameworkEvent()
    data class ModelsForFrameworkRequested(val framework: String) : SDKFrameworkEvent()
    data class ModelsForFrameworkRetrieved(val framework: String, val models: List<String>) : SDKFrameworkEvent()
    data class FrameworksForModalityRequested(val modality: String) : SDKFrameworkEvent()
    data class FrameworksForModalityRetrieved(val modality: String, val frameworks: List<String>) : SDKFrameworkEvent()
}

/**
 * SDK Device Events for public API
 */
sealed class SDKDeviceEvent : BaseSDKEvent(SDKEventType.DEVICE) {
    data class DeviceInfoCollected(val deviceInfo: Map<String, Any>) : SDKDeviceEvent()
    data class DeviceInfoCollectionFailed(val error: Throwable) : SDKDeviceEvent()
    data class DeviceInfoRefreshed(val deviceInfo: Map<String, Any>) : SDKDeviceEvent()
    object DeviceInfoSyncStarted : SDKDeviceEvent()
    object DeviceInfoSyncCompleted : SDKDeviceEvent()
    data class DeviceInfoSyncFailed(val error: Throwable) : SDKDeviceEvent()
    data class DeviceStateChanged(val property: String, val newValue: String) : SDKDeviceEvent()
}

/**
 * Events for component initialization lifecycle
 */
sealed class ComponentInitializationEvent : BaseSDKEvent(SDKEventType.INITIALIZATION) {
    // Overall initialization
    data class InitializationStarted(val components: List<String>) : ComponentInitializationEvent()
    data class InitializationCompleted(val result: String) : ComponentInitializationEvent()

    // Component-specific events
    data class ComponentStateChanged(val component: String, val oldState: String, val newState: String) : ComponentInitializationEvent()
    data class ComponentChecking(val component: String, val modelId: String?) : ComponentInitializationEvent()
    data class ComponentDownloadRequired(val component: String, val modelId: String, val sizeBytes: Long) : ComponentInitializationEvent()
    data class ComponentDownloadStarted(val component: String, val modelId: String) : ComponentInitializationEvent()
    data class ComponentDownloadProgress(val component: String, val modelId: String, val progress: Double) : ComponentInitializationEvent()
    data class ComponentDownloadCompleted(val component: String, val modelId: String) : ComponentInitializationEvent()
    data class ComponentDownloadFailed(val component: String, val modelId: String, val error: String) : ComponentInitializationEvent()
    data class ComponentInitializing(val component: String, val modelId: String?) : ComponentInitializationEvent()
    data class ComponentReady(val component: String, val modelId: String?) : ComponentInitializationEvent()
    data class ComponentFailed(val component: String, val error: Throwable) : ComponentInitializationEvent()

    // Batch events
    data class ParallelInitializationStarted(val components: List<String>) : ComponentInitializationEvent()
    data class SequentialInitializationStarted(val components: List<String>) : ComponentInitializationEvent()
    object AllComponentsReady : ComponentInitializationEvent()
    data class SomeComponentsReady(val ready: List<String>, val pending: List<String>) : ComponentInitializationEvent()

    /**
     * Extract component from event if applicable
     */
    val componentName: String?
        get() = when (this) {
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
