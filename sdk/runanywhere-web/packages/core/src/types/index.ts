/**
 * RunAnywhere Web SDK — Public Types Barrel.
 *
 * All hand-rolled duplicate type files have been deleted. This barrel
 * re-exports proto-ts types directly (single source of truth = idl/*.proto) and
 * adds a small set of Web-only ergonomic shapes that proto doesn't cover
 * (browser-specific I/O, streaming session interfaces).
 *
 * Source of truth (wire shape): idl/*.proto → @runanywhere/proto-ts/*
 */

// ---------------------------------------------------------------------------
// LLM — proto-ts canonical types
// ---------------------------------------------------------------------------
export type {
  LLMGenerationOptions,
  LLMGenerationResult,
  LLMConfiguration,
  GenerationHints,
  StreamToken,
} from '@runanywhere/proto-ts/llm_options';
export { ExecutionTarget } from '@runanywhere/proto-ts/llm_options';

// Web-only LLM streaming types (browser AsyncIterable + cancel handle).
import type {
  LLMGenerationResult as ProtoLLMGenerationResult,
  LLMGenerationOptions as ProtoLLMGenerationOptions,
} from '@runanywhere/proto-ts/llm_options';

export interface LLMStreamingResult {
  stream: AsyncIterable<string>;
  result: Promise<ProtoLLMGenerationResult>;
  cancel: () => void;
}

export interface LLMStreamingMetrics {
  fullText: string;
  tokenCount: number;
  timeToFirstTokenMs?: number;
  totalTimeMs: number;
  tokensPerSecond: number;
  completed: boolean;
  error?: string;
}

export type LLMTokenCallback = (token: string) => void;
export type LLMStreamCompleteCallback = (result: ProtoLLMGenerationResult) => void;
export type LLMStreamErrorCallback = (error: Error) => void;

/**
 * Default values aligned with Swift `LLMGenerationOptions` defaults.
 * Use `applyLLMGenerationDefaults(opts)` to merge defaults into a partial
 * options object.
 */
export const LLM_GENERATION_DEFAULTS = Object.freeze({
  maxTokens: 100,
  temperature: 0.8,
  topP: 1.0,
  stopSequences: [] as readonly string[],
  streamingEnabled: false,
}) as Readonly<{
  maxTokens: number;
  temperature: number;
  topP: number;
  stopSequences: readonly string[];
  streamingEnabled: boolean;
}>;

/**
 * Merge Swift-aligned defaults into the user-supplied options.
 * Returns a new object so the caller's input is not mutated.
 */
export function applyLLMGenerationDefaults(
  options: Partial<ProtoLLMGenerationOptions> = {},
): Partial<ProtoLLMGenerationOptions> {
  return {
    ...options,
    maxTokens: options.maxTokens ?? LLM_GENERATION_DEFAULTS.maxTokens,
    temperature: options.temperature ?? LLM_GENERATION_DEFAULTS.temperature,
    topP: options.topP ?? LLM_GENERATION_DEFAULTS.topP,
    stopSequences: options.stopSequences ?? [...LLM_GENERATION_DEFAULTS.stopSequences],
    streamingEnabled: options.streamingEnabled ?? LLM_GENERATION_DEFAULTS.streamingEnabled,
  };
}

// ---------------------------------------------------------------------------
// VLM — proto-ts canonical types + Web-only browser shapes
// ---------------------------------------------------------------------------
// VLMImage, VLMGenerationOptions, and VLMResult are re-exported as runtime
// values (not `export type`) because the lifecycle VLM adapter calls
// `.encode()` / `.decode()` on them. ts-proto generates a dual interface +
// const for each message, so the runtime export still carries the full type
// shape as well.
export {
  VLMImage,
  VLMGenerationOptions,
  VLMResult,
} from '@runanywhere/proto-ts/vlm_options';
export type {
  VLMConfiguration,
  VLMGenerationRequest,
  VLMStreamEvent,
  VLMServiceState,
} from '@runanywhere/proto-ts/vlm_options';
export {
  VLMImageFormat,
  VLMModelFamily,
  VLMStreamEventKind,
} from '@runanywhere/proto-ts/vlm_options';

// ---------------------------------------------------------------------------
// STT — proto-ts canonical types
// ---------------------------------------------------------------------------
export type {
  STTConfiguration,
  STTOptions,
  STTOutput,
  STTPartialResult,
  WordTimestamp,
  TranscriptionAlternative,
  TranscriptionMetadata,
} from '@runanywhere/proto-ts/stt_options';
export { STTLanguage } from '@runanywhere/proto-ts/stt_options';
import type { STTOptions } from '@runanywhere/proto-ts/stt_options';

// Raw browser PCM buffers do not carry sample rate, so the Web adapter accepts
// that one transport hint alongside canonical STTOptions.
export type STTTranscribeOptions =
  Partial<Omit<STTOptions, 'language'>> & {
    language?: STTOptions['language'] | string;
    sampleRate?: number;
  };

export type STTStreamCallback = (text: string, isFinal: boolean) => void;

export interface STTStreamingSession {
  acceptWaveform(samples: Float32Array, sampleRate?: number): void;
  inputFinished(): void;
  getResult(): { text: string; isEndpoint: boolean };
  reset(): void;
  destroy(): void;
}

// ---------------------------------------------------------------------------
// TTS — proto-ts canonical types + Web-only browser shapes
// ---------------------------------------------------------------------------
export type {
  TTSConfiguration,
  TTSOptions,
  TTSOutput,
  TTSSpeakResult,
  TTSVoiceInfo,
  TTSPhonemeTimestamp,
  TTSSynthesisMetadata,
} from '@runanywhere/proto-ts/tts_options';
export { TTSVoiceGender } from '@runanywhere/proto-ts/tts_options';
import type { TTSOptions } from '@runanywhere/proto-ts/tts_options';

// Web-only synthesis result (Float32Array PCM for direct Web Audio playback).
export interface TTSSynthesisResult {
  [key: string]: unknown;
  audioData: Float32Array;
  sampleRate: number;
  durationMs: number;
  processingTimeMs: number;
}

export type TTSSynthesizeOptions = Partial<TTSOptions>;

// ---------------------------------------------------------------------------
// VAD — proto-ts canonical types + Web-only ergonomic shapes
// ---------------------------------------------------------------------------
export type {
  VADConfiguration,
  VADOptions,
  VADResult,
  VADStatistics,
  SpeechActivityEvent,
} from '@runanywhere/proto-ts/vad_options';
export { SpeechActivityKind } from '@runanywhere/proto-ts/vad_options';
import type { SpeechActivityKind } from '@runanywhere/proto-ts/vad_options';

export type SpeechActivityCallback = (activity: SpeechActivityKind) => void;

export interface SpeechSegment {
  startTime: number;
  samples: Float32Array;
}

// ---------------------------------------------------------------------------
// LoRA — proto-ts canonical types
// ---------------------------------------------------------------------------
// Web SDK uses proto names directly: `adapterPath`, `url`,
// `compatibleModels`, `sizeBytes`, `errorMessage`.
export type {
  LoRAAdapterConfig,
  LoRAAdapterInfo,
  LoRAApplyRequest,
  LoRAApplyResult,
  LoRARemoveRequest,
  LoRAState,
  LoraAdapterCatalogEntry,
  LoraAdapterCatalogGetRequest,
  LoraAdapterCatalogGetResult,
  LoraAdapterCatalogListRequest,
  LoraAdapterCatalogListResult,
  LoraAdapterCatalogQuery,
  LoraAdapterDownloadCompletedRequest,
  LoraAdapterDownloadCompletedResult,
  LoraCompatibilityResult,
} from '@runanywhere/proto-ts/lora_options';

// ---------------------------------------------------------------------------
// RAG — proto-ts canonical types
// ---------------------------------------------------------------------------
export type {
  RAGConfiguration,
  RAGQueryOptions,
  RAGSearchResult,
  RAGResult,
  RAGStatistics,
} from '@runanywhere/proto-ts/rag';

// ---------------------------------------------------------------------------
// Voice Agent — proto-ts canonical + Web-only ergonomic shapes
// ---------------------------------------------------------------------------
export type {
  VoiceAgentResult,
  VoiceAgentComposeConfig,
  VoiceSessionConfig,
} from '@runanywhere/proto-ts/voice_agent_service';
export type { VoiceAgentComponentStates } from '@runanywhere/proto-ts/voice_events';
// Former ComponentLoadState re-exported as the canonical
// ComponentLifecycleState (from component_types.proto).

// ---------------------------------------------------------------------------
// Model lifecycle — generated proto source of truth
// ---------------------------------------------------------------------------
export type {
  CurrentModelRequest,
  CurrentModelResult,
  ModelLoadRequest,
  ModelLoadResult,
  ModelUnloadRequest,
  ModelUnloadResult,
} from '@runanywhere/proto-ts/model_types';
export type {
  ComponentLifecycleEvent,
  ComponentLifecycleSnapshot,
} from '@runanywhere/proto-ts/sdk_events';
// ---------------------------------------------------------------------------
// Tool Calling — pure proto re-export
// ---------------------------------------------------------------------------
export * from '@runanywhere/proto-ts/tool_calling';

// ---------------------------------------------------------------------------
// Chat / downloads — pure proto re-exports
// ---------------------------------------------------------------------------
export type { ChatMessage } from '@runanywhere/proto-ts/chat';
export { ChatMessageStatus, MessageRole } from '@runanywhere/proto-ts/chat';
export type { DownloadProgress } from '@runanywhere/proto-ts/download_service';

// ---------------------------------------------------------------------------
// Canonical proto enums/messages that used to be mirrored by Web-local enums.
// The short Web aliases (`SDKEnvironment.Development`,
// `ModelCategory.Language`, etc.) are intentionally not re-exported here.
// ---------------------------------------------------------------------------
export {
  AudioFormat,
  InferenceFramework,
  ModelCategory,
  ModelFileRole,
  ModelFormat,
  ModelArtifactType,
  ModelQuerySortField,
  ModelQuerySortOrder,
  ModelRegistryStatus,
  ModelSource,
  RoutingPolicy,
  SDKEnvironment,
} from '@runanywhere/proto-ts/model_types';
export {
  ComponentLifecycleState,
  EventCategory,
} from '@runanywhere/proto-ts/component_types';
export {
  EventDestination,
  SDKComponent,
} from '@runanywhere/proto-ts/sdk_events';
export { ErrorSeverity } from '@runanywhere/proto-ts/errors';
export { DownloadStage, DownloadState } from '@runanywhere/proto-ts/download_service';
export { AccelerationPreference } from '@runanywhere/proto-ts/hardware_profile';

export type {
  ModelInfo,
  SDKInitOptions,
  StorageInfo,
  StoredModel,
} from './models.js';
export type { DeviceInfo } from '@runanywhere/proto-ts/device_info';
export type { ModelInfoMetadata } from '@runanywhere/proto-ts/model_types';
export type { ThinkingTagPattern } from '@runanywhere/proto-ts/thinking_tag_pattern';
