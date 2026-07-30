/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public v3 surface: one event grammar — `started`, then deltas, then
 * `completed`, with in-flight failures thrown into the collector.
 */

package com.runanywhere.sdk.public.api

/** Whether a streamed token is answer text or model reasoning. */
public enum class TokenKind {
    TEXT,
    THOUGHT,
}

/** Progress of a streaming text or vision generation. */
public sealed class GenerationEvent {
    /** The request was admitted and generation began. */
    public data class Started(
        val requestId: String,
    ) : GenerationEvent()

    /** One decoded token. */
    public data class Token(
        val text: String,
        val kind: TokenKind,
    ) : GenerationEvent()

    /** The model asked to call a tool. */
    public data class ToolCallRequested(
        val call: ToolCall,
    ) : GenerationEvent()

    /** Generation finished; carries the aggregate result. */
    public data class Completed(
        val result: GenerationResult,
    ) : GenerationEvent()
}

/** Progress of a streaming transcription. */
public sealed class TranscriptionEvent {
    /** The recognizer opened and is accepting audio. */
    public data object Started : TranscriptionEvent()

    /** An unstable hypothesis that may still change. */
    public data class Partial(
        val text: String,
    ) : TranscriptionEvent()

    /** The stable transcription for the closed utterance. */
    public data class Final(
        val transcription: Transcription,
    ) : TranscriptionEvent()
}

/** Progress of a streaming voice-activity check. */
public sealed class VadEvent {
    /** Speech began. */
    public data class SpeechStarted(
        val result: VadResult,
    ) : VadEvent()

    /** Speech ended. */
    public data class SpeechEnded(
        val result: VadResult,
    ) : VadEvent()

    /** A frame verdict with no state transition. */
    public data class Frame(
        val result: VadResult,
    ) : VadEvent()
}

/** What the agent is doing right now. */
public enum class AgentState {
    LISTENING,
    THINKING,
    SPEAKING,
}

/** Progress of a live voice session. */
public sealed class VoiceEvent {
    /** The user's speech was recognised. */
    public data class UserTranscribed(
        val text: String,
        val isFinal: Boolean,
    ) : VoiceEvent()

    /** The agent moved to a new phase of the turn. */
    public data class AgentStateChanged(
        val state: AgentState,
    ) : VoiceEvent()

    /** The agent's reply text for this turn. */
    public data class AgentResponse(
        val text: String,
    ) : VoiceEvent()

    /** The user started talking. */
    public data object SpeechStarted : VoiceEvent()

    /** The user stopped talking. */
    public data object SpeechEnded : VoiceEvent()

    /** A component failed; the session keeps running when [recoverable]. */
    public data class Error(
        val message: String,
        val recoverable: Boolean,
    ) : VoiceEvent()
}

/** Progress of a streaming RAG answer. */
public sealed class RagEvent {
    /** The chunks that will ground the answer. */
    public data class Retrieved(
        val matches: List<Match>,
    ) : RagEvent()

    /** One decoded token of the answer. */
    public data class Token(
        val text: String,
        val kind: TokenKind,
    ) : RagEvent()

    /** The answer finished; carries the aggregate result. */
    public data class Completed(
        val result: RagResult,
    ) : RagEvent()
}

/** Progress of a streaming image generation. */
public sealed class ImageEvent {
    /** The request was admitted and denoising began. */
    public data object Started : ImageEvent()

    /** One denoising step, optionally carrying a preview. */
    public data class Progress(
        val step: Int,
        val totalSteps: Int,
        val partialImage: ImageData? = null,
    ) : ImageEvent()

    /** Generation finished; carries the images. */
    public data class Completed(
        val result: ImageResult,
    ) : ImageEvent()
}

/** Progress of a model download. */
public sealed class DownloadEvent {
    /** Bytes transferred so far. */
    public data class Progress(
        val bytesDone: Long,
        val bytesTotal: Long,
        val percent: Float,
    ) : DownloadEvent()

    /** The archive is being unpacked. */
    public data object Extracting : DownloadEvent()

    /** The model is on disk and registered. */
    public data class Completed(
        val model: ModelInfo,
    ) : DownloadEvent()
}

/** SDK-wide lifecycle breadcrumbs. */
public sealed class SdkEvent {
    /** Local inference is usable. */
    public data object Ready : SdkEvent()

    /** A model became resident. */
    public data class ModelLoaded(
        val id: String,
        val category: ModelCategory,
    ) : SdkEvent()

    /** A model was released. */
    public data class ModelUnloaded(
        val id: String,
    ) : SdkEvent()

    /** Something failed; the SDK keeps running when [recoverable]. */
    public data class Error(
        val message: String,
        val recoverable: Boolean,
    ) : SdkEvent()
}
