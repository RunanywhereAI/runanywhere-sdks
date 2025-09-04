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

    val shared = EventBus
}

// Event definitions
sealed class SDKInitializationEvent {
    object Started : SDKInitializationEvent()
    object Completed : SDKInitializationEvent()
    data class Failed(val error: Throwable) : SDKInitializationEvent()
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

// Import configuration data for event usage
typealias ConfigurationData = com.runanywhere.sdk.data.models.ConfigurationData
