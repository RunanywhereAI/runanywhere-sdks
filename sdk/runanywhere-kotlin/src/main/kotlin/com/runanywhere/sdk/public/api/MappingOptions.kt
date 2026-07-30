/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Internal bridge from the v3 options types onto the canonical generated proto
 * messages. Nothing here is public; the spec's defaults are applied once, on the
 * way down.
 */

package com.runanywhere.sdk.public.api

import ai.runanywhere.proto.v1.DiffusionGenerationOptions
import ai.runanywhere.proto.v1.DiffusionMode
import ai.runanywhere.proto.v1.EmbeddingsNormalizeMode
import ai.runanywhere.proto.v1.EmbeddingsOptions
import ai.runanywhere.proto.v1.EmbeddingsPoolingStrategy
import ai.runanywhere.proto.v1.LLMGenerationOptions
import ai.runanywhere.proto.v1.MessageRole
import ai.runanywhere.proto.v1.ModelQuery
import ai.runanywhere.proto.v1.RAGConfiguration
import ai.runanywhere.proto.v1.RAGQueryOptions
import ai.runanywhere.proto.v1.RerankOptions
import ai.runanywhere.proto.v1.STTOptions
import ai.runanywhere.proto.v1.StructuredOutputMode
import ai.runanywhere.proto.v1.StructuredOutputOptions
import ai.runanywhere.proto.v1.TTSOptions
import ai.runanywhere.proto.v1.ThinkingTagPattern
import ai.runanywhere.proto.v1.ToolCallingOptions
import ai.runanywhere.proto.v1.ToolChoiceMode
import ai.runanywhere.proto.v1.VADOptions
import ai.runanywhere.proto.v1.VLMGenerationOptions
import com.runanywhere.sdk.generated.convenience.defaults
import ai.runanywhere.proto.v1.ChatMessage as ProtoChatMessage
import ai.runanywhere.proto.v1.DiarizationOptions as ProtoDiarizationOptions
import ai.runanywhere.proto.v1.ReasoningMode as ProtoReasoningMode
import ai.runanywhere.proto.v1.ReasoningOptions as ProtoReasoningOptions
import ai.runanywhere.proto.v1.SegmentationOptions as ProtoSegmentationOptions

/** The IDL's neutral repetition penalty, used when the caller leaves it unset. */
private val NEUTRAL_REPETITION_PENALTY = LLMGenerationOptions.defaults().repetition_penalty

internal fun LlmOptions?.orDefault(): LlmOptions = this ?: LlmOptions()

internal fun LlmOptions.toProto(): LLMGenerationOptions =
    LLMGenerationOptions(
        max_output_tokens = maxOutputTokens,
        temperature = temperature,
        top_p = topP,
        top_k = topK ?: 0,
        min_p = minP ?: 0f,
        frequency_penalty = frequencyPenalty ?: 0f,
        presence_penalty = presencePenalty ?: 0f,
        repetition_penalty = repetitionPenalty ?: NEUTRAL_REPETITION_PENALTY,
        seed = seed?.toLong() ?: 0L,
        stop_sequences = stopSequences,
        system_prompt = systemPrompt,
        reasoning = reasoning?.toProto(),
        structured_output = structuredOutput?.toProto(),
        tool_calling = toolCallingProto(),
    )

internal fun LlmOptions.toVlmProto(prompt: String): VLMGenerationOptions =
    VLMGenerationOptions(
        prompt = prompt,
        max_output_tokens = maxOutputTokens,
        temperature = temperature,
        top_p = topP,
        top_k = topK ?: 0,
        min_p = minP ?: 0f,
        repetition_penalty = repetitionPenalty ?: NEUTRAL_REPETITION_PENALTY,
        system_prompt = systemPrompt,
        stop_sequences = stopSequences,
        seed = seed?.toLong() ?: 0L,
        reasoning = reasoning?.toProto(),
    )

private fun LlmOptions.toolCallingProto(): ToolCallingOptions? {
    val hasChoice = toolChoice != ToolChoice.Auto
    if (tools.isEmpty() && !hasChoice && maxToolCalls == LlmOptions.DEFAULT_MAX_TOOL_CALLS) return null
    return ToolCallingOptions(
        tools = tools,
        max_tool_calls = maxToolCalls,
        tool_choice = toolChoice.toProto(),
        forced_tool_name = (toolChoice as? ToolChoice.Forced)?.name,
    )
}

internal fun ToolChoice.toProto(): ToolChoiceMode =
    when (this) {
        ToolChoice.Auto -> ToolChoiceMode.TOOL_CHOICE_MODE_AUTO
        ToolChoice.None -> ToolChoiceMode.TOOL_CHOICE_MODE_NONE
        ToolChoice.Required -> ToolChoiceMode.TOOL_CHOICE_MODE_REQUIRED
        is ToolChoice.Forced -> ToolChoiceMode.TOOL_CHOICE_MODE_SPECIFIC
    }

internal fun ReasoningOptions.toProto(): ProtoReasoningOptions =
    ProtoReasoningOptions(
        mode =
            when (mode) {
                ReasoningMode.ON -> ProtoReasoningMode.REASONING_MODE_ON
                ReasoningMode.OFF -> ProtoReasoningMode.REASONING_MODE_OFF
            },
        include_in_output = includeInOutput,
        pattern =
            pattern?.takeIf { it.isNotBlank() }?.let { tag ->
                ThinkingTagPattern(open_tag = "<$tag>", close_tag = "</$tag>")
            },
    )

internal fun StructuredOutput.toProto(): StructuredOutputOptions =
    StructuredOutputOptions(
        schema = schema,
        strict_mode = strict,
        mode = StructuredOutputMode.STRUCTURED_OUTPUT_MODE_JSON_SCHEMA,
        include_schema_in_prompt = true,
        repair_json = !strict,
    )

internal fun SttOptions?.orDefault(): SttOptions = this ?: SttOptions()

internal fun SttOptions.toProto(): STTOptions =
    STTOptions(
        language = language,
        enable_punctuation = punctuation,
        enable_word_timestamps = wordTimestamps,
        enable_diarization = diarization,
        max_speakers = maxSpeakers ?: 0,
        translate_to_english = translateToEnglish,
    )

internal fun TtsOptions?.orDefault(): TtsOptions = this ?: TtsOptions()

internal fun TtsOptions.toProto(): TTSOptions =
    TTSOptions(
        voice = voice.orEmpty(),
        language_code = language,
        speed = speed,
        pitch = pitch,
        audio_format = format,
        sample_rate = sampleRate,
    )

internal fun VadOptions?.orDefault(): VadOptions = this ?: VadOptions()

internal fun VadOptions.toProto(): VADOptions =
    VADOptions(
        activation_threshold = activationThreshold ?: 0f,
        min_speech_duration_ms = minSpeechMs,
        min_silence_duration_ms = minSilenceMs,
        prefix_padding_ms = prefixPaddingMs,
    )

internal fun EmbedOptions?.orDefault(): EmbedOptions = this ?: EmbedOptions()

internal fun EmbedOptions.toProto(): EmbeddingsOptions =
    EmbeddingsOptions(
        normalize_mode =
            when (normalize) {
                NormalizeMode.NONE -> EmbeddingsNormalizeMode.EMBEDDINGS_NORMALIZE_MODE_NONE
                NormalizeMode.L2 -> EmbeddingsNormalizeMode.EMBEDDINGS_NORMALIZE_MODE_L2
            },
        pooling =
            when (pooling) {
                PoolingMode.MEAN -> EmbeddingsPoolingStrategy.EMBEDDINGS_POOLING_STRATEGY_MEAN
                PoolingMode.CLS -> EmbeddingsPoolingStrategy.EMBEDDINGS_POOLING_STRATEGY_CLS
                PoolingMode.LAST -> EmbeddingsPoolingStrategy.EMBEDDINGS_POOLING_STRATEGY_LAST
            },
    )

internal fun rerankOptions(topN: Int?): RerankOptions = RerankOptions(top_n = topN ?: 0)

internal fun DiarizationOptions?.orDefault(): DiarizationOptions = this ?: DiarizationOptions()

internal fun DiarizationOptions.toProto(): ProtoDiarizationOptions =
    ProtoDiarizationOptions(
        threshold = threshold,
        minimum_duration_ms = minimumDurationMs?.toLong() ?: 0L,
        merge_gap_ms = mergeGapMs?.toLong() ?: 0L,
    )

internal fun SegmentationOptions?.orDefault(): SegmentationOptions = this ?: SegmentationOptions()

internal fun SegmentationOptions.toProto(): ProtoSegmentationOptions =
    ProtoSegmentationOptions(include_diagnostic_rgba = includeDiagnosticImage)

internal fun ImageOptions?.orDefault(): ImageOptions = this ?: ImageOptions()

internal fun ImageOptions.toProto(prompt: String): DiffusionGenerationOptions {
    val inpaint = mode as? ImageMode.Inpaint
    return DiffusionGenerationOptions(
        prompt = prompt,
        negative_prompt = negativePrompt.orEmpty(),
        width = width ?: 0,
        height = height ?: 0,
        steps = steps ?: 0,
        guidance_scale = guidanceScale ?: 0f,
        seed = seed?.toLong() ?: -1L,
        mode =
            if (inpaint != null) {
                DiffusionMode.DIFFUSION_MODE_INPAINTING
            } else {
                DiffusionMode.DIFFUSION_MODE_TEXT_TO_IMAGE
            },
        input_image = inpaint?.input?.encodedBytes(),
        mask_image = inpaint?.mask?.encodedBytes(),
        input_image_media_type = inpaint?.input?.encodedMediaType(),
        mask_image_media_type = inpaint?.mask?.encodedMediaType(),
        report_intermediate_images = reportPartials,
    )
}

internal fun RagConfig?.orDefault(): RagConfig = this ?: RagConfig()

internal fun RagConfig.toProto(embeddingModelId: String, llmModelId: String): RAGConfiguration =
    RAGConfiguration(
        embedding_model_id = embeddingModelId,
        llm_model_id = llmModelId,
        top_k = topK,
        chunk_size = chunkSize,
        chunk_overlap = chunkOverlap,
        similarity_threshold = similarityThreshold,
        index_path = persistPath,
        persist_index = persistPath != null,
        rerank_results = rerank,
    )

internal fun ragQueryOptions(
    question: String,
    config: RagConfig,
    options: LlmOptions?,
    topK: Int?,
    stream: Boolean,
): RAGQueryOptions =
    RAGQueryOptions(
        question = question,
        generation = options?.toProto(),
        retrieval_top_k = topK ?: config.topK,
        similarity_threshold = config.similarityThreshold,
        stream = stream,
        enable_multi_query = config.multiQuery,
    )

internal fun ModelFilter?.toProto(): ModelQuery? {
    if (this == null) return null
    return ModelQuery(
        category = category,
        framework = framework,
        downloaded_only = downloadedOnly,
        available_only = availableOnly,
        search_query = search.orEmpty(),
    )
}

internal fun ChatMessage.toProto(): ProtoChatMessage =
    ProtoChatMessage(
        role =
            when (role) {
                ChatRole.SYSTEM -> MessageRole.MESSAGE_ROLE_SYSTEM
                ChatRole.USER -> MessageRole.MESSAGE_ROLE_USER
                ChatRole.ASSISTANT -> MessageRole.MESSAGE_ROLE_ASSISTANT
                ChatRole.TOOL -> MessageRole.MESSAGE_ROLE_TOOL
            },
        content = content,
        tool_call_id = toolCallId,
    )
