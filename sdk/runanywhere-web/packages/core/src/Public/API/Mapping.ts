/**
 * Translation between the v3 public option/result shapes and the generated
 * proto messages the C++ core speaks. Internal — never exported from the
 * package root.
 */

import { AudioFormat, type ModelCategory } from '@runanywhere/proto-ts/model_types';
import {
  LLMGenerationOptions as LLMGenerationOptionsMessage,
  type LLMGenerationOptions,
  type LLMGenerationResult,
} from '@runanywhere/proto-ts/llm_options';
import { ReasoningMode } from '@runanywhere/proto-ts/thinking_tag_pattern';
import { ToolChoiceMode } from '@runanywhere/proto-ts/tool_calling';
import { StructuredOutputMode, type StructuredOutputResult } from '@runanywhere/proto-ts/structured_output';
import type { STTOptions, STTOutput } from '@runanywhere/proto-ts/stt_options';
import type { TTSOptions, TTSOutput, TTSVoiceInfo } from '@runanywhere/proto-ts/tts_options';
import type { VADOptions, VADResult as ProtoVadResult } from '@runanywhere/proto-ts/vad_options';
import {
  EmbeddingsPoolingStrategy,
  type EmbeddingsOptions,
  type EmbeddingsResult,
} from '@runanywhere/proto-ts/embeddings_options';
import {
  DiffusionMode,
  type DiffusionGenerationOptions,
  type DiffusionResult,
} from '@runanywhere/proto-ts/diffusion_options';
import type { DiarizationOptions as ProtoDiarizationOptions, DiarizationResult as ProtoDiarizationResult } from '@runanywhere/proto-ts/diarization';
import type { SegmentationResult as ProtoSegmentationResult } from '@runanywhere/proto-ts/segmentation';
import type { RerankResult } from '@runanywhere/proto-ts/rerank';
import type { RAGResult, RAGSearchResult, RAGStatistics } from '@runanywhere/proto-ts/rag';
import type { VLMResult } from '@runanywhere/proto-ts/vlm_options';
import type { LLMStreamFinalResult } from '@runanywhere/proto-ts/llm_service';
import type { LoRAState } from '@runanywhere/proto-ts/lora_options';
import type {
  DiarizationOptions,
  EmbedOptions,
  ImageOptions,
  LlmOptions,
  SttOptions,
  TtsOptions,
  VadOptions,
} from './Options.js';
import { optionDefaults } from './Options.js';
import type {
  Audio,
  DiarizationResult,
  Embedding,
  FinishReason,
  GenerationMetrics,
  GenerationResult,
  ImageResult,
  LoraState,
  Match,
  RagResult,
  RagStats,
  RankedResult,
  SegmentationResult,
  StructuredResult,
  Transcription,
  VadResult,
  Voice,
} from './Results.js';
import type { ChatMessage } from './Inputs.js';
import { ChatMessage as ProtoChatMessageMessage, MessageRole } from '@runanywhere/proto-ts/chat';
import type { ChatMessage as ProtoChatMessage } from '@runanywhere/proto-ts/chat';

function reasoningMode(mode: 'on' | 'off' | undefined): ReasoningMode {
  if (mode === 'off') return ReasoningMode.REASONING_MODE_OFF;
  if (mode === 'on') return ReasoningMode.REASONING_MODE_ON;
  return ReasoningMode.REASONING_MODE_UNSPECIFIED;
}

function toolChoiceMode(choice: LlmOptions['toolChoice']): ToolChoiceMode {
  switch (choice?.kind) {
    case 'none': return ToolChoiceMode.TOOL_CHOICE_MODE_NONE;
    case 'required': return ToolChoiceMode.TOOL_CHOICE_MODE_REQUIRED;
    case 'forced': return ToolChoiceMode.TOOL_CHOICE_MODE_SPECIFIC;
    default: return ToolChoiceMode.TOOL_CHOICE_MODE_AUTO;
  }
}

/** Build the proto generation options, filling gaps from the IDL defaults. */
export function toProtoLlmOptions(options?: LlmOptions): LLMGenerationOptions {
  const defaults = optionDefaults.llm();
  const partial: Partial<LLMGenerationOptions> = {
    maxOutputTokens: options?.maxOutputTokens ?? defaults.maxOutputTokens,
    temperature: options?.temperature ?? defaults.temperature,
    topP: options?.topP ?? defaults.topP,
    topK: options?.topK ?? defaults.topK,
    minP: options?.minP ?? defaults.minP,
    frequencyPenalty: options?.frequencyPenalty ?? defaults.frequencyPenalty,
    presencePenalty: options?.presencePenalty ?? defaults.presencePenalty,
    repetitionPenalty: options?.repetitionPenalty ?? defaults.repetitionPenalty,
    seed: options?.seed ?? defaults.seed,
    stopSequences: options?.stopSequences ?? defaults.stopSequences,
    systemPrompt: options?.systemPrompt,
  };

  if (options?.reasoning) {
    partial.reasoning = {
      mode: reasoningMode(options.reasoning.mode ?? 'on'),
      includeInOutput: options.reasoning.includeInOutput ?? false,
      pattern: options.reasoning.pattern
        ? { openTag: options.reasoning.pattern, closeTag: options.reasoning.pattern }
        : undefined,
    };
  }

  if (options?.structuredOutput) {
    partial.structuredOutput = {
      includeSchemaInPrompt: true,
      jsonSchema: options.structuredOutput.schema.json,
      strictMode: options.structuredOutput.strict ?? true,
      mode: StructuredOutputMode.STRUCTURED_OUTPUT_MODE_JSON_SCHEMA,
      repairJson: false,
      maxRetries: 0,
    };
  }

  if (options?.tools?.length || options?.toolChoice || options?.maxToolCalls !== undefined) {
    partial.toolCalling = {
      tools: options.tools ?? [],
      replaceSystemPrompt: false,
      keepToolsAvailable: true,
      toolChoice: toolChoiceMode(options.toolChoice),
      forcedToolName: options.toolChoice?.kind === 'forced' ? options.toolChoice.name : undefined,
      requireJsonArguments: false,
      maxToolCalls: options.maxToolCalls,
      autoExecute: true,
    };
  }

  return LLMGenerationOptionsMessage.fromPartial(partial);
}

const CHAT_ROLES: Record<ChatMessage['role'], MessageRole> = {
  system: MessageRole.MESSAGE_ROLE_SYSTEM,
  user: MessageRole.MESSAGE_ROLE_USER,
  assistant: MessageRole.MESSAGE_ROLE_ASSISTANT,
  tool: MessageRole.MESSAGE_ROLE_TOOL,
};

/** Convert a public chat transcript to the proto history list. */
export function toProtoHistory(messages: readonly ChatMessage[]): ProtoChatMessage[] {
  return messages.map((message) => ProtoChatMessageMessage.fromPartial({
    role: CHAT_ROLES[message.role],
    content: message.content,
    toolCallId: message.toolCallId,
  }));
}

function finishReasonFrom(raw: string | undefined, cancelled: boolean): FinishReason {
  if (cancelled) return 'cancelled';
  const value = (raw ?? '').toLowerCase();
  if (value.includes('tool')) return 'toolCalls';
  if (value.includes('length') || value.includes('max')) return 'length';
  if (value.includes('cancel')) return 'cancelled';
  return 'stop';
}

function metricsFrom(result: LLMGenerationResult, requestId: string): GenerationMetrics {
  return {
    inputTokens: result.usage?.inputTokens ?? 0,
    outputTokens: result.usage?.outputTokens ?? 0,
    timeToFirstTokenMs: Math.round(result.ttftMs ?? 0),
    tokensPerSecond: result.usage?.tokensPerSecond ?? 0,
    requestId,
    model: result.modelUsed,
  };
}

/** Convert a proto generation result to the public shape. */
export function toGenerationResult(
  result: LLMGenerationResult,
  requestId = '',
  cancelled = false,
): GenerationResult {
  return {
    ...metricsFrom(result, requestId),
    text: result.text,
    thinkingText: result.thinkingContent,
    toolCalls: result.toolCalls,
    finishReason: finishReasonFrom(result.finishReason, cancelled),
  };
}

/** Convert a streamed terminal result to the public shape. */
export function streamFinalToGenerationResult(
  final: LLMStreamFinalResult,
  requestId: string,
  model: string,
  fallback: { text: string; thinkingText: string; outputTokens: number; ttftMs: number; tokensPerSecond: number },
): GenerationResult {
  const outputTokens = (final.usage?.outputTokens ?? 0) || fallback.outputTokens;
  return {
    text: final.text || fallback.text,
    thinkingText: final.thinkingContent || fallback.thinkingText || undefined,
    toolCalls: final.toolCalls,
    finishReason: finishReasonFrom(final.finishReason, false),
    inputTokens: final.usage?.inputTokens ?? 0,
    outputTokens,
    timeToFirstTokenMs: Math.round(final.timeToFirstTokenMs || fallback.ttftMs),
    tokensPerSecond: (final.usage?.tokensPerSecond ?? 0) || fallback.tokensPerSecond,
    requestId,
    model,
  };
}

/** Convert a proto VLM result to the public generation shape. */
export function vlmToGenerationResult(result: VLMResult, requestId = ''): GenerationResult {
  return {
    text: result.text,
    thinkingText: undefined,
    toolCalls: [],
    finishReason: finishReasonFrom(result.finishReason, false),
    inputTokens: result.usage?.inputTokens ?? 0,
    outputTokens: result.usage?.outputTokens ?? 0,
    timeToFirstTokenMs: Math.round(result.timeToFirstTokenMs),
    tokensPerSecond: result.usage?.tokensPerSecond ?? 0,
    requestId,
    model: '',
  };
}

/** Convert a proto structured-output result to the public shape. */
export function toStructuredResult(
  parsed: StructuredOutputResult,
  generation: GenerationResult,
  parse?: (text: string) => unknown,
): StructuredResult {
  const raw = parsed.rawText ?? generation.text;
  const decoded = new TextDecoder().decode(parsed.parsedJson);
  let value: unknown;
  try {
    value = parse ? parse(raw) : JSON.parse(decoded || raw);
  } catch {
    value = undefined;
  }
  return {
    value,
    raw,
    valid: parsed.validation?.isValid ?? value !== undefined,
    inputTokens: generation.inputTokens,
    outputTokens: generation.outputTokens,
    timeToFirstTokenMs: generation.timeToFirstTokenMs,
    tokensPerSecond: generation.tokensPerSecond,
    requestId: generation.requestId,
    model: generation.model,
  };
}

/** Build the proto transcription options, filling gaps from the IDL defaults. */
export function toProtoSttOptions(options?: SttOptions): STTOptions {
  const defaults = optionDefaults.stt();
  return {
    ...defaults,
    language: options?.language,
    enablePunctuation: options?.punctuation ?? defaults.enablePunctuation,
    enableWordTimestamps: options?.wordTimestamps ?? defaults.enableWordTimestamps,
    enableDiarization: options?.diarization ?? defaults.enableDiarization,
    maxSpeakers: options?.maxSpeakers ?? defaults.maxSpeakers,
    translateToEnglish: options?.translateToEnglish ?? defaults.translateToEnglish,
  };
}

/** Convert a proto transcription to the public shape. */
export function toTranscription(output: STTOutput): Transcription {
  return {
    text: output.text,
    language: output.language,
    confidence: output.confidence,
    durationMs: output.durationMs,
    words: output.words.map((word) => ({
      text: word.word,
      startMs: word.startMs,
      endMs: word.endMs,
      confidence: word.confidence,
      speakerId: word.speakerId,
    })),
  };
}

const AUDIO_FORMATS: Record<NonNullable<TtsOptions['format']>, AudioFormat> = {
  pcm: AudioFormat.AUDIO_FORMAT_PCM,
  pcm16: AudioFormat.AUDIO_FORMAT_PCM_S16LE,
  wav: AudioFormat.AUDIO_FORMAT_WAV,
};

/** Build the proto synthesis options, filling gaps from the IDL defaults. */
export function toProtoTtsOptions(options?: TtsOptions): TTSOptions {
  const defaults = optionDefaults.tts();
  return {
    ...defaults,
    voice: options?.voice ?? defaults.voice,
    languageCode: options?.language ?? defaults.languageCode,
    speed: options?.speed ?? defaults.speed,
    pitch: options?.pitch ?? defaults.pitch,
    audioFormat: options?.format ? AUDIO_FORMATS[options.format] : defaults.audioFormat,
    sampleRate: options?.sampleRate ?? defaults.sampleRate,
  };
}

function audioFormatName(format: AudioFormat): Audio['format'] {
  if (format === AudioFormat.AUDIO_FORMAT_WAV) return 'wav';
  if (format === AudioFormat.AUDIO_FORMAT_PCM_S16LE) return 'pcm16';
  return 'pcm';
}

/** Convert a proto synthesis output to the public shape. */
export function toAudio(output: TTSOutput): Audio {
  return {
    data: output.audioData,
    sampleRate: output.sampleRate,
    format: audioFormatName(output.audioFormat),
    durationMs: output.durationMs,
  };
}

/** Convert a proto voice descriptor to the public shape. */
export function toVoice(info: TTSVoiceInfo): Voice {
  return {
    id: info.id,
    name: info.displayName,
    language: info.languageCode,
    isNeural: info.isNeural,
  };
}

/** Build the proto VAD options, filling gaps from the IDL defaults. */
export function toProtoVadOptions(options?: VadOptions): VADOptions {
  const defaults = optionDefaults.vad();
  return {
    ...defaults,
    activationThreshold: options?.activationThreshold ?? defaults.activationThreshold,
    minSpeechDurationMs: options?.minSpeechMs ?? defaults.minSpeechDurationMs,
    minSilenceDurationMs: options?.minSilenceMs ?? defaults.minSilenceDurationMs,
    prefixPaddingMs: options?.prefixPaddingMs ?? defaults.prefixPaddingMs,
  };
}

/** Convert a proto VAD verdict to the public shape. */
export function toVadResult(result: ProtoVadResult): VadResult {
  const hasSpan = result.endTimeMs > result.startTimeMs;
  return {
    isSpeech: result.isSpeech,
    probability: result.confidence,
    segments: result.isSpeech && hasSpan
      ? [{ startMs: result.startTimeMs, endMs: result.endTimeMs }]
      : [],
  };
}

const POOLING_MODES: Record<NonNullable<EmbedOptions['pooling']>, EmbeddingsPoolingStrategy> = {
  mean: EmbeddingsPoolingStrategy.EMBEDDINGS_POOLING_STRATEGY_MEAN,
  cls: EmbeddingsPoolingStrategy.EMBEDDINGS_POOLING_STRATEGY_CLS,
  max: EmbeddingsPoolingStrategy.EMBEDDINGS_POOLING_STRATEGY_LAST,
};

/** Build the proto embedding options, filling gaps from the IDL defaults. */
export function toProtoEmbedOptions(options?: EmbedOptions): EmbeddingsOptions {
  const defaults = optionDefaults.embed();
  return {
    ...defaults,
    normalize: options?.normalize ? options.normalize === 'l2' : true,
    pooling: options?.pooling
      ? POOLING_MODES[options.pooling]
      : EmbeddingsPoolingStrategy.EMBEDDINGS_POOLING_STRATEGY_MEAN,
  };
}

/** Convert a proto embeddings batch to the public per-input list. */
export function toEmbeddings(result: EmbeddingsResult): Embedding[] {
  return result.vectors.map((vector, index) => ({
    index,
    vector: Float32Array.from(vector.values),
  }));
}

/** Build the proto diffusion options, filling gaps from the IDL defaults. */
export function toProtoImageOptions(
  prompt: string,
  options?: ImageOptions,
): Partial<DiffusionGenerationOptions> {
  const defaults = optionDefaults.image();
  const inpaint = options?.mode?.kind === 'inpaint' ? options.mode : null;
  return {
    prompt,
    negativePrompt: options?.negativePrompt ?? defaults.negativePrompt,
    width: options?.width ?? defaults.width,
    height: options?.height ?? defaults.height,
    steps: options?.steps ?? defaults.steps,
    guidanceScale: options?.guidanceScale ?? defaults.guidanceScale,
    seed: options?.seed ?? defaults.seed,
    mode: inpaint ? DiffusionMode.DIFFUSION_MODE_INPAINTING : DiffusionMode.DIFFUSION_MODE_TEXT_TO_IMAGE,
    inputImage: inpaint?.input,
    maskImage: inpaint?.mask,
    reportIntermediateImages: options?.reportPartials ?? defaults.reportIntermediateImages,
  };
}

/**
 * Convert a proto diffusion result to the public shape. The proto carries no
 * step count, so the requested `steps` is threaded back in by the caller.
 */
export function toImageResult(result: DiffusionResult, steps: number): ImageResult {
  const extra = result.batchImages.map((bytes) => ({
    bytes,
    width: result.width,
    height: result.height,
  }));
  return {
    images: [{ bytes: result.imageData, width: result.width, height: result.height }, ...extra],
    seed: result.seedUsed,
    steps,
  };
}

/** Build the proto diarization options, filling gaps from the IDL defaults. */
export function toProtoDiarizationOptions(options?: DiarizationOptions): ProtoDiarizationOptions {
  const defaults = optionDefaults.diarization();
  return {
    ...defaults,
    threshold: options?.threshold ?? defaults.threshold,
    minimumDurationMs: options?.minimumDurationMs ?? defaults.minimumDurationMs,
    mergeGapMs: options?.mergeGapMs ?? defaults.mergeGapMs,
  };
}

/** Convert a proto diarization result to the public shape. */
export function toDiarizationResult(result: ProtoDiarizationResult): DiarizationResult {
  return {
    speakerCount: result.speakerCount,
    segments: result.segments.map((segment) => ({
      speakerId: segment.speakerId || String(segment.speakerIndex),
      startMs: segment.startMs,
      endMs: segment.endMs,
    })),
  };
}

/** Convert a proto segmentation result to the public shape. */
export function toSegmentationResult(result: ProtoSegmentationResult): SegmentationResult {
  return {
    classMask: result.classMaskU16Le,
    width: result.width,
    height: result.height,
    diagnosticImage: result.diagnosticRgba,
    classes: result.classSummaries.map((summary) => ({
      id: summary.classId,
      label: summary.label,
      pixelCount: summary.pixelCount,
      fraction: summary.fraction,
    })),
  };
}

/** Convert a proto rerank result to the public index-pointer list. */
export function toRankedResults(result: RerankResult): RankedResult[] {
  return result.items
    .map((item) => ({ index: item.index, relevanceScore: item.relevanceScore }))
    .sort((a, b) => b.relevanceScore - a.relevanceScore);
}

/** Convert a proto RAG chunk to the public match shape. */
export function toMatch(chunk: RAGSearchResult): Match {
  return {
    text: chunk.text,
    score: chunk.similarityScore,
    metadata: chunk.metadata ?? {},
  };
}

/** Convert a proto RAG result to the public shape. */
export function toRagResult(result: RAGResult): RagResult {
  const totalMs = result.generationTimeMs || result.totalTimeMs;
  return {
    answer: result.answer,
    sources: result.retrievedChunks.map(toMatch),
    inputTokens: result.usage?.inputTokens ?? 0,
    outputTokens: result.usage?.outputTokens ?? 0,
    timeToFirstTokenMs: 0,
    tokensPerSecond: totalMs > 0 ? ((result.usage?.outputTokens ?? 0) / totalMs) * 1000 : 0,
    requestId: result.requestId ?? '',
    model: '',
  };
}

/** Convert proto RAG statistics to the public shape. */
export function toRagStats(statistics: RAGStatistics): RagStats {
  return {
    documentCount: statistics.indexedDocuments,
    chunkCount: statistics.indexedChunks,
    indexSizeBytes: statistics.totalTokensIndexed,
  };
}

/** Convert a proto LoRA state to the public shape. */
export function toLoraState(state: LoRAState): LoraState {
  return {
    applied: state.loadedAdapters
      .filter((adapter) => adapter.applied)
      .map((adapter) => ({ id: adapter.adapterId, scale: adapter.scale })),
  };
}

export type { ModelCategory };
