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
import ai.runanywhere.proto.v1.EmbeddingsOptions
import ai.runanywhere.proto.v1.EmbeddingsPoolingStrategy
import ai.runanywhere.proto.v1.LLMGenerationOptions
import ai.runanywhere.proto.v1.MessageRole
import ai.runanywhere.proto.v1.ModelQuery
import ai.runanywhere.proto.v1.RAGConfiguration
import ai.runanywhere.proto.v1.RAGQueryOptions
import ai.runanywhere.proto.v1.RAGRetrievalOptions
import ai.runanywhere.proto.v1.RerankOptions
import ai.runanywhere.proto.v1.STTOptions
import ai.runanywhere.proto.v1.StructuredOutputOptions
import ai.runanywhere.proto.v1.TTSOptions
import ai.runanywhere.proto.v1.ThinkingTagPattern
import ai.runanywhere.proto.v1.ToolCallingOptions
import ai.runanywhere.proto.v1.ToolChoiceMode
import ai.runanywhere.proto.v1.VADOptions
import ai.runanywhere.proto.v1.VLMGenerationRequest
import ai.runanywhere.proto.v1.VLMImage
import com.runanywhere.sdk.generated.convenience.defaults
import ai.runanywhere.proto.v1.ChatMessage as ProtoChatMessage
import ai.runanywhere.proto.v1.DiarizationOptions as ProtoDiarizationOptions
import ai.runanywhere.proto.v1.ReasoningMode as ProtoReasoningMode
import ai.runanywhere.proto.v1.ReasoningOptions as ProtoReasoningOptions
import ai.runanywhere.proto.v1.SegmentationOptions as ProtoSegmentationOptions

/** The IDL's neutral repetition penalty, used when the caller leaves it unset. */
private val NEUTRAL_REPETITION_PENALTY = LLMGenerationOptions.defaults().repeat_penalty

internal fun LlmOptions?.orDefault(): LlmOptions = this ?: LlmOptions()

/**
 * [structuredOutput] is never populated from a public [LlmOptions] field —
 * only `llm.generateStructured` supplies it, through its own internal call path.
 */
internal fun LlmOptions.toProto(structuredOutput: StructuredOutput? = null): LLMGenerationOptions =
    LLMGenerationOptions(
        max_output_tokens = maxOutputTokens,
        temperature = temperature,
        top_p = topP,
        top_k = topK ?: 0,
        min_p = minP ?: 0f,
        frequency_penalty = frequencyPenalty ?: 0f,
        presence_penalty = presencePenalty ?: 0f,
        repeat_penalty = repetitionPenalty ?: NEUTRAL_REPETITION_PENALTY,
        seed = seed?.toLong() ?: 0L,
        stop_sequences = stopSequences,
        system_prompt = systemPrompt,
        reasoning = reasoning?.toProto(),
        structured_output = structuredOutput?.toProto(),
        tool_calling = toolCallingProto(),
    )

/**
 * Build the VLM request envelope. `VLMGenerationOptions` was deleted outright
 * (idl/vlm_options.proto): its 11 sampling fields were name-for-name copies
 * of `LLMGenerationOptions` with drifted defaults, so VLM now shares the
 * exact same [toProto] options this file already builds for `llm`.
 * `vision`/`images` carry the four genuinely vision-specific knobs and the
 * image payload; neither has a public [LlmOptions] knob yet, so `vision`
 * stays default (mirrors Swift `LlmOptions.toVLMRequest(prompt:images:)`).
 */
internal fun LlmOptions.toVlmProto(prompt: String, images: List<VLMImage>): VLMGenerationRequest =
    VLMGenerationRequest(
        prompt = prompt,
        images = images,
        options = toProto(),
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

/**
 * `StructuredOutputOptions.strict_mode`/`.mode`/`.repair_json` are all
 * deleted (idl/structured_output.proto): the message shrank to
 * `include_schema_in_prompt` plus a `oneof constraint { schema | grammar |
 * regex }`. [StructuredOutput.strict] has no wire home any more — retry
 * behaviour for an invalid first pass is owned entirely by the Kotlin-side
 * `llm.generateStructured(mode = REPAIR)` loop, not by a commons flag.
 */
internal fun StructuredOutput.toProto(): StructuredOutputOptions =
    StructuredOutputOptions(
        schema = schema.rawJson,
        include_schema_in_prompt = true,
    )

internal fun SttOptions?.orDefault(): SttOptions = this ?: SttOptions()

// enable_diarization / max_speakers / translate_to_english are renamed or
// deleted (idl/stt_options.proto): diarize (bool) replaces enable_diarization,
// speakers_expected (optional int32) replaces max_speakers (0 no longer means
// "unset" -- omitting the field does), and translate_to_english has no
// surviving field at all.
internal fun SttOptions.toProto(): STTOptions =
    STTOptions(
        language = language,
        enable_punctuation = punctuation,
        enable_word_timestamps = wordTimestamps,
        diarize = diarization,
        speakers_expected = maxSpeakers,
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

internal fun VadOptions.toProto(
    sampleRate: Int = AudioFormatSpec.DEFAULT_SAMPLE_RATE,
): VADOptions =
    VADOptions(
        activation_threshold = activationThreshold ?: 0f,
        min_speech_duration_ms = minSpeechMs,
        min_silence_duration_ms = minSilenceMs,
        prefix_padding_ms = prefixPaddingMs,
        sample_rate = sampleRate,
    )

internal fun EmbedOptions?.orDefault(): EmbedOptions = this ?: EmbedOptions()

internal fun EmbedOptions.toProto(): EmbeddingsOptions =
    EmbeddingsOptions(
        normalize = normalize == NormalizeMode.L2,
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

// Mode is inferred, never declared (idl/diffusion.proto): no image =
// text-to-image, image = image-to-image, image + mask_image = inpainting.
// DiffusionMode / input_image / input_image_media_type /
// report_intermediate_images are all deleted; the surviving fields are
// `image` / `image_media_type` / `strength`.
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
        image = inpaint?.input?.encodedBytes(),
        mask_image = inpaint?.mask?.encodedBytes(),
        image_media_type = inpaint?.input?.encodedMediaType(),
        mask_image_media_type = inpaint?.mask?.encodedMediaType(),
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
        score_threshold = similarityThreshold,
        rerank_results = rerank,
    )

// `RAGQueryOptions.stream` is deleted outright (idl/rag.proto): the C++ ABI
// (rac_rag_proto_abi.cpp) never read it -- streaming vs. blocking is chosen
// entirely by which entry point the caller invokes (rac_rag_query_proto vs.
// rac_rag_query_stream_proto), both parsing the identical RAGQueryOptions
// payload, so this builder no longer takes a `stream` flag.
// `question`/`retrieval_top_k`/`similarity_threshold` are likewise gone: the
// flat fields collapsed onto the shared `RAGRetrievalOptions` message
// (`query` + nested `retrieval`), matching RAGSearchRequest's shape.
internal fun ragQueryProto(
    question: String,
    config: RagConfig,
    options: RagQueryOptions?,
): RAGQueryOptions =
    RAGQueryOptions(
        query = question,
        retrieval =
            RAGRetrievalOptions(
                top_k = options?.retrieval?.topK ?: config.topK,
                score_threshold = options?.retrieval?.similarityThreshold ?: config.similarityThreshold,
                enable_multi_query = config.multiQuery,
            ),
        generation = options?.generation?.toProto(),
    )

internal fun ModelFilter?.toProto(): ModelQuery? {
    if (this == null) return null
    return ModelQuery(
        category = category,
        framework = framework,
        downloaded_only = downloadedOnly,
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
