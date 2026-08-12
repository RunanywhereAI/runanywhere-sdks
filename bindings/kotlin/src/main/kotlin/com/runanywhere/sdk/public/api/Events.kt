/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public v4 surface: one event grammar throughout — `started`, then deltas,
 * then a terminal `completed`/`failed`/`cancelled`. Streams never fabricate a
 * successful `completed`: an in-flight failure is a `failed` event, and a
 * stream that ends without a terminal signal is a `failed`/`cancelled` event
 * too, never a silently synthesized success. Long-lived sessions
 * (`VoiceSession`, `RunAnywhere.events`) additionally emit a recoverable
 * `error` breadcrumb for per-component trouble.
 */

package com.runanywhere.sdk.public.api

import com.runanywhere.sdk.foundation.errors.SDKException

/** Whether a streamed delta is answer text or a thought. */
public enum class TokenKind {
    TEXT,
    THOUGHT,
}

/** One alternative transcript for a still-revising partial segment. */
public data class TranscriptAlternative(
    val text: String,
    val confidence: Float? = null,
)

/** Progress of one text generation (`llm`/`vlm` `generateStream`). */
public sealed class GenerationEvent {
    public abstract val requestId: String

    /** The request was admitted and generation began. */
    public data class Started(
        override val requestId: String,
    ) : GenerationEvent()

    /** A new output item (text run, reasoning run, or tool call) began. */
    public data class OutputItemAdded(
        override val requestId: String,
        val sequence: Long,
        val itemId: String,
        val index: Int,
        val item: Any?,
    ) : GenerationEvent()

    /** One answer-text delta. */
    public data class TextDelta(
        override val requestId: String,
        val sequence: Long,
        val itemId: String,
        val index: Int,
        val text: String,
    ) : GenerationEvent()

    /** One reasoning/thinking delta. */
    public data class ReasoningDelta(
        override val requestId: String,
        val sequence: Long,
        val itemId: String,
        val index: Int,
        val text: String,
    ) : GenerationEvent()

    /** The model asked to call a tool. */
    public data class ToolCallAdded(
        override val requestId: String,
        val sequence: Long,
        val itemId: String,
        val index: Int,
        val call: ToolCall,
    ) : GenerationEvent()

    /** One delta of a tool call's streamed argument JSON. */
    public data class ToolArgumentsDelta(
        override val requestId: String,
        val sequence: Long,
        val itemId: String,
        val delta: String,
    ) : GenerationEvent()

    /** A tool call's argument JSON is complete. */
    public data class ToolArgumentsDone(
        override val requestId: String,
        val sequence: Long,
        val itemId: String,
        val arguments: String,
    ) : GenerationEvent()

    /** Token accounting for the request so far. */
    public data class Usage(
        override val requestId: String,
        val sequence: Long,
        val inputTokens: Int,
        val outputTokens: Int,
    ) : GenerationEvent()

    /** Generation finished; carries the aggregate result. */
    public data class Completed(
        override val requestId: String,
        val result: GenerationResult,
    ) : GenerationEvent()

    /** Generation failed in flight. */
    public data class Failed(
        override val requestId: String,
        val partial: String? = null,
        val error: SDKException,
    ) : GenerationEvent()

    /** Generation was cancelled by the caller. */
    public data class Cancelled(
        override val requestId: String,
        val partial: String? = null,
    ) : GenerationEvent()
}

/** Progress of one streamed transcription (`stt.openStream`). */
public sealed class TranscriptionEvent {
    public abstract val requestId: String

    /** The recognizer opened and is accepting audio. */
    public data class Started(
        override val requestId: String,
    ) : TranscriptionEvent()

    /** Speech began. */
    public data class SpeechStarted(
        override val requestId: String,
        val sequence: Long,
        val timestampMs: Long? = null,
    ) : TranscriptionEvent()

    /** An unstable hypothesis that may still change. */
    public data class Partial(
        override val requestId: String,
        val sequence: Long,
        val segmentId: String,
        val revision: Int,
        val alternatives: List<TranscriptAlternative>,
    ) : TranscriptionEvent()

    /** The stable transcription for the closed utterance. */
    public data class TranscriptFinal(
        override val requestId: String,
        val sequence: Long,
        val segment: Transcription,
    ) : TranscriptionEvent()

    /** Speech ended. */
    public data class SpeechEnded(
        override val requestId: String,
        val sequence: Long,
        val timestampMs: Long? = null,
    ) : TranscriptionEvent()

    /** Token/duration accounting for the request so far. */
    public data class Usage(
        override val requestId: String,
        val sequence: Long,
    ) : TranscriptionEvent()

    /** The stream finished normally. */
    public data class Completed(
        override val requestId: String,
    ) : TranscriptionEvent()

    /** The stream failed in flight. */
    public data class Failed(
        override val requestId: String,
        val error: SDKException,
    ) : TranscriptionEvent()

    /** The stream was cancelled by the caller. */
    public data class Cancelled(
        override val requestId: String,
    ) : TranscriptionEvent()
}

/** Progress of a streaming voice-activity session (`vad.openStream`). */
public sealed class VadEvent {
    /** Speech began. */
    public data class SpeechStarted(
        val timestampMs: Long? = null,
    ) : VadEvent()

    /** Speech ended. */
    public data class SpeechEnded(
        val timestampMs: Long? = null,
    ) : VadEvent()

    /** A frame verdict with no state transition. */
    public data class Activity(
        val isSpeech: Boolean,
        val probability: Float,
        val timestampMs: Long? = null,
    ) : VadEvent()

    /** The stream failed in flight. */
    public data class Failed(
        val error: SDKException,
    ) : VadEvent()

    /** The stream finished normally. */
    public data object Completed : VadEvent()
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
        val requestId: String? = null,
    ) : VoiceEvent()

    /** The agent moved to a new phase of the turn. */
    public data class AgentStateChanged(
        val state: AgentState,
    ) : VoiceEvent()

    /** The agent's reply text for this turn. */
    public data class AgentResponse(
        val text: String,
        val speechId: String? = null,
    ) : VoiceEvent()

    /** The user started talking. */
    public data class SpeechStarted(
        val speechId: String? = null,
    ) : VoiceEvent()

    /** The user stopped talking. */
    public data class SpeechEnded(
        val speechId: String? = null,
    ) : VoiceEvent()

    /** A component failed; the session keeps running when [recoverable]. */
    public data class Error(
        val message: String,
        val recoverable: Boolean,
        val source: String? = null,
        val code: String? = null,
    ) : VoiceEvent()
}

/** Progress of a streaming RAG answer. */
public sealed class RagEvent {
    /** The chunks that will ground the answer. */
    public data class Retrieved(
        val matches: List<Match>,
    ) : RagEvent()

    /** One decoded token of the answer. */
    public data class TextDelta(
        val text: String,
        val kind: TokenKind,
    ) : RagEvent()

    /** The answer finished; carries the aggregate result. */
    public data class Completed(
        val result: RagResult,
    ) : RagEvent()

    /** The query failed in flight. */
    public data class Failed(
        val error: SDKException,
    ) : RagEvent()
}

/** Progress of a streaming image generation. */
public sealed class ImageEvent {
    /** The request was admitted and denoising began. */
    public data object Started : ImageEvent()

    /** One denoising step, optionally carrying a preview. Only ever real progress. */
    public data class Progress(
        val step: Int,
        val totalSteps: Int,
        val partialImage: ImageData? = null,
    ) : ImageEvent()

    /** Generation finished; carries the images. */
    public data class Completed(
        val result: ImageResult,
    ) : ImageEvent()

    /** Generation failed in flight. */
    public data class Failed(
        val error: SDKException,
    ) : ImageEvent()
}

/** Progress of a model download, correlated by `operationId`/`sequence`. */
public sealed class DownloadEvent {
    public abstract val operationId: String
    public abstract val sequence: Long

    /** The transfer was admitted and began. */
    public data class Started(
        override val operationId: String,
        override val sequence: Long,
    ) : DownloadEvent()

    /**
     * Bytes transferred so far, plus what a UI needs to say how the transfer is going.
     *
     * C++ already measures throughput and projects a finish time
     * (`download_orchestrator.cpp`), and the `DownloadProgress` proto carries both along with the
     * retry count and the position in a multi-file plan. Those fields used to be dropped at this
     * boundary, so no consumer could show a rate or a remaining time no matter what it did. They are
     * surfaced here rather than recomputed per platform: five SDKs deriving their own rate from
     * successive byte counts would disagree with each other and with the transfer that actually
     * knows its own history.
     *
     * Every added field is optional and defaulted, so a caller that only wants bytes is unaffected.
     */
    public data class Progress(
        override val operationId: String,
        override val sequence: Long,
        val bytesDone: Long,
        val bytesTotal: Long,
        val file: String? = null,
        /** Measured throughput. Null when not yet known — never a zero standing in for unknown. */
        val bytesPerSecond: Float? = null,
        /** Projected seconds remaining. Null when the total size or the rate is unknown. */
        val etaSeconds: Long? = null,
        /** 0 on the first attempt. Above 0 means the transfer recovered from a failure. */
        val retryAttempt: Int = 0,
        /** 0.0..1.0 across every file in the plan, not just the current one. */
        val overallProgress: Float? = null,
        /** 0-based position in the planned file list. */
        val currentFileIndex: Int = 0,
        /** Files in the plan. 1 for a single-file model. */
        val totalFiles: Int = 1,
    ) : DownloadEvent() {
        /**
         * Fraction of the whole download that is done, 0.0..1.0, or null when
         * commons has not yet reported a positive [overallProgress].
         *
         * Never re-derives a byte ratio locally — multi-file plans make
         * bytesDone/bytesTotal a per-file figure that is not overall progress.
         */
        public val fraction: Float?
            get() = overallProgress
    }

    /** Downloaded bytes are being checksummed/validated. */
    public data class Verifying(
        override val operationId: String,
        override val sequence: Long,
    ) : DownloadEvent()

    /** The archive is being unpacked. */
    public data class Extracting(
        override val operationId: String,
        override val sequence: Long,
        val percent: Float? = null,
    ) : DownloadEvent()

    /** The model is on disk and registered. */
    public data class Completed(
        override val operationId: String,
        override val sequence: Long,
        val model: ModelInfo,
    ) : DownloadEvent()

    /** The transfer failed in flight. */
    public data class Failed(
        override val operationId: String,
        override val sequence: Long,
        val error: SDKException,
    ) : DownloadEvent()

    /** The transfer was cancelled by the caller. */
    public data class Cancelled(
        override val operationId: String,
        override val sequence: Long,
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
        val actualBackend: Backend? = null,
    ) : SdkEvent()

    /** A model was released. */
    public data class ModelUnloaded(
        val id: String,
    ) : SdkEvent()

    /** Something failed; the SDK keeps running when [recoverable]. */
    public data class Error(
        val message: String,
        val recoverable: Boolean,
        val source: String? = null,
        val code: String? = null,
    ) : SdkEvent()
}
