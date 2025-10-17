package com.runanywhere.sdk.events

import com.runanywhere.sdk.components.base.ComponentState
import com.runanywhere.sdk.components.base.SDKComponent

// MARK: - Component Events

/**
 * Base class for all component events
 */
sealed class ComponentEvent

// Legacy ComponentInitializationEvent - now replaced by the one in SDKEvent.kt
// Keeping this as LegacyComponentInitializationEvent for backwards compatibility
sealed class LegacyComponentInitializationEvent : ComponentEvent() {
    data class ComponentChecking(
        val component: String, // Changed to String to avoid dependency issues
        val modelId: String?
    ) : LegacyComponentInitializationEvent()

    data class ComponentInitializing(
        val component: String,
        val modelId: String?
    ) : LegacyComponentInitializationEvent()

    data class ComponentDownloadStarted(
        val component: String,
        val modelId: String
    ) : LegacyComponentInitializationEvent()

    data class ComponentDownloadProgress(
        val component: String,
        val modelId: String,
        val progress: Float
    ) : LegacyComponentInitializationEvent()

    data class ComponentDownloadCompleted(
        val component: String,
        val modelId: String
    ) : LegacyComponentInitializationEvent()

    data class ComponentReady(
        val component: String,
        val modelId: String?
    ) : LegacyComponentInitializationEvent()

    data class ComponentFailed(
        val component: String,
        val error: Throwable
    ) : LegacyComponentInitializationEvent()

    data class ComponentStateChanged(
        val component: String,
        val oldState: String,
        val newState: String
    ) : LegacyComponentInitializationEvent()
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

// MARK: - Pipeline Events (iOS Parity)

/**
 * Pipeline events that exactly match iOS ModularPipelineEvent patterns
 * These are used by STTHandler and voice pipeline components
 */
sealed class ModularPipelineEvent {
    // STT specific events matching iOS patterns
    data class sttFinalTranscript(val transcript: String) : ModularPipelineEvent()

    data class sttFinalTranscriptWithSpeaker(
        val transcript: String,
        val speaker: SpeakerInfo
    ) : ModularPipelineEvent()

    data class sttSpeakerChanged(
        val from: SpeakerInfo?,
        val to: SpeakerInfo
    ) : ModularPipelineEvent()

    data class sttPartialTranscript(val partial: String) : ModularPipelineEvent()

    data class sttLanguageDetected(
        val language: String,
        val confidence: Float
    ) : ModularPipelineEvent()

    data class sttAudioLevelChanged(
        val level: Float,
        val timestamp: Double
    ) : ModularPipelineEvent()

    data class sttError(val error: com.runanywhere.sdk.components.stt.STTError) : ModularPipelineEvent()
}

/**
 * Speaker information for diarization (matches iOS SpeakerInfo)
 */
data class SpeakerInfo(
    val id: String,
    val name: String? = null,
    val confidence: Float? = null
)
