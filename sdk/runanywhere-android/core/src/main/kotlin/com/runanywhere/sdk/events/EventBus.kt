package com.runanywhere.sdk.events

import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow

/**
 * Central event bus for SDK events
 */
object EventBus {
    private val _events = MutableSharedFlow<SDKEvent>(replay = 0)
    val events: SharedFlow<SDKEvent> = _events.asSharedFlow()

    suspend fun emit(event: SDKEvent) {
        _events.emit(event)
    }
}

/**
 * Base SDK event interface
 */
sealed interface SDKEvent

/**
 * STT related events
 */
sealed class STTEvent : SDKEvent {
    object Initialized : STTEvent()
    data class TranscriptionStarted(val timestamp: Long = System.currentTimeMillis()) : STTEvent()
    data class TranscriptionCompleted(val text: String, val duration: Long) : STTEvent()
    data class TranscriptionError(val error: Throwable) : STTEvent()
}

/**
 * Model related events
 */
sealed class ModelEvent : SDKEvent {
    data class DownloadStarted(val modelId: String) : ModelEvent()
    data class DownloadProgress(val modelId: String, val progress: Float) : ModelEvent()
    data class DownloadCompleted(val modelId: String) : ModelEvent()
    data class DownloadError(val modelId: String, val error: Throwable) : ModelEvent()
    data class ModelLoaded(val modelId: String) : ModelEvent()
    data class ModelUnloaded(val modelId: String) : ModelEvent()
}

/**
 * Transcription events for streaming
 */
sealed class TranscriptionEvent : SDKEvent {
    object SpeechStart : TranscriptionEvent()
    object SpeechEnd : TranscriptionEvent()
    data class PartialTranscription(val text: String) : TranscriptionEvent()
    data class FinalTranscription(val text: String) : TranscriptionEvent()
    data class Error(val error: Throwable) : TranscriptionEvent()
}
