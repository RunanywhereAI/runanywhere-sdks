/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public v3 surface: one options type per modality.
 *
 * Defaults are read from the generated `defaults()` helpers, which carry the
 * `rac_default` annotations from idl/ — the IDL is the cross-SDK contract, so no
 * value is restated as a literal here. Turn handling is the exception: it has no
 * proto message yet, so its numbers come from the public API spec. Where a field
 * is left null the SDK omits it from the wire message and the engine's own
 * default applies.
 */

package com.runanywhere.sdk.public.api

import ai.runanywhere.proto.v1.LLMGenerationOptions
import ai.runanywhere.proto.v1.RAGConfiguration
import ai.runanywhere.proto.v1.STTOptions
import ai.runanywhere.proto.v1.TTSOptions
import ai.runanywhere.proto.v1.VADOptions
import com.runanywhere.sdk.generated.convenience.defaults

/** How the model should spend thinking tokens. */
public enum class ReasoningMode {
    /** Let the model think; thoughts are stripped from `text` unless requested. */
    ON,

    /** Suppress thinking entirely. */
    OFF,
}

/** Thinking behaviour for one generation. */
public data class ReasoningOptions(
    val mode: ReasoningMode = ReasoningMode.ON,
    val includeInOutput: Boolean = false,
    /** Null uses the model's own thinking tags. */
    val pattern: String? = null,
)

/** Which tool the model is allowed or required to call. */
public sealed class ToolChoice {
    /** The model decides whether to call a tool. */
    public data object Auto : ToolChoice()

    /** Tool calling is disabled for this generation. */
    public data object None : ToolChoice()

    /** The model must call some tool. */
    public data object Required : ToolChoice()

    /** The model must call exactly this tool. */
    public data class Forced(
        val name: String,
    ) : ToolChoice()
}

/** Schema the generated text must conform to. */
public data class StructuredOutput(
    val schema: JsonSchema,
    val strict: Boolean = true,
)

/** Sampling and tool-calling knobs for one text or vision generation. */
public data class LlmOptions(
    /** Model slug; an absent model auto-loads, downloading if needed. */
    val model: String? = null,
    val maxOutputTokens: Int = DEFAULT_MAX_OUTPUT_TOKENS,
    val temperature: Float = DEFAULT_TEMPERATURE,
    val topP: Float = DEFAULT_TOP_P,
    val topK: Int? = null,
    val minP: Float? = null,
    val frequencyPenalty: Float? = null,
    val presencePenalty: Float? = null,
    val repetitionPenalty: Float? = null,
    val seed: Int? = null,
    val stopSequences: List<String> = emptyList(),
    val systemPrompt: String? = null,
    val reasoning: ReasoningOptions? = null,
    val structuredOutput: StructuredOutput? = null,
    /** Empty uses the tools registered through `llm.tools`. */
    val tools: List<ToolDefinition> = emptyList(),
    val toolChoice: ToolChoice = ToolChoice.Auto,
    val maxToolCalls: Int = DEFAULT_MAX_TOOL_CALLS,
    /**
     * Whether the SDK should run a requested tool call itself and feed the
     * result back into the loop. `false` returns the parsed call to the
     * caller instead of invoking it — same contract as the direct
     * tool-calling API's `autoExecute`, just reachable from
     * `llm.generate`/`llm.generateStream` with inline `tools`.
     */
    val autoExecute: Boolean = true,
) {
    /** Sampling and tool-loop defaults, as annotated in idl/. */
    public companion object {
        private val generationDefaults = LLMGenerationOptions.defaults()

        public val DEFAULT_MAX_OUTPUT_TOKENS: Int = generationDefaults.max_output_tokens
        public val DEFAULT_TEMPERATURE: Float = generationDefaults.temperature
        public val DEFAULT_TOP_P: Float = generationDefaults.top_p

        // main's ToolCallingOptions carries no rac_default, so max_tool_calls has
        // no generated default. Restate the contract value as a literal.
        public const val DEFAULT_MAX_TOOL_CALLS: Int = 5
    }
}

/** Transcription knobs for one speech-to-text call. */
public data class SttOptions(
    /** BCP-47 tag; null auto-detects. */
    val language: String? = null,
    val punctuation: Boolean = DEFAULT_PUNCTUATION,
    val wordTimestamps: Boolean = DEFAULT_WORD_TIMESTAMPS,
    val diarization: Boolean = false,
    val maxSpeakers: Int? = null,
    val translateToEnglish: Boolean = false,
) {
    /** Transcription defaults, as annotated in idl/. */
    public companion object {
        private val protoDefaults = STTOptions.defaults()

        public val DEFAULT_PUNCTUATION: Boolean = protoDefaults.enable_punctuation
        public val DEFAULT_WORD_TIMESTAMPS: Boolean = protoDefaults.enable_word_timestamps
    }
}

/** Voice and audio-shape knobs for one synthesis call. */
public data class TtsOptions(
    val voice: String? = null,
    val language: String = DEFAULT_LANGUAGE,
    val speed: Float = DEFAULT_SPEED,
    val pitch: Float = DEFAULT_PITCH,
    val format: AudioFormat = DEFAULT_FORMAT,
    val sampleRate: Int = DEFAULT_SAMPLE_RATE,
) {
    /** Synthesis defaults, as annotated in idl/. */
    public companion object {
        private val protoDefaults = TTSOptions.defaults()

        public val DEFAULT_LANGUAGE: String = protoDefaults.language_code
        public val DEFAULT_SPEED: Float = protoDefaults.speed
        public val DEFAULT_PITCH: Float = protoDefaults.pitch
        public val DEFAULT_FORMAT: AudioFormat = protoDefaults.audio_format
        public val DEFAULT_SAMPLE_RATE: Int = protoDefaults.sample_rate
    }
}

/** Endpointing knobs for voice-activity detection. */
public data class VadOptions(
    /** Null uses the model's calibrated default. */
    val activationThreshold: Float? = null,
    val minSpeechMs: Int = DEFAULT_MIN_SPEECH_MS,
    val minSilenceMs: Int = DEFAULT_MIN_SILENCE_MS,
    val prefixPaddingMs: Int = DEFAULT_PREFIX_PADDING_MS,
) {
    /** Endpointing defaults, as annotated in idl/. */
    public companion object {
        private val protoDefaults = VADOptions.defaults()

        public val DEFAULT_MIN_SPEECH_MS: Int = protoDefaults.min_speech_duration_ms
        public val DEFAULT_MIN_SILENCE_MS: Int = protoDefaults.min_silence_duration_ms
        public val DEFAULT_PREFIX_PADDING_MS: Int = protoDefaults.prefix_padding_ms
    }
}

/** Post-processing applied to embedding vectors. */
public enum class NormalizeMode {
    NONE,
    L2,
}

/** How token vectors collapse into one sentence vector. */
public enum class PoolingMode {
    MEAN,
    CLS,
    LAST,
}

/** Knobs for one embedding batch. */
public data class EmbedOptions(
    val normalize: NormalizeMode = NormalizeMode.L2,
    val pooling: PoolingMode = PoolingMode.MEAN,
)

/** Whether an image request paints from scratch or repaints a masked region. */
public sealed class ImageMode {
    /** Paint a new image from the prompt alone. */
    public data object Generate : ImageMode()

    /** Repaint the white region of [mask] inside [input]. */
    public data class Inpaint(
        val input: ImageInput,
        val mask: ImageInput,
    ) : ImageMode()
}

/** Knobs for one image-generation call. */
public data class ImageOptions(
    val negativePrompt: String? = null,
    val width: Int? = null,
    val height: Int? = null,
    val steps: Int? = null,
    val guidanceScale: Float? = null,
    val seed: Int? = null,
    val mode: ImageMode = ImageMode.Generate,
    val reportPartials: Boolean = false,
)

/** Knobs for one speaker-diarization call. */
public data class DiarizationOptions(
    val threshold: Float? = null,
    val minimumDurationMs: Int? = null,
    val mergeGapMs: Int? = null,
)

/** Knobs for one semantic-segmentation call. */
public data class SegmentationOptions(
    val includeDiagnosticImage: Boolean = false,
)

/** How long silence must last before a user turn is considered finished. */
public data class Endpointing(
    val minDelayMs: Int = DEFAULT_MIN_DELAY_MS,
    val maxDelayMs: Int = DEFAULT_MAX_DELAY_MS,
) {
    public companion object {
        public const val DEFAULT_MIN_DELAY_MS: Int = 500
        public const val DEFAULT_MAX_DELAY_MS: Int = 3_000
    }
}

/** Whether the user may talk over the agent, and for how long before it yields. */
public data class Interruption(
    val enabled: Boolean = true,
    val minDurationMs: Int = DEFAULT_MIN_DURATION_MS,
) {
    public companion object {
        public const val DEFAULT_MIN_DURATION_MS: Int = 500
    }
}

/** Turn-taking behaviour for a voice session. */
public data class TurnHandlingOptions(
    val endpointing: Endpointing = Endpointing(),
    val interruption: Interruption = Interruption(),
)

/** Chunking and retrieval knobs for a RAG session. */
public data class RagConfig(
    val topK: Int = DEFAULT_TOP_K,
    val chunkSize: Int = DEFAULT_CHUNK_SIZE,
    val chunkOverlap: Int = DEFAULT_CHUNK_OVERLAP,
    val similarityThreshold: Float? = null,
    val persistPath: String? = null,
    /** Rerank retrieved chunks with the loaded cross-encoder before generating. */
    val rerank: Boolean = false,
    /** Expand each question into several retrieval queries before ranking. */
    val multiQuery: Boolean = false,
) {
    /** Chunking and retrieval defaults, as annotated in idl/. */
    public companion object {
        private val protoDefaults = RAGConfiguration.defaults()

        public val DEFAULT_TOP_K: Int = checkNotNull(protoDefaults.top_k)
        public val DEFAULT_CHUNK_SIZE: Int = checkNotNull(protoDefaults.chunk_size)
        public val DEFAULT_CHUNK_OVERLAP: Int = checkNotNull(protoDefaults.chunk_overlap)
    }
}

/** Placement knobs applied when a model is loaded. */
public data class LoadOptions(
    /** Pin the engine for this load; null lets the registry choose. */
    val framework: InferenceFramework? = null,
    val contextLength: Int? = null,
    val threads: Int? = null,
    val useGpu: Boolean? = null,
)

/** Narrows a model listing. */
public data class ModelFilter(
    val category: ModelCategory? = null,
    val framework: InferenceFramework? = null,
    val downloadedOnly: Boolean? = null,
    val availableOnly: Boolean? = null,
    val search: String? = null,
)
