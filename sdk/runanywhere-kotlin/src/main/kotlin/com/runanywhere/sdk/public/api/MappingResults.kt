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
import ai.runanywhere.proto.v1.LLMStreamFinalResult
import ai.runanywhere.proto.v1.LoRAState
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
import ai.runanywhere.proto.v1.SegmentationResult as ProtoSegmentationResult

private const val MILLIS_PER_SECOND = 1_000.0

internal fun finishReasonOf(raw: String): FinishReason =
    when (raw.lowercase()) {
        "length", "max_tokens" -> FinishReason.LENGTH
        "tool_calls", "tool_call", "tool" -> FinishReason.TOOL_CALLS
        "cancelled", "canceled" -> FinishReason.CANCELLED
        else -> FinishReason.STOP
    }

internal fun LLMGenerationResult.toGenerationResult(requestId: String): GenerationResult =
    GenerationResult(
        text = text,
        thinkingText = thinking_content?.takeIf { it.isNotEmpty() },
        toolCalls = tool_calls,
        toolResults = tool_results,
        finishReason = finishReasonOf(finish_reason),
        inputTokens = input_tokens,
        outputTokens = output_tokens,
        timeToFirstTokenMs = ttft_ms?.toLong() ?: 0L,
        tokensPerSecond = tokens_per_second.toFloat(),
        requestId = requestId,
        model = model_used,
    )

internal fun LLMStreamFinalResult.toGenerationResult(
    requestId: String,
    model: String,
    fallbackText: String,
    fallbackThinking: String?,
): GenerationResult =
    GenerationResult(
        text = text.ifEmpty { fallbackText },
        thinkingText = thinking_content?.takeIf { it.isNotEmpty() } ?: fallbackThinking,
        toolCalls = tool_calls,
        toolResults = tool_results,
        finishReason = finishReasonOf(finish_reason),
        inputTokens = input_tokens,
        outputTokens = output_tokens,
        timeToFirstTokenMs = time_to_first_token_ms,
        tokensPerSecond = tokens_per_second,
        requestId = requestId,
        model = model,
    )

internal fun VLMResult.toGenerationResult(requestId: String, model: String): GenerationResult =
    GenerationResult(
        text = text,
        finishReason = finishReasonOf(finish_reason),
        inputTokens = input_tokens,
        outputTokens = output_tokens,
        timeToFirstTokenMs = time_to_first_token_ms,
        tokensPerSecond = tokens_per_second,
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

internal fun VADResult.toVadResult(): VadResult =
    VadResult(
        isSpeech = is_speech,
        probability = confidence,
        segments =
            if (is_speech && end_time_ms > start_time_ms) {
                listOf(Segment(startMs = start_time_ms, endMs = end_time_ms))
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

internal fun DiffusionResult.toImageResult(requestedSteps: Int): ImageResult {
    val mediaType = image_media_type?.takeIf { it.isNotEmpty() } ?: "image/png"
    val primary =
        if (image_data.size > 0) {
            listOf(ImageData(image_data.toByteArray(), width, height, mediaType))
        } else {
            emptyList()
        }
    val batch = batch_images.map { ImageData(it.toByteArray(), width, height, mediaType) }
    return ImageResult(
        images = primary + batch,
        seed = seed_used,
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
                    classId = summary.class_id.toInt(),
                    label = summary.label,
                    pixelCount = summary.pixel_count,
                    fraction = summary.fraction,
                )
            },
        diagnosticImage = diagnostic_rgba?.toByteArray(),
    )

internal fun RAGSearchResult.toMatch(): Match =
    Match(
        text = text,
        score = similarity_score,
        metadata = metadata,
    )

internal fun RAGResult.toRagResult(model: String): RagResult {
    val generationSeconds = generation_time_ms.toDouble() / MILLIS_PER_SECOND
    return RagResult(
        answer = answer,
        sources = retrieved_chunks.map { it.toMatch() },
        inputTokens = prompt_tokens,
        outputTokens = completion_tokens,
        timeToFirstTokenMs = retrieval_time_ms,
        tokensPerSecond =
            if (generationSeconds > 0.0) {
                (completion_tokens / generationSeconds).toFloat()
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

internal fun LoRAState.toLoraState(): LoraState =
    LoraState(
        applied =
            loaded_adapters
                .filter { it.applied }
                .map { AppliedAdapter(id = it.adapter_id.ifEmpty { it.adapter_path }, scale = it.scale) },
    )
