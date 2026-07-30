/**
 * Translation between the public v3 option bags and the generated proto
 * messages the native bridge speaks.
 *
 * Every default comes from a generated `*Defaults()` helper so the IDL stays
 * the single declaration of a default. Nothing in this file writes a literal
 * default value.
 */

import { AudioFormat } from '@runanywhere/proto-ts/model_types';
import { LLMGenerationOptions } from '@runanywhere/proto-ts/llm_options';
import { lLMGenerationOptionsDefaults } from '@runanywhere/proto-ts/convenience/llm_options_convenience';
import {
  ReasoningMode,
  ReasoningOptions as ReasoningOptionsMessage,
  ThinkingTagPattern,
} from '@runanywhere/proto-ts/thinking_tag_pattern';
import {
  StructuredOutputOptions,
  type JSONSchema,
} from '@runanywhere/proto-ts/structured_output';
import {
  ToolCallingOptions,
  ToolChoiceMode,
  type ToolDefinition,
} from '@runanywhere/proto-ts/tool_calling';
import { toolCallingOptionsDefaults } from '@runanywhere/proto-ts/convenience/tool_calling_convenience';
import { STTOptions } from '@runanywhere/proto-ts/stt_options';
import { sTTOptionsDefaults } from '@runanywhere/proto-ts/convenience/stt_options_convenience';
import { TTSOptions } from '@runanywhere/proto-ts/tts_options';
import { tTSOptionsDefaults } from '@runanywhere/proto-ts/convenience/tts_options_convenience';
import { VADOptions } from '@runanywhere/proto-ts/vad_options';
import { vADOptionsDefaults } from '@runanywhere/proto-ts/convenience/vad_options_convenience';
import {
  EmbeddingsNormalizeMode,
  EmbeddingsOptions,
  EmbeddingsPoolingStrategy,
} from '@runanywhere/proto-ts/embeddings_options';
import { embeddingsOptionsDefaults } from '@runanywhere/proto-ts/convenience/embeddings_options_convenience';
import {
  DiffusionGenerationOptions,
  DiffusionMode,
} from '@runanywhere/proto-ts/diffusion_options';
import { diffusionGenerationOptionsDefaults } from '@runanywhere/proto-ts/convenience/diffusion_options_convenience';
import { DiarizationOptions as DiarizationOptionsMessage } from '@runanywhere/proto-ts/diarization';
import { diarizationOptionsDefaults } from '@runanywhere/proto-ts/convenience/diarization_convenience';
import { SegmentationOptions as SegmentationOptionsMessage } from '@runanywhere/proto-ts/segmentation';
import { RAGConfiguration } from '@runanywhere/proto-ts/rag';
import { rAGConfigurationDefaults } from '@runanywhere/proto-ts/convenience/rag_convenience';
import { RerankOptions } from '@runanywhere/proto-ts/rerank';
import { rerankOptionsDefaults } from '@runanywhere/proto-ts/convenience/rerank_convenience';
import { VLMGenerationOptions } from '@runanywhere/proto-ts/vlm_options';
import { vLMGenerationOptionsDefaults } from '@runanywhere/proto-ts/convenience/vlm_options_convenience';

import type {
  AudioFormatName,
  DiarizationOptions,
  EmbedOptions,
  ImageOptions,
  LlmOptions,
  RagConfig,
  ReasoningOptions,
  SegmentationOptions,
  SttOptions,
  StructuredOutput,
  ToolChoice,
  TtsOptions,
  VadOptions,
} from './Types';
import { encodeImageBytes } from './Inputs';

/** Strip keys whose value is `undefined` so proto defaults survive a spread. */
function defined<T extends object>(value: T): Partial<T> {
  const out: Record<string, unknown> = {};
  for (const [key, item] of Object.entries(value)) {
    if (item !== undefined) out[key] = item;
  }
  return out as Partial<T>;
}

const audioFormatByName: Record<AudioFormatName, AudioFormat> = {
  pcm: AudioFormat.AUDIO_FORMAT_PCM,
  wav: AudioFormat.AUDIO_FORMAT_WAV,
  mp3: AudioFormat.AUDIO_FORMAT_MP3,
  opus: AudioFormat.AUDIO_FORMAT_OPUS,
  flac: AudioFormat.AUDIO_FORMAT_FLAC,
  aac: AudioFormat.AUDIO_FORMAT_AAC,
};

/** Map a public audio-format name onto the proto enum. */
export function toAudioFormat(name: AudioFormatName): AudioFormat {
  return audioFormatByName[name];
}

/** Map a proto audio-format enum onto its public name. */
export function fromAudioFormat(format: AudioFormat): AudioFormatName {
  switch (format) {
    case AudioFormat.AUDIO_FORMAT_WAV:
      return 'wav';
    case AudioFormat.AUDIO_FORMAT_MP3:
      return 'mp3';
    case AudioFormat.AUDIO_FORMAT_OPUS:
      return 'opus';
    case AudioFormat.AUDIO_FORMAT_FLAC:
      return 'flac';
    case AudioFormat.AUDIO_FORMAT_AAC:
      return 'aac';
    default:
      return 'pcm';
  }
}

function toReasoningOptions(
  reasoning: ReasoningOptions
): ReasoningOptionsMessage {
  return ReasoningOptionsMessage.fromPartial({
    mode:
      reasoning.mode === 'off'
        ? ReasoningMode.REASONING_MODE_OFF
        : ReasoningMode.REASONING_MODE_ON,
    includeInOutput: reasoning.includeInOutput ?? false,
    ...(reasoning.pattern
      ? {
          pattern: ThinkingTagPattern.fromPartial({
            openTag: `<${reasoning.pattern}>`,
            closeTag: `</${reasoning.pattern}>`,
          }),
        }
      : {}),
  });
}

function toStructuredOutputOptions(
  structured: StructuredOutput
): StructuredOutputOptions {
  return StructuredOutputOptions.fromPartial({
    schema: structured.schema,
    strictMode: structured.strict ?? true,
    includeSchemaInPrompt: true,
  });
}

function toToolChoiceMode(choice: ToolChoice): {
  toolChoice: ToolChoiceMode;
  forcedToolName?: string;
} {
  if (typeof choice === 'object') {
    return {
      toolChoice: ToolChoiceMode.TOOL_CHOICE_MODE_SPECIFIC,
      forcedToolName: choice.forced,
    };
  }
  switch (choice) {
    case 'none':
      return { toolChoice: ToolChoiceMode.TOOL_CHOICE_MODE_NONE };
    case 'required':
      return { toolChoice: ToolChoiceMode.TOOL_CHOICE_MODE_REQUIRED };
    default:
      return { toolChoice: ToolChoiceMode.TOOL_CHOICE_MODE_AUTO };
  }
}

/** Build the proto tool-calling submessage for a request. */
export function toToolCallingOptions(
  tools: ToolDefinition[],
  options?: LlmOptions
): ToolCallingOptions {
  return ToolCallingOptions.fromPartial({
    ...toolCallingOptionsDefaults(),
    tools,
    ...defined({ maxToolCalls: options?.maxToolCalls }),
    ...(options?.toolChoice ? toToolChoiceMode(options.toolChoice) : {}),
  });
}

/** Merge public LLM options over the generated proto defaults. */
export function toLlmOptions(options?: LlmOptions): LLMGenerationOptions {
  return LLMGenerationOptions.fromPartial({
    ...lLMGenerationOptionsDefaults(),
    ...defined({
      maxOutputTokens: options?.maxOutputTokens,
      temperature: options?.temperature,
      topP: options?.topP,
      topK: options?.topK,
      minP: options?.minP,
      frequencyPenalty: options?.frequencyPenalty,
      presencePenalty: options?.presencePenalty,
      repetitionPenalty: options?.repetitionPenalty,
      seed: options?.seed,
      systemPrompt: options?.systemPrompt,
      stopSequences: options?.stopSequences,
    }),
    ...(options?.reasoning
      ? { reasoning: toReasoningOptions(options.reasoning) }
      : {}),
    ...(options?.structuredOutput
      ? { structuredOutput: toStructuredOutputOptions(options.structuredOutput) }
      : {}),
  });
}

/** Merge public LLM options over the generated VLM proto defaults. */
export function toVlmOptions(
  prompt: string,
  options?: LlmOptions
): VLMGenerationOptions {
  return VLMGenerationOptions.fromPartial({
    ...vLMGenerationOptionsDefaults(),
    prompt,
    ...defined({
      maxOutputTokens: options?.maxOutputTokens,
      temperature: options?.temperature,
      topP: options?.topP,
      topK: options?.topK,
      minP: options?.minP,
      repetitionPenalty: options?.repetitionPenalty,
      seed: options?.seed,
      stopSequences: options?.stopSequences,
      systemPrompt: options?.systemPrompt,
    }),
    ...(options?.reasoning
      ? { reasoning: toReasoningOptions(options.reasoning) }
      : {}),
  });
}

/** Merge public STT options over the generated proto defaults. */
export function toSttOptions(options?: SttOptions): STTOptions {
  return STTOptions.fromPartial({
    ...sTTOptionsDefaults(),
    ...defined({
      language: options?.language,
      enablePunctuation: options?.punctuation,
      enableWordTimestamps: options?.wordTimestamps,
      enableDiarization: options?.diarization,
      maxSpeakers: options?.maxSpeakers,
      translateToEnglish: options?.translateToEnglish,
    }),
  });
}

/** Merge public TTS options over the generated proto defaults. */
export function toTtsOptions(options?: TtsOptions): TTSOptions {
  return TTSOptions.fromPartial({
    ...tTSOptionsDefaults(),
    ...defined({
      voice: options?.voice,
      languageCode: options?.language,
      speed: options?.speed,
      pitch: options?.pitch,
      sampleRate: options?.sampleRate,
      audioFormat: options?.format ? toAudioFormat(options.format) : undefined,
    }),
  });
}

/** Merge public VAD options over the generated proto defaults. */
export function toVadOptions(options?: VadOptions): VADOptions {
  return VADOptions.fromPartial({
    ...vADOptionsDefaults(),
    ...defined({
      activationThreshold: options?.activationThreshold,
      minSpeechDurationMs: options?.minSpeechMs,
      minSilenceDurationMs: options?.minSilenceMs,
      prefixPaddingMs: options?.prefixPaddingMs,
    }),
  });
}

/** Merge public embedding options over the generated proto defaults. */
export function toEmbedOptions(options?: EmbedOptions): EmbeddingsOptions {
  const normalize =
    options?.normalize === undefined
      ? undefined
      : options.normalize === 'none'
        ? EmbeddingsNormalizeMode.EMBEDDINGS_NORMALIZE_MODE_NONE
        : EmbeddingsNormalizeMode.EMBEDDINGS_NORMALIZE_MODE_L2;
  const pooling =
    options?.pooling === undefined
      ? undefined
      : options.pooling === 'cls'
        ? EmbeddingsPoolingStrategy.EMBEDDINGS_POOLING_STRATEGY_CLS
        : options.pooling === 'last'
          ? EmbeddingsPoolingStrategy.EMBEDDINGS_POOLING_STRATEGY_LAST
          : EmbeddingsPoolingStrategy.EMBEDDINGS_POOLING_STRATEGY_MEAN;
  return EmbeddingsOptions.fromPartial({
    ...embeddingsOptionsDefaults(),
    ...defined({ normalizeMode: normalize, pooling }),
  });
}

/** Merge public rerank options over the generated proto defaults. */
export function toRerankOptions(topN?: number): RerankOptions {
  return RerankOptions.fromPartial({
    ...rerankOptionsDefaults(),
    ...defined({ topN }),
  });
}

/** Merge public image options over the generated proto defaults. */
export function toImageOptions(
  prompt: string,
  options?: ImageOptions
): DiffusionGenerationOptions {
  const inpaint =
    options?.mode && typeof options.mode === 'object'
      ? options.mode.inpaint
      : undefined;
  return DiffusionGenerationOptions.fromPartial({
    ...diffusionGenerationOptionsDefaults(),
    prompt,
    ...defined({
      negativePrompt: options?.negativePrompt,
      width: options?.width,
      height: options?.height,
      steps: options?.steps,
      guidanceScale: options?.guidanceScale,
      seed: options?.seed,
      reportIntermediateImages: options?.reportPartials,
    }),
    ...(inpaint
      ? {
          mode: DiffusionMode.DIFFUSION_MODE_INPAINTING,
          inputImage: encodeImageBytes(inpaint.input),
          maskImage: encodeImageBytes(inpaint.mask),
        }
      : { mode: DiffusionMode.DIFFUSION_MODE_TEXT_TO_IMAGE }),
  });
}

/** Merge public diarization options over the generated proto defaults. */
export function toDiarizationOptions(
  options?: DiarizationOptions
): DiarizationOptionsMessage {
  return DiarizationOptionsMessage.fromPartial({
    ...diarizationOptionsDefaults(),
    ...defined({
      threshold: options?.threshold,
      minimumDurationMs: options?.minimumDurationMs,
      mergeGapMs: options?.mergeGapMs,
    }),
  });
}

/** Build the proto segmentation options for a request. */
export function toSegmentationOptions(
  options?: SegmentationOptions
): SegmentationOptionsMessage {
  return SegmentationOptionsMessage.fromPartial(
    defined({ includeDiagnosticRgba: options?.includeDiagnosticImage })
  );
}

/** Merge public RAG configuration over the generated proto defaults. */
export function toRagConfiguration(
  embeddingModelId: string,
  llmModelId: string,
  config?: RagConfig
): RAGConfiguration {
  return RAGConfiguration.fromPartial({
    ...rAGConfigurationDefaults(),
    embeddingModelId,
    llmModelId,
    ...defined({
      topK: config?.topK,
      chunkSize: config?.chunkSize,
      chunkOverlap: config?.chunkOverlap,
      similarityThreshold: config?.similarityThreshold,
      indexPath: config?.persistPath,
    }),
    ...(config?.persistPath ? { persistIndex: true } : {}),
  });
}
