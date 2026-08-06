// options.ts — the v3 option objects, their spec defaults, and the mapping onto
// the addon's N-API keys.
//
// Public names follow the spec; the addon's own wire names are older in places
// (`maxTokens` for maxOutputTokens, `speed` -> rac `rate`), so every rename is
// resolved here and nowhere else.

import type {
  AudioFormat,
  ImageMode,
  InferenceFramework,
  NormalizeMode,
  PoolingMode,
  ReasoningMode,
  ToolChoice,
  ToolDefinition,
} from './types';
import type { JsonSchema } from '../grammar';

// ---------------------------------------------------------------------------
// Option objects
// ---------------------------------------------------------------------------

/** Whether and how the model reasons before answering. */
export interface ReasoningOptions {
  /** OFF suppresses thinking entirely. Default ON. */
  mode?: ReasoningMode;
  /** Stream thought tokens to the caller. Default false. */
  includeInOutput?: boolean;
  /** Tag pair to treat as thinking; null uses the model's own. */
  pattern?: string;
}

/** A schema the output must satisfy. */
export interface StructuredOutput {
  schema: JsonSchema;
  /** Constrain decoding so the output cannot violate the schema. Default true. */
  strict?: boolean;
}

/** Per-request generation controls shared by llm and vlm. */
export interface LlmOptions {
  /** Model slug; an absent model auto-loads, downloading if needed. */
  model?: string;
  maxOutputTokens?: number;
  temperature?: number;
  topP?: number;
  topK?: number;
  minP?: number;
  frequencyPenalty?: number;
  presencePenalty?: number;
  repetitionPenalty?: number;
  seed?: number;
  stopSequences?: string[];
  systemPrompt?: string;
  reasoning?: ReasoningOptions;
  structuredOutput?: StructuredOutput;
  /** Tools for this request only; empty uses the registry. */
  tools?: ToolDefinition[];
  toolChoice?: ToolChoice;
  maxToolCalls?: number;
}

/** Transcription controls. */
export interface SttOptions {
  /** BCP-47 tag; absent auto-detects. */
  language?: string;
  punctuation?: boolean;
  wordTimestamps?: boolean;
  diarization?: boolean;
  maxSpeakers?: number;
  translateToEnglish?: boolean;
}

/** Synthesis controls. */
export interface TtsOptions {
  voice?: string;
  language?: string;
  speed?: number;
  pitch?: number;
  format?: AudioFormat;
  sampleRate?: number;
}

/** Voice-activity detection controls. */
export interface VadOptions {
  /** Absent uses the model's calibrated default. */
  activationThreshold?: number;
  minSpeechMs?: number;
  minSilenceMs?: number;
  prefixPaddingMs?: number;
}

/** Embedding controls. */
export interface EmbedOptions {
  normalize?: NormalizeMode;
  pooling?: PoolingMode;
}

/** Image generation controls. */
export interface ImageOptions {
  negativePrompt?: string;
  width?: number;
  height?: number;
  steps?: number;
  guidanceScale?: number;
  seed?: number;
  mode?: ImageMode;
  /** Source image for INPAINT mode. */
  input?: Uint8Array;
  /** Mask marking the region to repaint, for INPAINT mode. */
  mask?: Uint8Array;
  reportPartials?: boolean;
}

/** Diarization controls. */
export interface DiarizationOptions {
  threshold?: number;
  minimumDurationMs?: number;
  mergeGapMs?: number;
}

/** Segmentation controls. */
export interface SegmentationOptions {
  includeDiagnosticImage?: boolean;
}

/** When the agent decides the user has finished speaking. */
export interface Endpointing {
  minDelayMs?: number;
  maxDelayMs?: number;
}

/** Whether the user can cut the agent off mid-utterance. */
export interface Interruption {
  enabled?: boolean;
  minDurationMs?: number;
}

/** Turn-taking controls for a voice session. */
export interface TurnHandlingOptions {
  endpointing?: Endpointing;
  interruption?: Interruption;
}

/** Retrieval and chunking controls for a RAG session. */
export interface RagConfig {
  topK?: number;
  chunkSize?: number;
  chunkOverlap?: number;
  scoreThreshold?: number;
}

/** Placement controls applied when a model loads. */
export interface LoadOptions {
  /** Engine pin, load time only. */
  framework?: InferenceFramework;
  contextLength?: number;
  threads?: number;
  useGpu?: boolean;
}

// ---------------------------------------------------------------------------
// Defaults — one table, shared by both surfaces
// ---------------------------------------------------------------------------

/**
 * Defaults for {@link LlmOptions}. The sampling numbers come from the
 * `rac_default` annotations on `LLMGenerationOptions` in `idl/llm_options.proto`
 * (512 / 0.7 / 1.0), which is the cross-SDK source of truth. ts-proto emits
 * proto3 zeros rather than those annotations, so they are transcribed here.
 */
export const LLM_DEFAULTS = {
  maxOutputTokens: 512,
  temperature: 0.7,
  topP: 1.0,
  stopSequences: [] as string[],
  toolChoice: 'AUTO' as ToolChoice,
  maxToolCalls: 5,
} as const;

/** Spec defaults for {@link ReasoningOptions}. */
export const REASONING_DEFAULTS = { mode: 'ON', includeInOutput: false } as const;

/** Spec defaults for {@link SttOptions}. */
export const STT_DEFAULTS = {
  punctuation: true,
  wordTimestamps: true,
  diarization: false,
  translateToEnglish: false,
} as const;

/** Spec defaults for {@link TtsOptions}. */
export const TTS_DEFAULTS = {
  language: 'en-US',
  speed: 1.0,
  pitch: 1.0,
  format: 'PCM' as AudioFormat,
  sampleRate: 22050,
} as const;

/** Spec defaults for {@link VadOptions}. */
export const VAD_DEFAULTS = {
  minSpeechMs: 100,
  minSilenceMs: 300,
  prefixPaddingMs: 0,
} as const;

/** Spec defaults for {@link EmbedOptions}. */
export const EMBED_DEFAULTS = {
  normalize: 'L2' as NormalizeMode,
  pooling: 'MEAN' as PoolingMode,
} as const;

/** Spec defaults for {@link ImageOptions}. */
export const IMAGE_DEFAULTS = { mode: 'GENERATE' as ImageMode, reportPartials: false } as const;

/** Spec defaults for {@link SegmentationOptions}. */
export const SEGMENTATION_DEFAULTS = { includeDiagnosticImage: false } as const;

/** Spec defaults for {@link TurnHandlingOptions}. */
export const TURN_DEFAULTS = {
  endpointing: { minDelayMs: 500, maxDelayMs: 3000 },
  interruption: { enabled: true, minDurationMs: 500 },
} as const;

/** Spec defaults for {@link RagConfig}. */
export const RAG_DEFAULTS = { topK: 5, chunkSize: 512, chunkOverlap: 64 } as const;

// ---------------------------------------------------------------------------
// Native mapping
// ---------------------------------------------------------------------------

/** Generation options in the addon's own key spelling. */
export interface NativeGenerateOptions {
  maxTokens?: number;
  temperature?: number;
  topP?: number;
  topK?: number;
  minP?: number;
  frequencyPenalty?: number;
  presencePenalty?: number;
  repetitionPenalty?: number;
  seed?: number;
  nThreads?: number;
  disableThinking?: boolean;
  systemPrompt?: string;
  grammar?: string;
  stopSequences?: string[];
  /** Alternating user/assistant turns, excluding the system prompt and the current prompt. */
  history?: string[];
}

/**
 * Map {@link LlmOptions} onto the addon's keys, applying spec defaults. `grammar`
 * and `history` are computed by the caller (structured output, chat messages) and
 * merged in rather than being public option fields.
 */
export function toNativeGenerateOptions(
  o: LlmOptions = {},
  extra: { grammar?: string; history?: string[] } = {}
): NativeGenerateOptions {
  const native: NativeGenerateOptions = {
    maxTokens: o.maxOutputTokens ?? LLM_DEFAULTS.maxOutputTokens,
    temperature: o.temperature ?? LLM_DEFAULTS.temperature,
    topP: o.topP ?? LLM_DEFAULTS.topP,
  };
  if (o.topK !== undefined) native.topK = o.topK;
  if (o.minP !== undefined) native.minP = o.minP;
  if (o.frequencyPenalty !== undefined) native.frequencyPenalty = o.frequencyPenalty;
  if (o.presencePenalty !== undefined) native.presencePenalty = o.presencePenalty;
  if (o.repetitionPenalty !== undefined) native.repetitionPenalty = o.repetitionPenalty;
  if (o.seed !== undefined) native.seed = o.seed;
  if (o.systemPrompt !== undefined) native.systemPrompt = o.systemPrompt;
  const stops = o.stopSequences ?? LLM_DEFAULTS.stopSequences;
  if (stops.length) native.stopSequences = [...stops];
  if (o.reasoning?.mode === 'OFF') native.disableThinking = true;
  if (extra.grammar) native.grammar = extra.grammar;
  if (extra.history && extra.history.length) native.history = [...extra.history];
  return native;
}

/** STT options in the addon's own key spelling. */
export interface NativeSttOptions {
  language?: string;
  detectLanguage?: boolean;
  punctuation?: boolean;
  wordTimestamps?: boolean;
  diarization?: boolean;
  maxSpeakers?: number;
  sampleRate?: number;
}

/** Map {@link SttOptions} onto the addon's keys, applying spec defaults. */
export function toNativeSttOptions(o: SttOptions = {}, sampleRate?: number): NativeSttOptions {
  const native: NativeSttOptions = {
    punctuation: o.punctuation ?? STT_DEFAULTS.punctuation,
    wordTimestamps: o.wordTimestamps ?? STT_DEFAULTS.wordTimestamps,
    diarization: o.diarization ?? STT_DEFAULTS.diarization,
  };
  if (o.language !== undefined) native.language = o.language;
  else native.detectLanguage = true;
  if (o.maxSpeakers !== undefined) native.maxSpeakers = o.maxSpeakers;
  if (sampleRate) native.sampleRate = sampleRate;
  return native;
}

// rac_audio_format_enum_t ordinals (rac_stt_types.h). The addon takes the int.
const AUDIO_FORMAT_ORDINAL: Record<string, number> = {
  PCM: 0,
  WAV: 1,
  MP3: 2,
  OPUS: 3,
  AAC: 4,
  FLAC: 5,
};

/** Decode a rac_audio_format_enum_t ordinal back to the public name. */
export function audioFormatFromOrdinal(n: number): AudioFormat {
  const found = Object.entries(AUDIO_FORMAT_ORDINAL).find(([, v]) => v === n);
  return (found ? found[0] : 'PCM') as AudioFormat;
}

/** TTS options in the addon's own key spelling. */
export interface NativeTtsOptions {
  voice?: string;
  language?: string;
  speed?: number;
  pitch?: number;
  audioFormat?: number;
  sampleRate?: number;
}

/** Map {@link TtsOptions} onto the addon's keys, applying spec defaults. */
export function toNativeTtsOptions(o: TtsOptions = {}): NativeTtsOptions {
  const native: NativeTtsOptions = {
    language: o.language ?? TTS_DEFAULTS.language,
    speed: o.speed ?? TTS_DEFAULTS.speed,
    pitch: o.pitch ?? TTS_DEFAULTS.pitch,
    audioFormat: AUDIO_FORMAT_ORDINAL[o.format ?? TTS_DEFAULTS.format] ?? 0,
    sampleRate: o.sampleRate ?? TTS_DEFAULTS.sampleRate,
  };
  if (o.voice !== undefined) native.voice = o.voice;
  return native;
}

// rac_embeddings_{normalize,pooling}_t ordinals (rac_embeddings_types.h).
const NORMALIZE_ORDINAL: Record<NormalizeMode, number> = { NONE: 0, L2: 1 };
const POOLING_ORDINAL: Record<PoolingMode, number> = { MEAN: 0, CLS: 1, LAST: 2 };

/** Embedding options in the addon's own key spelling. */
export interface NativeEmbedOptions {
  normalize?: number;
  pooling?: number;
}

/** Map {@link EmbedOptions} onto the addon's keys, applying spec defaults. */
export function toNativeEmbedOptions(o: EmbedOptions = {}): NativeEmbedOptions {
  return {
    normalize: NORMALIZE_ORDINAL[o.normalize ?? EMBED_DEFAULTS.normalize],
    pooling: POOLING_ORDINAL[o.pooling ?? EMBED_DEFAULTS.pooling],
  };
}

/** VAD config in the addon's own key spelling. */
export interface NativeVadConfig {
  activationThreshold?: number;
  sampleRate?: number;
  frameLength?: number;
  modelPath?: string;
}

/** Map {@link VadOptions} onto the addon's createVad config. */
export function toNativeVadConfig(
  o: VadOptions = {},
  extra: { sampleRate?: number; modelPath?: string } = {}
): NativeVadConfig {
  const native: NativeVadConfig = {};
  if (o.activationThreshold !== undefined) native.activationThreshold = o.activationThreshold;
  if (extra.sampleRate) native.sampleRate = extra.sampleRate;
  if (extra.modelPath) native.modelPath = extra.modelPath;
  return native;
}

/** Diarization options in the addon's own key spelling. */
export interface NativeDiarizationOptions {
  threshold?: number;
  minimumDurationMs?: number;
  mergeGapMs?: number;
  sampleRate?: number;
}

/** Map {@link DiarizationOptions} onto the addon's keys. */
export function toNativeDiarizationOptions(
  o: DiarizationOptions = {},
  sampleRate?: number
): NativeDiarizationOptions {
  const native: NativeDiarizationOptions = {};
  if (o.threshold !== undefined) native.threshold = o.threshold;
  if (o.minimumDurationMs !== undefined) native.minimumDurationMs = o.minimumDurationMs;
  if (o.mergeGapMs !== undefined) native.mergeGapMs = o.mergeGapMs;
  if (sampleRate) native.sampleRate = sampleRate;
  return native;
}
