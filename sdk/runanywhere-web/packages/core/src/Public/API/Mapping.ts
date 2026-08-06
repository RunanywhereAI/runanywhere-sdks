/**
 * Translation between the v4 public option/result shapes and the generated
 * proto messages the C++ core speaks. Internal — never exported from the
 * package root.
 */

import { AudioFormat, InferenceFramework, type ModelCategory } from '@runanywhere/proto-ts/model_types';
import {
  FinishReason as ProtoFinishReason,
  LLMGenerationOptions as LLMGenerationOptionsMessage,
  type LLMGenerationOptions,
  type LLMGenerationResult,
} from '@runanywhere/proto-ts/llm_options';
import { ReasoningMode } from '@runanywhere/proto-ts/thinking_tag_pattern';
import { ToolChoiceMode } from '@runanywhere/proto-ts/tool_calling';
import type { StructuredOutputOptions, StructuredOutputResult } from '@runanywhere/proto-ts/structured_output';
import type { STTOptions, STTOutput } from '@runanywhere/proto-ts/stt_options';
import type { TTSOptions, TTSOutput, TTSVoiceInfo } from '@runanywhere/proto-ts/tts_options';
import type { VADOptions, VADResult as ProtoVadResult } from '@runanywhere/proto-ts/vad_options';
import {
  EmbeddingsPoolingStrategy,
  type EmbeddingsOptions,
  type EmbeddingsResult,
} from '@runanywhere/proto-ts/embeddings_options';
import type {
  DiffusionGenerationOptions,
  DiffusionResult,
} from '@runanywhere/proto-ts/diffusion_options';
import type { DiarizationOptions as ProtoDiarizationOptions, DiarizationResult as ProtoDiarizationResult } from '@runanywhere/proto-ts/diarization';
import type { SegmentationResult as ProtoSegmentationResult } from '@runanywhere/proto-ts/segmentation';
import type { RerankResult } from '@runanywhere/proto-ts/rerank';
import type { RAGResult, RAGSearchResult, RAGStatistics } from '@runanywhere/proto-ts/rag';
import type { VLMResult } from '@runanywhere/proto-ts/vlm_options';
import type { LoraState as ProtoLoraState } from '@runanywhere/proto-ts/lora_options';
import { Runtime } from '../../Foundation/RuntimeConfig.js';
import type {
  Backend,
  DiarizationOptions,
  EmbedOptions,
  ImageOptions,
  LlmOptions,
  StructuredOutputMode,
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

/** Map the cross-SDK `Backend` name back to the proto `InferenceFramework` it selects. */
const BACKEND_TO_FRAMEWORK: Record<Backend, InferenceFramework> = {
  onnx: InferenceFramework.INFERENCE_FRAMEWORK_ONNX,
  llamaCpp: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
  mlx: InferenceFramework.INFERENCE_FRAMEWORK_MLX,
  coreml: InferenceFramework.INFERENCE_FRAMEWORK_COREML,
  foundationModels: InferenceFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS,
  sherpa: InferenceFramework.INFERENCE_FRAMEWORK_SHERPA,
  qhexrt: InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
  systemTts: InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS,
  builtIn: InferenceFramework.INFERENCE_FRAMEWORK_BUILT_IN,
  unknown: InferenceFramework.INFERENCE_FRAMEWORK_UNKNOWN,
};

/** Map a proto `InferenceFramework` to the cross-SDK `Backend` name it represents. */
export function frameworkToBackend(framework?: InferenceFramework | null): Backend {
  switch (framework) {
    case InferenceFramework.INFERENCE_FRAMEWORK_ONNX: return 'onnx';
    case InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP: return 'llamaCpp';
    case InferenceFramework.INFERENCE_FRAMEWORK_MLX: return 'mlx';
    case InferenceFramework.INFERENCE_FRAMEWORK_COREML: return 'coreml';
    case InferenceFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS: return 'foundationModels';
    case InferenceFramework.INFERENCE_FRAMEWORK_SHERPA: return 'sherpa';
    case InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT: return 'qhexrt';
    case InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS: return 'systemTts';
    case InferenceFramework.INFERENCE_FRAMEWORK_BUILT_IN: return 'builtIn';
    default: return 'unknown';
  }
}

/** Map the cross-SDK `Backend` name to the proto `InferenceFramework` it selects. */
export function backendToFramework(backend: Backend): InferenceFramework {
  return BACKEND_TO_FRAMEWORK[backend] ?? InferenceFramework.INFERENCE_FRAMEWORK_UNKNOWN;
}

/**
 * Honest device placement for the currently active runtime. Web only ever
 * resolves to `'cpu'` or `'gpu'` (WebGPU) — there is no NPU/ANE access from
 * the browser.
 */
export function currentDevicePlacement(): string {
  return Runtime.active === 'webgpu' ? 'gpu' : 'cpu';
}

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
    repeatPenalty: options?.repetitionPenalty ?? defaults.repeatPenalty,
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

  if (options?.tools?.length || options?.toolChoice || options?.maxToolCalls !== undefined) {
    partial.toolCalling = {
      tools: options.tools ?? [],
      replaceSystemPrompt: false,
      keepToolsAvailable: true,
      toolChoice: toolChoiceMode(options.toolChoice),
      forcedToolName: options.toolChoice?.kind === 'forced' ? options.toolChoice.name : undefined,
      requireJsonArguments: false,
      maxToolCalls: options.maxToolCalls,
      // Forwarded verbatim -- generateWithToolLoop hands this straight to
      // toolCalling.generateWithTools as its autoExecute override, so an
      // explicit caller `autoExecute: false` must survive this hop instead
      // of being hardcoded away.
      autoExecute: options.autoExecute ?? true,
      parallelToolCalls: false,
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

/**
 * Map the proto `FinishReason` enum to the public string union. `finishReason`
 * is a typed enum now, not a raw string to substring-match against.
 */
function finishReasonFrom(reason: ProtoFinishReason, cancelled: boolean): FinishReason {
  if (cancelled) return 'cancelled';
  switch (reason) {
    case ProtoFinishReason.FINISH_REASON_STOP:
    case ProtoFinishReason.FINISH_REASON_STOP_SEQUENCE:
      return 'stop';
    case ProtoFinishReason.FINISH_REASON_LENGTH:
    case ProtoFinishReason.FINISH_REASON_CONTEXT_OVERFLOW:
      return 'length';
    case ProtoFinishReason.FINISH_REASON_TOOL_CALLS:
      return 'toolCalls';
    case ProtoFinishReason.FINISH_REASON_CANCELLED:
      return 'cancelled';
    case ProtoFinishReason.FINISH_REASON_ERROR:
      return 'unknown';
    default:
      return 'unknown';
  }
}

/**
 * Map a raw finish-reason string (VLMResult.finishReason, which stayed a
 * plain string on the wire) to the public union.
 */
function finishReasonFromString(raw: string | undefined, cancelled: boolean): FinishReason {
  if (cancelled) return 'cancelled';
  const value = (raw ?? '').toLowerCase();
  if (!value) return 'stop';
  if (value.includes('tool')) return 'toolCalls';
  if (value.includes('length') || value.includes('max')) return 'length';
  if (value.includes('cancel')) return 'cancelled';
  if (value.includes('filter') || value.includes('safety')) return 'contentFilter';
  if (value.includes('stop') || value.includes('eos') || value.includes('end')) return 'stop';
  return 'unknown';
}

function metricsFrom(result: LLMGenerationResult, requestId: string): GenerationMetrics {
  return {
    inputTokens: result.usage?.inputTokens ?? 0,
    outputTokens: result.usage?.outputTokens ?? 0,
    timeToFirstTokenMs: Math.round(result.usage?.ttftMs ?? 0),
    tokensPerSecond: result.usage?.decodeTokensPerSecond ?? 0,
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
    rawFinishReason: result.finishReason ? String(result.finishReason) : undefined,
    actualDevice: currentDevicePlacement(),
  };
}

/**
 * Convert a streamed terminal result to the public shape. `LLMStreamEvent`
 * carries its terminal payload directly on `.result: LLMGenerationResult`
 * now — the standalone `LLMStreamFinalResult` message was deleted outright.
 */
export function streamFinalToGenerationResult(
  final: LLMGenerationResult,
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
    rawFinishReason: final.finishReason ? String(final.finishReason) : undefined,
    inputTokens: final.usage?.inputTokens ?? 0,
    outputTokens,
    timeToFirstTokenMs: Math.round((final.usage?.ttftMs ?? 0) || fallback.ttftMs),
    tokensPerSecond: (final.usage?.decodeTokensPerSecond ?? 0) || fallback.tokensPerSecond,
    requestId,
    model,
    actualDevice: currentDevicePlacement(),
  };
}

/** Convert a proto VLM result to the public generation shape. */
export function vlmToGenerationResult(result: VLMResult, requestId = ''): GenerationResult {
  return {
    text: result.text,
    thinkingText: undefined,
    toolCalls: [],
    finishReason: finishReasonFromString(result.finishReason, false),
    rawFinishReason: result.finishReason || undefined,
    inputTokens: result.usage?.inputTokens ?? 0,
    outputTokens: result.usage?.outputTokens ?? 0,
    timeToFirstTokenMs: Math.round(result.usage?.ttftMs ?? 0),
    tokensPerSecond: result.usage?.decodeTokensPerSecond ?? 0,
    requestId,
    model: '',
    actualDevice: currentDevicePlacement(),
  };
}

/**
 * Build the proto structured-output request options for one
 * `llm.generateStructured` call. `CONSTRAINED` is not wired on Web (no
 * grammar-constrained decoding hook) — callers must preflight-reject it
 * before reaching this helper. `StructuredOutputOptions` no longer carries a
 * `mode`/`strictMode`/`repairJson` knob: it is just
 * `includeSchemaInPrompt`/`schema`/`grammar`/`regex` now, so `mode` is kept
 * only as the caller-facing enforcement level threaded through to
 * `toStructuredResult` — commons always validates+extracts on the result.
 */
export function toProtoStructuredOutputOptions(
  json: string,
  _mode: Exclude<StructuredOutputMode, 'constrained'>,
): StructuredOutputOptions {
  return {
    includeSchemaInPrompt: true,
    schema: json,
  };
}

/** Convert a proto structured-output result to the public shape. */
export function toStructuredResult(
  parsed: StructuredOutputResult,
  generation: GenerationResult,
  mode: StructuredOutputMode,
  parse?: (text: string) => unknown,
): StructuredResult {
  const raw = parsed.rawText ?? generation.text;
  let value: unknown;
  try {
    value = parse ? parse(raw) : JSON.parse(parsed.json || raw);
  } catch {
    value = undefined;
  }
  return {
    value,
    raw,
    valid: parsed.validation?.isValid ?? value !== undefined,
    mode,
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
    diarize: options?.diarization ?? defaults.diarize,
    speakersExpected: options?.maxSpeakers ?? defaults.speakersExpected,
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

/**
 * Convert a proto VAD verdict to the public shape. `VADResult` (a one-shot
 * detect() response) carries no span info -- no `startTimeMs`/`endTimeMs`
 * ever existed on this message; span data lives on the streaming
 * `SpeechActivityEvent` instead. `segments` is therefore always empty here.
 */
export function toVadResult(result: ProtoVadResult): VadResult {
  return {
    isSpeech: result.isSpeech,
    probability: result.probability,
    segments: [],
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

/**
 * Build the proto diffusion options, filling gaps from the IDL defaults.
 * `DiffusionMode`/`reportIntermediateImages` were deleted outright: adding
 * `maskImage` on top of `image` promotes a request to inpainting (there is
 * no explicit mode enum any more), and progress/intermediate images ride
 * the streaming `DiffusionStreamEvent.progress` arm instead of a request flag.
 */
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
    image: inpaint?.input,
    maskImage: inpaint?.mask,
  };
}

/**
 * Convert a proto diffusion result to the public shape. The proto carries no
 * step count, so the requested `steps` is threaded back in by the caller.
 * `DiffusionResult.images` is now a list of `DiffusionImage` (data/width/
 * height/seedUsed/mediaType each), not a single imageData+batchImages pair.
 */
export function toImageResult(result: DiffusionResult, steps: number): ImageResult {
  const [first, ...rest] = result.images;
  return {
    images: (first ? [first, ...rest] : []).map((image) => ({
      bytes: image.data,
      width: image.width,
      height: image.height,
    })),
    seed: first?.seedUsed ?? 0,
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
  const totalPixels = result.width * result.height;
  return {
    classMask: result.classMaskU16Le,
    width: result.width,
    height: result.height,
    diagnosticImage: result.diagnosticRgba,
    classes: result.classSummaries.map((summary) => ({
      id: summary.classId,
      label: summary.label,
      pixelCount: summary.pixelCount,
      fraction: totalPixels > 0 ? summary.pixelCount / totalPixels : 0,
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
    score: chunk.score,
    metadata: chunk.metadata ?? {},
  };
}

/** Convert a proto RAG result to the public shape. */
export function toRagResult(result: RAGResult): RagResult {
  const totalMs = result.retrievalTimeMs + result.generationTimeMs;
  return {
    answer: result.answer,
    sources: result.retrievedChunks.map(toMatch),
    inputTokens: result.usage?.inputTokens ?? 0,
    outputTokens: result.usage?.outputTokens ?? 0,
    timeToFirstTokenMs: Math.round(result.usage?.ttftMs ?? 0),
    tokensPerSecond: result.usage?.decodeTokensPerSecond
      ?? (totalMs > 0 ? ((result.usage?.outputTokens ?? 0) / totalMs) * 1000 : 0),
    requestId: result.requestId ?? '',
    model: '',
  };
}

/** Convert proto RAG statistics to the public shape. */
export function toRagStats(statistics: RAGStatistics): RagStats {
  return {
    documentCount: statistics.indexedDocuments,
    chunkCount: statistics.indexedChunks,
    indexSizeBytes: statistics.vectorStoreSizeBytes,
  };
}

/** Convert a proto LoRA state to the public shape. */
export function toLoraState(state: ProtoLoraState): LoraState {
  return {
    applied: state.loadedAdapters
      .filter((adapter) => adapter.applied)
      .map((adapter) => ({ id: adapter.adapterId, scale: adapter.scale })),
  };
}

export type { ModelCategory };
