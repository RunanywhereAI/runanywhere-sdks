/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public v3 surface: every result shape, with one shared metrics block on the
 * generation results so no caller computes throughput itself.
 */

package com.runanywhere.sdk.public.api

/** Why a generation stopped. */
public enum class FinishReason {
    STOP,
    LENGTH,
    TOOL_CALLS,
    CANCELLED,
}

/** A completed text or vision generation, with its metrics. */
public data class GenerationResult(
    val text: String,
    val thinkingText: String? = null,
    val toolCalls: List<ToolCall> = emptyList(),
    /** Outcomes of the tool calls the SDK executed during the loop. */
    val toolResults: List<ToolResult> = emptyList(),
    val finishReason: FinishReason = FinishReason.STOP,
    val inputTokens: Int = 0,
    val outputTokens: Int = 0,
    val timeToFirstTokenMs: Long = 0L,
    val tokensPerSecond: Float = 0f,
    val requestId: String = "",
    val model: String = "",
)

/** A generation parsed against a JSON schema, with the same metrics as [GenerationResult]. */
public data class StructuredResult(
    /** Parsed JSON, as the canonical text commons produced. */
    val value: String,
    val raw: String,
    val valid: Boolean,
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
