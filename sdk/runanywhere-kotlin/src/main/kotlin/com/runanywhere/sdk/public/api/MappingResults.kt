/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Internal bridge from the generated proto results onto the v3 result types.
 * Every generation result leaves here with its metrics block populated.
 */

package com.runanywhere.sdk.public.api

import ai.runanywhere.proto.v1.DiffusionResult
import ai.runanywhere.proto.v1.EmbeddingsResult
import ai.runanywhere.proto.v1.LLMGenerationResult
import ai.runanywhere.proto.v1.RAGResult
import ai.runanywhere.proto.v1.RAGSearchResult
import ai.runanywhere.proto.v1.RAGStatistics
import ai.runanywhere.proto.v1.RerankResult
import ai.runanywhere.proto.v1.STTOutput
import ai.runanywhere.proto.v1.STTServiceState
import ai.runanywhere.proto.v1.TTSOutput
import ai.runanywhere.proto.v1.VADResult
import ai.runanywhere.proto.v1.VLMResult
import ai.runanywhere.proto.v1.DiarizationResult as ProtoDiarizationResult
import ai.runanywhere.proto.v1.LoraState as ProtoLoraState
import ai.runanywhere.proto.v1.SegmentationResult as ProtoSegmentationResult

private const val MILLIS_PER_SECOND = 1_000.0

/** Maps a generated [ai.runanywhere.proto.v1.FinishReason] onto the v3 [FinishReason]. */
internal fun finishReasonOf(raw: ai.runanywhere.proto.v1.FinishReason): FinishReason =
    when (raw) {
        ai.runanywhere.proto.v1.FinishReason.FINISH_REASON_STOP,
        ai.runanywhere.proto.v1.FinishReason.FINISH_REASON_STOP_SEQUENCE,
        -> FinishReason.STOP
        ai.runanywhere.proto.v1.FinishReason.FINISH_REASON_LENGTH -> FinishReason.LENGTH
        ai.runanywhere.proto.v1.FinishReason.FINISH_REASON_TOOL_CALLS -> FinishReason.TOOL_CALLS
        ai.runanywhere.proto.v1.FinishReason.FINISH_REASON_CANCELLED -> FinishReason.CANCELLED
        ai.runanywhere.proto.v1.FinishReason.FINISH_REASON_CONTEXT_OVERFLOW,
        ai.runanywhere.proto.v1.FinishReason.FINISH_REASON_ERROR,
        -> FinishReason.UNKNOWN
        else -> FinishReason.UNKNOWN
    }

internal fun LLMGenerationResult.toGenerationResult(requestId: String): GenerationResult =
    GenerationResult(
        text = text,
        thinkingText = thinking_content?.takeIf { it.isNotEmpty() },
        toolCalls = tool_calls,
        toolResults = tool_results,
        finishReason = finishReasonOf(finish_reason),
        rawFinishReason = finish_reason.name,
        inputTokens = usage?.input_tokens ?: 0,
        outputTokens = usage?.output_tokens ?: 0,
        timeToFirstTokenMs = usage?.ttft_ms ?: 0L,
        tokensPerSecond = (usage?.decode_tokens_per_second ?: 0.0).toFloat(),
        requestId = requestId,
        model = model_used,
    )

// LLMStreamFinalResult is deleted: the stream terminates with the same
// LLMGenerationResult type the unary call returns (LLMStreamEvent.result),
// so LLMGenerationResult.toGenerationResult(requestId) above serves both
// paths instead of two near-identical mappers.

internal fun VLMResult.toGenerationResult(requestId: String, model: String): GenerationResult =
    GenerationResult(
        text = text,
        // VLMResult.finish_reason is a free-form string ("stop" | "length" |
        // "stop_sequence"), not the FinishReason enum -- reuse the same
        // wire-vocabulary parser LLMNamespace's stream mapper uses.
        finishReason =
            when (finish_reason) {
                "length" -> FinishReason.LENGTH
                "tool_calls" -> FinishReason.TOOL_CALLS
                "cancelled", "canceled" -> FinishReason.CANCELLED
                else -> FinishReason.STOP
            },
        rawFinishReason = finish_reason.takeIf { it.isNotEmpty() },
        inputTokens = usage?.input_tokens ?: 0,
        outputTokens = usage?.output_tokens ?: 0,
        timeToFirstTokenMs = usage?.ttft_ms ?: 0L,
        tokensPerSecond = (usage?.decode_tokens_per_second ?: 0.0).toFloat(),
        requestId = requestId,
        model = model,
    )

internal fun STTOutput.toTranscription(): Transcription =
    Transcription(
        text = text,
        language = language?.takeIf { it.isNotEmpty() },
        confidence = confidence,
        words =
            words.map { word ->
                Word(
                    text = word.word,
                    startMs = word.start_ms,
                    endMs = word.end_ms,
                    confidence = word.confidence,
                    speakerId = word.speaker_id?.takeIf { it.isNotEmpty() },
                )
            },
        durationMs = duration_ms,
    )

internal fun STTServiceState.toSttState(): SttState =
    SttState(
        isReady = is_ready,
        modelId = current_model?.takeIf { it.isNotEmpty() },
        supportsStreaming = supports_streaming,
        languages = supported_language_codes,
    )

internal fun TTSOutput.toAudio(fallbackSampleRate: Int): Audio =
    Audio(
        data = audio_data.toByteArray(),
        sampleRate = if (sample_rate > 0) sample_rate else fallbackSampleRate,
        format = audio_format,
        durationMs = duration_ms,
    )

internal fun TTSOutput.toAudioChunk(): AudioChunk =
    AudioChunk(
        data = audio_data.toByteArray(),
        index = chunk_index,
        isFinal = is_final,
    )

/**
 * `VADResult.confidence`/`.start_time_ms`/`.end_time_ms` were deleted outright
 * (idl/vad_options.proto): `confidence` is renamed `probability`, and the
 * start/end pair has no replacement -- the result now only carries
 * `timestamp_ms` (frame start) + `duration_ms` (frame length). Derive the
 * one segment this frame represents from that pair instead of a span.
 */
internal fun VADResult.toVadResult(): VadResult =
    VadResult(
        isSpeech = is_speech,
        probability = probability,
        segments =
            if (is_speech && duration_ms > 0) {
                listOf(Segment(startMs = timestamp_ms, endMs = timestamp_ms + duration_ms))
            } else {
                emptyList()
            },
    )

internal fun EmbeddingsResult.toEmbeddings(): List<Embedding> =
    vectors.mapIndexed { position, vector ->
        Embedding(
            index = if (vector.input_index > 0) vector.input_index else position,
            vector = vector.values.toFloatArray(),
        )
    }

internal fun RerankResult.toRankedResults(): List<RankedResult> =
    items
        .map { RankedResult(index = it.index.toInt(), relevanceScore = it.relevance_score) }
        .sortedByDescending { it.relevanceScore }

/**
 * `DiffusionResult` was reshaped from a flat width/height/imageData/
 * batchImages/seedUsed quintuple into `repeated DiffusionImage images` (each
 * carrying its own data/width/height/seedUsed/mediaType) + `total_time_ms`.
 * `seed` surfaces the first image's seed for backward-compatible
 * single-image callers.
 */
internal fun DiffusionResult.toImageResult(requestedSteps: Int): ImageResult {
    val mapped =
        images.map { image ->
            ImageData(
                bytes = image.data_.toByteArray(),
                width = image.width,
                height = image.height,
                mediaType = image.media_type.takeIf { it.isNotEmpty() } ?: "image/png",
            )
        }
    return ImageResult(
        images = mapped,
        seed = images.firstOrNull()?.seed_used ?: 0L,
        steps = requestedSteps,
    )
}

internal fun ProtoDiarizationResult.toDiarizationResult(): DiarizationResult =
    DiarizationResult(
        segments =
            segments.map { segment ->
                SpeakerSegment(
                    speakerId = segment.speaker_id.ifEmpty { "speaker_${segment.speaker_index}" },
                    startMs = segment.start_ms,
                    endMs = segment.end_ms,
                )
            },
        speakerCount = speaker_count,
    )

internal fun ProtoSegmentationResult.toSegmentationResult(): SegmentationResult =
    SegmentationResult(
        classMask = class_mask_u16_le.toByteArray(),
        width = width,
        height = height,
        classes =
            class_summaries.map { summary ->
                ClassInfo(
                    classId = summary.class_id,
                    label = summary.label,
                    pixelCount = summary.pixel_count,
                    fraction = 0f,
                )
            },
        diagnosticImage = diagnostic_rgba?.toByteArray(),
    )

internal fun RAGSearchResult.toMatch(): Match =
    Match(
        text = text,
        score = score,
        metadata = metadata,
    )

internal fun RAGResult.toRagResult(model: String): RagResult {
    val generationSeconds = generation_time_ms.toDouble() / MILLIS_PER_SECOND
    return RagResult(
        answer = answer,
        sources = retrieved_chunks.map { it.toMatch() },
        inputTokens = usage?.input_tokens ?: 0,
        outputTokens = usage?.output_tokens ?: 0,
        timeToFirstTokenMs = retrieval_time_ms,
        tokensPerSecond =
            if (generationSeconds > 0.0) {
                ((usage?.output_tokens ?: 0) / generationSeconds).toFloat()
            } else {
                0f
            },
        requestId = request_id,
        model = model,
    )
}

internal fun RAGStatistics.toRagStats(): RagStats =
    RagStats(
        documentCount = indexed_documents,
        chunkCount = indexed_chunks,
        indexSizeBytes = vector_store_size_bytes,
    )

internal fun ProtoLoraState.toLoraState(): LoraState =
    LoraState(
        applied =
            loaded_adapters
                .filter { it.applied }
                .map { AppliedAdapter(id = it.adapter_id.ifEmpty { it.adapter_path }, scale = it.scale) },
    )
