/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public v3 surface: every result shape, with one shared metrics block on the
 * generation results so no caller computes throughput itself.
 */

package com.runanywhere.sdk.public.api

import com.runanywhere.sdk.foundation.errors.SDKException
import kotlinx.coroutines.CompletableDeferred
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean

/** Why a generation stopped. */
public enum class FinishReason {
    STOP,
    LENGTH,
    TOOL_CALLS,
    CANCELLED,
    CONTENT_FILTER,
    ERROR,
    UNKNOWN,
}

/** A completed text or vision generation, with its metrics. */
public data class GenerationResult(
    val text: String,
    val thinkingText: String? = null,
    val toolCalls: List<ToolCall> = emptyList(),
    /** Outcomes of the tool calls the SDK executed during the loop. */
    val toolResults: List<ToolResult> = emptyList(),
    val finishReason: FinishReason = FinishReason.STOP,
    /** Backend-native finish-reason string, before normalization into [finishReason]. */
    val rawFinishReason: String? = null,
    val inputTokens: Int = 0,
    val outputTokens: Int = 0,
    val timeToFirstTokenMs: Long = 0L,
    val tokensPerSecond: Float = 0f,
    val requestId: String = "",
    val model: String = "",
    val actualBackend: Backend? = null,
    val actualDevice: String? = null,
)

/** A generation parsed against a JSON schema, with the same metrics as [GenerationResult]. */
public data class StructuredResult(
    /** Parsed JSON, as the canonical text commons produced. */
    val value: String,
    val raw: String,
    val valid: Boolean,
    val mode: StructuredOutputMode = StructuredOutputMode.VALIDATION_ONLY,
    val inputTokens: Int = 0,
    val outputTokens: Int = 0,
    val timeToFirstTokenMs: Long = 0L,
    val tokensPerSecond: Float = 0f,
    val requestId: String = "",
    val model: String = "",
)

/** One recognised word with its timing. */
public data class Word(
    val text: String,
    val startMs: Long,
    val endMs: Long,
    val confidence: Float,
    val speakerId: String? = null,
)

/** A completed transcription. */
public data class Transcription(
    val text: String,
    val language: String? = null,
    val confidence: Float = 0f,
    val words: List<Word> = emptyList(),
    val durationMs: Long = 0L,
)

/** Synthesized audio. */
public class Audio internal constructor(
    public val data: ByteArray,
    public val sampleRate: Int,
    public val format: AudioFormat,
    public val durationMs: Long,
)

/** One chunk of a streaming synthesis. */
public class AudioChunk internal constructor(
    public val data: ByteArray,
    public val index: Int,
    public val isFinal: Boolean,
)

/** A span of speech inside an analysed buffer. */
public data class Segment(
    val startMs: Long,
    val endMs: Long,
)

/** The verdict of a voice-activity check. */
public data class VadResult(
    val isSpeech: Boolean,
    val probability: Float,
    val segments: List<Segment> = emptyList(),
)

/** One embedding vector, tagged with its position in the input list. */
public class Embedding internal constructor(
    public val index: Int,
    public val vector: FloatArray,
)

/** One reranked document, pointing back at its input position. */
public data class RankedResult(
    val index: Int,
    val relevanceScore: Float,
)

/** One generated image. */
public class ImageData internal constructor(
    public val bytes: ByteArray,
    public val width: Int,
    public val height: Int,
    public val mediaType: String,
)

/** A completed image generation. */
public data class ImageResult(
    val images: List<ImageData>,
    val seed: Long,
    val steps: Int,
)

/** One speaker's turn inside an analysed buffer. */
public data class SpeakerSegment(
    val speakerId: String,
    val startMs: Long,
    val endMs: Long,
)

/** A completed speaker diarization. */
public data class DiarizationResult(
    val segments: List<SpeakerSegment>,
    val speakerCount: Int,
)

/** One class present in a segmentation mask. */
public data class ClassInfo(
    val classId: Int,
    val label: String,
    val pixelCount: Long,
    val fraction: Float,
)

/** A completed semantic segmentation. */
public class SegmentationResult internal constructor(
    /** Per-pixel class ids, little-endian `uint16`, row-major. */
    public val classMask: ByteArray,
    public val width: Int,
    public val height: Int,
    public val classes: List<ClassInfo>,
    /** RGBA overlay, present only when `includeDiagnosticImage` was requested. */
    public val diagnosticImage: ByteArray?,
)

/** One retrieved chunk with its similarity score. */
public data class Match(
    val text: String,
    val score: Float,
    val metadata: Map<String, String> = emptyMap(),
)

/** A completed RAG answer, with the same metrics as [GenerationResult]. */
public data class RagResult(
    val answer: String,
    val sources: List<Match>,
    /** Commons-split reasoning channel (`RAGResult.thinking_content`); null when absent. */
    val thinkingText: String? = null,
    val inputTokens: Int = 0,
    val outputTokens: Int = 0,
    val timeToFirstTokenMs: Long = 0L,
    val tokensPerSecond: Float = 0f,
    val requestId: String = "",
    val model: String = "",
)

/** Readiness of the speech-to-text component. */
public data class SttState(
    val isReady: Boolean,
    val modelId: String? = null,
    val supportsStreaming: Boolean = false,
    val languages: List<String> = emptyList(),
)

/** What is loaded and how much room is left. */
public data class ModelsState(
    val loaded: Map<ModelCategory, ModelInfo>,
    val storageUsedBytes: Long,
    val storageFreeBytes: Long,
)

/** One LoRA adapter currently applied to the loaded base model. */
public data class AppliedAdapter(
    val id: String,
    val scale: Float,
)

/** Which LoRA adapters are applied. */
public data class LoraState(
    val applied: List<AppliedAdapter>,
)

/** Size of a RAG session's index. */
public data class RagStats(
    val documentCount: Long,
    val chunkCount: Long,
    val indexSizeBytes: Long,
)

/**
 * Resident-model ownership handle returned by `models.load`.
 *
 * [close] and `models.unload(id)` release the same residency; calling
 * either after the other is a no-op.
 */
public class LoadedModel internal constructor(
    public val id: String,
    public val category: ModelCategory,
    /** The backend preference that was requested, when one was given. */
    public val requestedBackend: BackendPreference? = null,
    public val actualBackend: Backend,
    public val actualDevice: String = "unknown",
    public val runtimeVersion: String? = null,
    public val abiVersion: String? = null,
    /** Set when the requested backend/accelerator could not be honored. */
    public val fallbackReason: String? = null,
    private val closeHandler: suspend (String) -> Unit,
) {
    private val closed = AtomicBoolean(false)

    /** Release this model's residency. Idempotent. */
    public suspend fun close() {
        if (!closed.compareAndSet(false, true)) return
        closeHandler(id)
    }
}

/**
 * Handle to one in-flight or completed `tts.speak`/`VoiceSession.say` utterance.
 */
public class SpeechHandle internal constructor(
    public val id: String = UUID.randomUUID().toString(),
    private val interruptHandler: suspend () -> Unit,
) {
    private val done = CompletableDeferred<Unit>()
    private val interruptedFlag = AtomicBoolean(false)

    @Volatile
    public var error: SDKException? = null
        internal set

    public val interrupted: Boolean
        get() = interruptedFlag.get()

    /** Stop playback and any in-flight synthesis. Suspends until stopped. */
    public suspend fun interrupt() {
        interruptedFlag.set(true)
        interruptHandler()
        complete()
    }

    /** Suspend until playback finishes, is interrupted, or fails. */
    public suspend fun waitForPlayout() {
        done.await()
    }

    internal fun complete(error: SDKException? = null) {
        if (error != null) this.error = error
        done.complete(Unit)
    }
}

/** How to interpret the bytes pushed to a live [SttStream]/[VadStream]. */
public data class AudioFrame(
    val samples: ByteArray,
    val sampleCount: Int,
    val timestampMs: Long? = null,
)

/**
 * Live speech-to-text session opened by `stt.openStream`. Establishes its
 * audio format once; every pushed [AudioFrame] carries PCM samples in that format.
 */
public interface SttStream {
    public val events: kotlinx.coroutines.flow.Flow<TranscriptionEvent>

    /** Push one frame of PCM audio in the stream's established format. */
    public fun pushFrame(frame: AudioFrame)

    /** Request the backend surface partials for audio pushed so far. */
    public fun flush()

    /** Signal that no more audio is coming; the backend finalizes the transcript. */
    public fun finish()

    /** Release the stream's resources. Idempotent. */
    public suspend fun close()
}

/**
 * Live voice-activity session opened by `vad.openStream`. Establishes its
 * audio format once; every pushed [AudioFrame] carries PCM samples in that format.
 */
public interface VadStream {
    public val events: kotlinx.coroutines.flow.Flow<VadEvent>

    /** Push one frame of PCM audio in the stream's established format. */
    public fun pushFrame(frame: AudioFrame)

    /** No-op when there is no partial-result buffer to flush. */
    public fun flush()

    /** Signal that no more audio is coming; completes the event stream. */
    public fun finish()

    /** Release the stream's resources. Idempotent. */
    public suspend fun close()
}

/** Whether a modality/backend/feature is honestly available right now. */
public data class UnavailableCapability(
    val name: String,
    val reason: String,
)

/** Per-modality streaming support, keyed by namespace name. */
public data class StreamingCapabilities(
    val llm: Boolean = true,
    val vlm: Boolean = true,
    val stt: Boolean = true,
    val tts: Boolean = true,
    val vad: Boolean = true,
    val rag: Boolean = true,
    val images: Boolean = true,
)

/** Tool-calling support of the currently registered backends. */
public data class ToolCapabilities(
    val registry: Boolean = true,
    val parallel: Boolean = false,
    val cancellation: Boolean = true,
)

/** RAG-session support of the currently registered backends. */
public data class RagCapabilities(
    val multiSession: Boolean = true,
    val persistent: Boolean = true,
)

/**
 * Installed, packaged, and executable surface of this SDK build, generated
 * from packaging and runtime probes rather than from IDL enum presence
 * alone. `RunAnywhere.capabilities()` is the source of truth apps should
 * consult before calling into a modality that might not ship on this platform.
 */
public data class SDKCapabilities(
    val modalities: Set<String>,
    val backends: Set<Backend>,
    val audioFormats: Set<AudioFormat>,
    val streaming: StreamingCapabilities,
    val tools: ToolCapabilities,
    val rag: RagCapabilities,
    val unavailable: List<UnavailableCapability>,
)
