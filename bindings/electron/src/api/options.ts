// options.ts — the v3 option objects, their spec defaults, and the mapping onto
// the addon's N-API keys.
//
// Public names follow the spec; the addon's own wire names are older in places
// (`maxTokens` for maxOutputTokens, `speed` -> rac `rate`), so every rename is
// resolved here and nowhere else.

import { AudioFormat as ProtoAudioFormat } from '@runanywhere/proto-ts/model_types';
import { diarizationOptionsDefaults } from '@runanywhere/proto-ts/convenience/diarization_convenience';
import { diffusionGenerationOptionsDefaults } from '@runanywhere/proto-ts/convenience/diffusion_options_convenience';
import { embeddingsOptionsDefaults } from '@runanywhere/proto-ts/convenience/embeddings_options_convenience';
import { lLMGenerationOptionsDefaults } from '@runanywhere/proto-ts/convenience/llm_options_convenience';
import { rAGConfigurationDefaults } from '@runanywhere/proto-ts/convenience/rag_convenience';
import { sTTOptionsDefaults } from '@runanywhere/proto-ts/convenience/stt_options_convenience';
import { tTSOptionsDefaults } from '@runanywhere/proto-ts/convenience/tts_options_convenience';
import { vADOptionsDefaults } from '@runanywhere/proto-ts/convenience/vad_options_convenience';
import { audioCaptureDefaults, storageDefaults } from '@runanywhere/proto-ts/defaults/pool';
// `AudioFormat`, `ReasoningMode`, and `ToolChoice` are each a const object plus a
// type of the same name, so one value import supplies both.
import { AudioFormat, ReasoningMode, ToolChoice } from './types';
import type {
  ImageMode,
  InferenceFramework,
  JsonSchema,
  ModelCategory,
  NormalizeMode,
  PoolingMode,
  ToolDefinition,
} from './types';

// ---------------------------------------------------------------------------
// Option objects
// ---------------------------------------------------------------------------

/** Whether and how the model reasons before answering. */
export interface ReasoningOptions {
  /** OFF suppresses thinking entirely. Default ON. */
  mode?: ReasoningMode;
  /** Stream thought tokens to the caller. Default false. */
  includeInOutput?: boolean;
  /** Tag pair to treat as thinking; absent uses the model's own. */
  pattern?: ThinkingPattern;
}

/** The markers wrapping a model's reasoning, for families whose tags differ. */
export interface ThinkingPattern {
  open: string;
  close: string;
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
  /** Let one model turn request several tools before the follow-up turn. */
  parallelToolCalls?: boolean;
  /**
   * Check a call against the registry and its schema before running it.
   * Commons defaults this on; turn it off when the executor itself decides
   * what is callable (a dynamic registry, an authorization check).
   */
  validateCalls?: boolean;
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
  /**
   * Minimum similarity a chunk needs to be retrieved. Carried to commons as
   * `RAGConfiguration.score_threshold`; the public name follows the spec and
   * Swift, which do not leak the wire rename.
   */
  similarityThreshold?: number;
  /**
   * Where to persist the index. Declared for cross-SDK parity and not yet
   * honoured: `idl/rag.proto` has no persist field, so commons cannot receive
   * it. Swift declares it and drops it the same way.
   */
  persistPath?: string;
}

/** Placement controls applied when a model loads. */
export interface LoadOptions {
  /** Engine pin, load time only. */
  framework?: InferenceFramework;
  contextLength?: number;
  threads?: number;
  useGpu?: boolean;
  /**
   * Categories that must survive this load when memory is short. A voice turn
   * passes `['SPEECH_TO_TEXT', 'TEXT_TO_SPEECH']` so answering out loud does not
   * evict the microphone. The category being loaded is always kept.
   */
  keepResident?: ModelCategory[];
}

// ---------------------------------------------------------------------------
// Defaults — read from the IDL, never restated
// ---------------------------------------------------------------------------
//
// Every default the SDK needs client-side comes from the generated
// `@runanywhere/proto-ts/convenience/*` helpers, which are produced from the
// `(runanywhere.v1.rac_default)` annotations in `idl/`, or from the central
// `defaults/pool`. Nothing here transcribes a literal. This mirrors the Web
// SDK's `Public/API/Options.ts:293-303`.
//
// A default is only consulted where the SDK itself does the work (the
// client-side VAD debounce, a UI-facing fallback label). Everything that
// crosses into commons leaves an unset field ABSENT so commons applies its own
// `rac_default` — the contract `llm-abi.ts` documents.

/** Every IDL default the SDK reads, grouped by option object. */
export const optionDefaults = {
  llm: lLMGenerationOptionsDefaults,
  stt: sTTOptionsDefaults,
  tts: tTSOptionsDefaults,
  vad: vADOptionsDefaults,
  embed: embeddingsOptionsDefaults,
  image: diffusionGenerationOptionsDefaults,
  diarization: diarizationOptionsDefaults,
  rag: rAGConfigurationDefaults,
  contextLength: storageDefaults.contextLength,
  /** The rate every audio path in this SDK normalizes to. */
  micSampleRateHz: audioCaptureDefaults.micSampleRateHz,
  /** Playback fallback when a synthesis result reports no rate of its own. */
  ttsSampleRateHz: audioCaptureDefaults.ttsSampleRateHz,
} as const;

/**
 * The one knob the SDK still decides for {@link LlmOptions}: `idl/llm_options.proto`
 * has no tool-choice field, so there is no `rac_default` to read. Every sampling
 * knob that used to live here is gone — both request builders leave an unset
 * field absent and let commons apply its own annotation.
 */
export const LLM_DEFAULTS = {
  toolChoice: ToolChoice.AUTO as ToolChoice,
} as const;

/**
 * Spec defaults for {@link ReasoningOptions}. `idl/thinking_tag_pattern.proto`
 * carries the pattern, not a policy, so these two stay local: "may think, do not
 * surface the thoughts" is the SDK's own contract.
 */
export const REASONING_DEFAULTS = {
  mode: ReasoningMode.ON,
  includeInOutput: false,
} as const;

/**
 * Spec defaults for {@link SegmentationOptions}. `SegmentationOptions` in
 * `idl/segmentation.proto` carries no `rac_default` annotations, so the proto3
 * zero value is the default and this states it explicitly for the one field the
 * public option exposes.
 */
export const SEGMENTATION_DEFAULTS = { includeDiagnosticImage: false } as const;

/**
 * Spec defaults for {@link ImageOptions}. `mode` has no IDL counterpart at all —
 * commons infers inpainting from a mask's presence — so it stays local;
 * `reportPartials` is an SDK-side streaming policy, not a generation knob.
 */
export const IMAGE_DEFAULTS = { mode: 'GENERATE' as ImageMode, reportPartials: false } as const;

/**
 * Spec defaults for {@link TurnHandlingOptions}. Deliberately local: there is no
 * IDL counterpart for either dial. `TurnDetection` has `silence_duration_ms` but
 * no maximum-delay or interruption-duration field, and commons' own endpointing
 * caps are compile-time constants in `voice_agent_feed_abi.cpp`.
 */
export const TURN_DEFAULTS = {
  endpointing: { minDelayMs: 500, maxDelayMs: 3000 },
  interruption: { enabled: true, minDurationMs: 500 },
} as const;

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
 * Map {@link LlmOptions} onto the addon's keys. An unset field is omitted so the
 * addon keeps `RAC_LLM_OPTIONS_DEFAULT`, which carries the same
 * `rac_default` annotations the proto path uses. `grammar` and `history` are
 * computed by the caller and merged in rather than being public option fields.
 *
 * Only the VLM path still goes through here; LLM generation is proto-native.
 */
export function toNativeGenerateOptions(
  o: LlmOptions = {},
  extra: { grammar?: string; history?: string[] } = {}
): NativeGenerateOptions {
  const native: NativeGenerateOptions = {};
  if (o.maxOutputTokens !== undefined) native.maxTokens = o.maxOutputTokens;
  if (o.temperature !== undefined) native.temperature = o.temperature;
  if (o.topP !== undefined) native.topP = o.topP;
  if (o.topK !== undefined) native.topK = o.topK;
  if (o.minP !== undefined) native.minP = o.minP;
  if (o.frequencyPenalty !== undefined) native.frequencyPenalty = o.frequencyPenalty;
  if (o.presencePenalty !== undefined) native.presencePenalty = o.presencePenalty;
  if (o.repetitionPenalty !== undefined) native.repetitionPenalty = o.repetitionPenalty;
  if (o.seed !== undefined) native.seed = o.seed;
  if (o.systemPrompt !== undefined) native.systemPrompt = o.systemPrompt;
  if (o.stopSequences?.length) native.stopSequences = [...o.stopSequences];
  if (o.reasoning?.mode === 'OFF') native.disableThinking = true;
  if (extra.grammar) native.grammar = extra.grammar;
  if (extra.history && extra.history.length) native.history = [...extra.history];
  return native;
}

// ---------------------------------------------------------------------------
// C-ABI enum mirrors
// ---------------------------------------------------------------------------
//
// These are the C enum's ordinals, NOT the proto's. They exist because the
// addon's remaining N-API bindings take and return bare ints
// (`NativeAddon.synthesize` resolves `audioFormat: number`), and the proto
// numbering is different: `rac_audio_format_enum_t` starts at PCM = 0 while
// `runanywhere.v1.AudioFormat` starts at PCM = 1. Applying one decoder to the
// other's values is off by one for every member, which is exactly the bug that
// made `tts.synthesize` report PCM output as WAV.

/** `rac_audio_format_enum_t` ordinals (`rac/features/stt/rac_stt_types.h:73-79`). */
const RAC_AUDIO_FORMAT_ORDINAL: Readonly<Record<AudioFormat, number>> = Object.freeze({
  [AudioFormat.PCM]: 0,
  [AudioFormat.WAV]: 1,
  [AudioFormat.MP3]: 2,
  [AudioFormat.OPUS]: 3,
  [AudioFormat.AAC]: 4,
  [AudioFormat.FLAC]: 5,
});

const RAC_AUDIO_FORMAT_NAME = new Map<number, AudioFormat>(
  (Object.entries(RAC_AUDIO_FORMAT_ORDINAL) as Array<[AudioFormat, number]>).map(
    ([name, ordinal]) => [ordinal, name]
  )
);

/**
 * Decode a `rac_audio_format_enum_t` ordinal — the C ABI's numbering, as the
 * addon's own N-API bindings report it.
 *
 * NOT for a proto `AudioFormat` value: use {@link audioFormatFromProto} for
 * anything that arrived inside a generated message.
 */
export function audioFormatFromRacOrdinal(ordinal: number): AudioFormat {
  return RAC_AUDIO_FORMAT_NAME.get(ordinal) ?? AudioFormat.PCM;
}

/** Encode a public {@link AudioFormat} as its `rac_audio_format_enum_t` ordinal. */
export function audioFormatToRacOrdinal(format: AudioFormat): number {
  return RAC_AUDIO_FORMAT_ORDINAL[format] ?? RAC_AUDIO_FORMAT_ORDINAL[AudioFormat.PCM];
}

// ---------------------------------------------------------------------------
// Legacy N-API option shapes
// ---------------------------------------------------------------------------
//
// These describe the addon's OWN key spelling for the handful of verbs that
// still take a plain JS object rather than proto bytes. They are the wire shape
// of `RaBackend`'s speech/embedding/diarization methods, which is why they live
// here beside the public option types they are built from.
//
// They carry NO defaults: a field left absent is a field commons fills from its
// own `rac_default` annotation. Building a default in here is how the SDK and
// the IDL drift apart.

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

/** TTS options in the addon's own key spelling. `audioFormat` is a rac ordinal. */
export interface NativeTtsOptions {
  voice?: string;
  language?: string;
  speed?: number;
  pitch?: number;
  audioFormat?: number;
  sampleRate?: number;
}

/**
 * Embedding options in the addon's own key spelling. `normalize` and `pooling`
 * are `rac_embeddings_{normalize,pooling}_t` ordinals.
 */
export interface NativeEmbedOptions {
  normalize?: number;
  pooling?: number;
}

/** VAD config in the addon's `createVad` spelling. */
export interface NativeVadConfig {
  activationThreshold?: number;
  sampleRate?: number;
  frameLength?: number;
  modelPath?: string;
}

/** Diarization options in the addon's own key spelling. */
export interface NativeDiarizationOptions {
  threshold?: number;
  minimumDurationMs?: number;
  mergeGapMs?: number;
  sampleRate?: number;
}

/**
 * Decode a proto `runanywhere.v1.AudioFormat` to the public name — the decoder
 * every generated message's `audio_format` field needs. `PCM_S16LE`, `OGG`, and
 * `M4A` have no public member, and the public surface only ever hands back
 * float32 samples, so they report as PCM (mirrors the Web SDK's
 * `Mapping.ts:414-418`).
 */
export function audioFormatFromProto(format: ProtoAudioFormat): AudioFormat {
  switch (format) {
    case ProtoAudioFormat.AUDIO_FORMAT_WAV:
      return AudioFormat.WAV;
    case ProtoAudioFormat.AUDIO_FORMAT_MP3:
      return AudioFormat.MP3;
    case ProtoAudioFormat.AUDIO_FORMAT_OPUS:
      return AudioFormat.OPUS;
    case ProtoAudioFormat.AUDIO_FORMAT_AAC:
      return AudioFormat.AAC;
    case ProtoAudioFormat.AUDIO_FORMAT_FLAC:
      return AudioFormat.FLAC;
    default:
      return AudioFormat.PCM;
  }
}

/** Encode a public {@link AudioFormat} as its proto `AudioFormat` value. */
export function audioFormatToProto(format: AudioFormat): ProtoAudioFormat {
  switch (format) {
    case AudioFormat.WAV:
      return ProtoAudioFormat.AUDIO_FORMAT_WAV;
    case AudioFormat.MP3:
      return ProtoAudioFormat.AUDIO_FORMAT_MP3;
    case AudioFormat.OPUS:
      return ProtoAudioFormat.AUDIO_FORMAT_OPUS;
    case AudioFormat.AAC:
      return ProtoAudioFormat.AUDIO_FORMAT_AAC;
    case AudioFormat.FLAC:
      return ProtoAudioFormat.AUDIO_FORMAT_FLAC;
    default:
      return ProtoAudioFormat.AUDIO_FORMAT_PCM;
  }
}
