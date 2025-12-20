package com.runanywhere.sdk.events

import com.runanywhere.sdk.core.capabilities.ComponentState
import com.runanywhere.sdk.core.capabilities.SDKComponent

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
 * Stages in the voice pipeline
 * Matches iOS PipelineStage enum
 */
enum class PipelineStage(val displayName: String) {
    VAD("VAD"),
    TRANSCRIPTION("Speech-to-Text"),
    LLM_GENERATION("LLM Generation"),
    TEXT_TO_SPEECH("Text-to-Speech");

    companion object {
        val allCases: List<PipelineStage> = values().toList()
    }
}

/**
 * Pipeline events that exactly match iOS ModularPipelineEvent patterns
 * These are used by voice pipeline components
 */
sealed class ModularPipelineEvent {
    // VAD events
    object vadSpeechStart : ModularPipelineEvent()
    object vadSpeechEnd : ModularPipelineEvent()
    data class vadAudioLevel(val level: Float) : ModularPipelineEvent()

    // STT specific events matching iOS patterns
    data class sttPartialTranscript(val partial: String) : ModularPipelineEvent()
    data class sttFinalTranscript(val transcript: String) : ModularPipelineEvent()
    data class sttLanguageDetected(val language: String) : ModularPipelineEvent()

    data class sttFinalTranscriptWithSpeaker(
        val transcript: String,
        val speaker: SpeakerInfo
    ) : ModularPipelineEvent()

    data class sttPartialTranscriptWithSpeaker(
        val text: String,
        val speaker: SpeakerInfo
    ) : ModularPipelineEvent()

    data class sttNewSpeakerDetected(val speaker: SpeakerInfo) : ModularPipelineEvent()

    data class sttSpeakerChanged(
        val from: SpeakerInfo?,
        val to: SpeakerInfo
    ) : ModularPipelineEvent()

    // LLM events
    object llmThinking : ModularPipelineEvent()
    data class llmPartialResponse(val text: String) : ModularPipelineEvent()
    data class llmFinalResponse(val text: String) : ModularPipelineEvent()
    object llmStreamStarted : ModularPipelineEvent()
    data class llmStreamToken(val token: String) : ModularPipelineEvent()

    // TTS events
    object ttsStarted : ModularPipelineEvent()
    data class ttsAudioChunk(val data: ByteArray) : ModularPipelineEvent() {
        override fun equals(other: Any?): Boolean {
            if (this === other) return true
            if (other !is ttsAudioChunk) return false
            return data.contentEquals(other.data)
        }

        override fun hashCode(): Int = data.contentHashCode()
    }

    object ttsCompleted : ModularPipelineEvent()

    // Initialization events
    data class componentInitializing(val componentName: String) : ModularPipelineEvent()
    data class componentInitialized(val componentName: String) : ModularPipelineEvent()
    data class componentInitializationFailed(val componentName: String, val error: Throwable) :
        ModularPipelineEvent()

    object allComponentsInitialized : ModularPipelineEvent()

    // Pipeline events
    object pipelineStarted : ModularPipelineEvent()
    data class pipelineError(val error: Throwable) : ModularPipelineEvent()
    object pipelineCompleted : ModularPipelineEvent()
}

/**
 * Speaker information for diarization (matches iOS SpeakerInfo)
 */
data class SpeakerInfo(
    val id: String,
    val name: String? = null,
    val confidence: Float? = null
)

/**
 * Complete result from voice pipeline
 * Matches iOS VoicePipelineResult struct
 */
data class VoicePipelineResult(
    val transcription: com.runanywhere.sdk.features.stt.STTOutput,
    val llmResponse: String,
    val audioOutput: ByteArray? = null,
    val processingTime: Double = 0.0,
    val stageTiming: Map<PipelineStage, Double> = emptyMap()
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is VoicePipelineResult) return false

        return transcription == other.transcription &&
                llmResponse == other.llmResponse &&
                audioOutput?.contentEquals(
                    other.audioOutput ?: ByteArray(0)
                ) ?: (other.audioOutput == null) &&
                processingTime == other.processingTime &&
                stageTiming == other.stageTiming
    }

    override fun hashCode(): Int {
        var result = transcription.hashCode()
        result = 31 * result + llmResponse.hashCode()
        result = 31 * result + (audioOutput?.contentHashCode() ?: 0)
        result = 31 * result + processingTime.hashCode()
        result = 31 * result + stageTiming.hashCode()
        return result
    }
}
