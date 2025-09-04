package com.runanywhere.sdk.events

import com.runanywhere.sdk.components.base.ComponentState
import com.runanywhere.sdk.components.base.SDKComponent

// MARK: - Component Events

/**
 * Base class for all component events
 */
sealed class ComponentEvent

sealed class ComponentInitializationEvent : ComponentEvent() {
    data class ComponentChecking(
        val component: SDKComponent,
        val modelId: String?
    ) : ComponentInitializationEvent()

    data class ComponentInitializing(
        val component: SDKComponent,
        val modelId: String?
    ) : ComponentInitializationEvent()

    data class ComponentDownloadStarted(
        val component: SDKComponent,
        val modelId: String
    ) : ComponentInitializationEvent()

    data class ComponentDownloadProgress(
        val component: SDKComponent,
        val modelId: String,
        val progress: Float
    ) : ComponentInitializationEvent()

    data class ComponentDownloadCompleted(
        val component: SDKComponent,
        val modelId: String
    ) : ComponentInitializationEvent()

    data class ComponentReady(
        val component: SDKComponent,
        val modelId: String?
    ) : ComponentInitializationEvent()

    data class ComponentFailed(
        val component: SDKComponent,
        val error: Throwable
    ) : ComponentInitializationEvent()

    data class ComponentStateChanged(
        val component: SDKComponent,
        val oldState: ComponentState,
        val newState: ComponentState
    ) : ComponentInitializationEvent()
}

// MARK: - STT Events

sealed class STTEvent : ComponentEvent() {
    object Initialized : STTEvent()

    data class TranscriptionStarted(
        val sessionId: String
    ) : STTEvent()

    data class TranscriptionCompleted(
        val text: String,
        val duration: Long,
        val sessionId: String? = null
    ) : STTEvent()

    data class PartialTranscription(
        val text: String,
        val sessionId: String
    ) : STTEvent()

    data class Error(
        val error: Throwable,
        val sessionId: String? = null
    ) : STTEvent()
}

// MARK: - Transcription Events

sealed class TranscriptionEvent : ComponentEvent() {
    object SpeechStart : TranscriptionEvent()
    object SpeechEnd : TranscriptionEvent()

    data class PartialTranscription(
        val text: String,
        val confidence: Float? = null
    ) : TranscriptionEvent()

    data class FinalTranscription(
        val text: String,
        val confidence: Float? = null
    ) : TranscriptionEvent()

    data class Error(
        val error: Throwable
    ) : TranscriptionEvent()
}

// MARK: - VAD Events

sealed class VADEvent : ComponentEvent() {
    object Initialized : VADEvent()

    data class SpeechDetected(
        val timestamp: Long,
        val confidence: Float
    ) : VADEvent()

    data class SilenceDetected(
        val timestamp: Long,
        val duration: Long
    ) : VADEvent()

    data class Error(
        val error: Throwable
    ) : VADEvent()
}

// MARK: - Model Events

sealed class ModelEvent : ComponentEvent() {
    data class DownloadStarted(
        val modelId: String,
        val modelSize: Long? = null
    ) : ModelEvent()

    data class DownloadProgress(
        val modelId: String,
        val progress: Float,
        val downloadedBytes: Long? = null,
        val totalBytes: Long? = null
    ) : ModelEvent()

    data class DownloadCompleted(
        val modelId: String,
        val modelPath: String
    ) : ModelEvent()

    data class DownloadFailed(
        val modelId: String,
        val error: Throwable
    ) : ModelEvent()

    data class ModelLoaded(
        val modelId: String
    ) : ModelEvent()

    data class ModelUnloaded(
        val modelId: String
    ) : ModelEvent()
}
