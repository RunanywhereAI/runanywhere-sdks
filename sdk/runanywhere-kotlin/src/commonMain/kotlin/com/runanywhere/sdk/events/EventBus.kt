package com.runanywhere.sdk.events

import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow

/**
 * Central event bus for SDK-wide event publishing
 * Mirrors Swift SDK's EventBus
 */
object EventBus {

    // Event flows for different event types
    private val _initializationEvents = MutableSharedFlow<SDKInitializationEvent>()
    val initializationEvents: SharedFlow<SDKInitializationEvent> =
        _initializationEvents.asSharedFlow()

    private val _modelEvents = MutableSharedFlow<SDKModelEvent>()
    val modelEvents: SharedFlow<SDKModelEvent> = _modelEvents.asSharedFlow()

    private val _voiceEvents = MutableSharedFlow<SDKVoiceEvent>()
    val voiceEvents: SharedFlow<SDKVoiceEvent> = _voiceEvents.asSharedFlow()

    private val _configurationEvents = MutableSharedFlow<SDKConfigurationEvent>()
    val configurationEvents: SharedFlow<SDKConfigurationEvent> = _configurationEvents.asSharedFlow()

    private val _generationEvents = MutableSharedFlow<SDKGenerationEvent>()
    val generationEvents: SharedFlow<SDKGenerationEvent> = _generationEvents.asSharedFlow()

    // Component Events - New addition for component lifecycle tracking
    private val _componentEvents = MutableSharedFlow<ComponentEvent>()
    val componentEvents: SharedFlow<ComponentEvent> = _componentEvents.asSharedFlow()

    // Speaker Diarization Events
    private val _speakerDiarizationEvents = MutableSharedFlow<com.runanywhere.sdk.components.speakerdiarization.SpeakerDiarizationEvent>()
    val speakerDiarizationEvents: SharedFlow<com.runanywhere.sdk.components.speakerdiarization.SpeakerDiarizationEvent> = _speakerDiarizationEvents.asSharedFlow()

    // Bootstrap Events - For detailed 8-step initialization tracking
    private val _bootstrapEvents = MutableSharedFlow<SDKBootstrapEvent>()
    val bootstrapEvents: SharedFlow<SDKBootstrapEvent> = _bootstrapEvents.asSharedFlow()

    // Device Events - For device information tracking
    private val _deviceEvents = MutableSharedFlow<SDKDeviceEvent>()
    val deviceEvents: SharedFlow<SDKDeviceEvent> = _deviceEvents.asSharedFlow()

    // Publish methods (non-suspending for easier usage)
    fun publish(event: SDKInitializationEvent) {
        _initializationEvents.tryEmit(event)
    }

    fun publish(event: SDKModelEvent) {
        _modelEvents.tryEmit(event)
    }

    fun publish(event: SDKVoiceEvent) {
        _voiceEvents.tryEmit(event)
    }

    fun publish(event: SDKConfigurationEvent) {
        _configurationEvents.tryEmit(event)
    }

    fun publish(event: SDKGenerationEvent) {
        _generationEvents.tryEmit(event)
    }

    fun publish(event: ComponentEvent) {
        _componentEvents.tryEmit(event)
    }

    fun publish(event: com.runanywhere.sdk.components.speakerdiarization.SpeakerDiarizationEvent) {
        _speakerDiarizationEvents.tryEmit(event)
    }

    fun publish(event: SDKBootstrapEvent) {
        _bootstrapEvents.tryEmit(event)
    }

    fun publish(event: SDKDeviceEvent) {
        _deviceEvents.tryEmit(event)
    }

    val shared = EventBus
}

// Event definitions
sealed class SDKInitializationEvent {
    object Started : SDKInitializationEvent()
    object Completed : SDKInitializationEvent()
    data class Failed(val error: Throwable) : SDKInitializationEvent()

    // Step-by-step initialization events matching iOS 8-step process
    data class StepStarted(val step: Int, val stepName: String) : SDKInitializationEvent()
    data class StepCompleted(val step: Int, val stepName: String, val durationMs: Long) : SDKInitializationEvent()
    data class StepFailed(val step: Int, val stepName: String, val error: Throwable) : SDKInitializationEvent()
}

sealed class SDKModelEvent {
    data class LoadStarted(val modelId: String) : SDKModelEvent()
    data class LoadCompleted(val modelId: String) : SDKModelEvent()
    data class LoadFailed(val modelId: String, val error: Throwable) : SDKModelEvent()
    data class DownloadStarted(val modelId: String) : SDKModelEvent()
    data class DownloadProgress(val modelId: String, val progress: Float) : SDKModelEvent()
    data class DownloadCompleted(val modelId: String) : SDKModelEvent()
    data class DownloadFailed(val modelId: String, val error: Throwable) : SDKModelEvent()
}

sealed class SDKVoiceEvent {
    object TranscriptionStarted : SDKVoiceEvent()
    data class TranscriptionPartial(val text: String) : SDKVoiceEvent()
    data class TranscriptionFinal(val text: String) : SDKVoiceEvent()
    data class PipelineError(val error: Throwable) : SDKVoiceEvent()
}

sealed class SDKConfigurationEvent {
    data class Loaded(val config: ConfigurationData) : SDKConfigurationEvent()
    data class Updated(val key: String, val value: Any) : SDKConfigurationEvent()
}

sealed class SDKGenerationEvent {
    data class Started(val sessionId: String, val prompt: String) : SDKGenerationEvent()
    data class Completed(val sessionId: String, val result: GenerationResult) : SDKGenerationEvent()
    data class Failed(val sessionId: String, val error: Exception) : SDKGenerationEvent()
    data class Cancelled(val sessionId: String) : SDKGenerationEvent()
    data class PartialResult(val sessionId: String, val text: String) : SDKGenerationEvent()
}

// Import types for event usage
typealias ConfigurationData = com.runanywhere.sdk.data.models.ConfigurationData
typealias GenerationResult = com.runanywhere.sdk.generation.GenerationResult

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

/**
 * Device Events - For device information tracking
 * Matches iOS device-related events
 */
sealed class SDKDeviceEvent {
    data class DeviceInfoCollected(val deviceInfo: com.runanywhere.sdk.data.models.DeviceInfoData) : SDKDeviceEvent()
    data class DeviceInfoSynced(val deviceInfo: com.runanywhere.sdk.data.models.DeviceInfoData) : SDKDeviceEvent()
    data class DeviceInfoSyncFailed(val error: String) : SDKDeviceEvent()
    data class DeviceCapabilitiesAssessed(val assessment: com.runanywhere.sdk.data.models.DeviceCapabilityAssessment) : SDKDeviceEvent()
    data class DevicePerformanceUpdated(val metrics: com.runanywhere.sdk.data.models.DevicePerformanceMetrics) : SDKDeviceEvent()
}

// Import ComponentEvent from STTEvents for use in EventBus
// Note: ComponentEvent and related classes are defined in STTEvents.kt
