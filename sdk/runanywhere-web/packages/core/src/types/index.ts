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
  StreamToken,
} from '@runanywhere/proto-ts/llm_options';
export type { ReasoningOptions } from '@runanywhere/proto-ts/thinking_tag_pattern';
export { ReasoningMode } from '@runanywhere/proto-ts/thinking_tag_pattern';
export { ExecutionTarget } from '@runanywhere/proto-ts/llm_options';

// Web-only LLM streaming types (browser AsyncIterable + cancel handle).
import type {
  LLMGenerationResult as ProtoLLMGenerationResult,
  LLMGenerationOptions as ProtoLLMGenerationOptions,
} from '@runanywhere/proto-ts/llm_options';
import type { LLMStreamEvent } from '@runanywhere/proto-ts/llm_service';

export interface LLMStreamingResult {
  /** Canonical typed events, including thinking, progress, and terminal state. */
  events?: AsyncIterable<LLMStreamEvent>;
  /** Answer tokens only. Thinking tokens are available through `events`. */
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
  maxOutputTokens: lLMGenerationOptionsDefaults().maxOutputTokens,
  temperature: lLMGenerationOptionsDefaults().temperature,
  topP: lLMGenerationOptionsDefaults().topP,
  stopSequences: [] as readonly string[],
}) as Readonly<{
  maxOutputTokens: number;
  temperature: number;
  topP: number;
  stopSequences: readonly string[];
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
    maxOutputTokens: options.maxOutputTokens ?? LLM_GENERATION_DEFAULTS.maxOutputTokens,
    temperature: options.temperature ?? LLM_GENERATION_DEFAULTS.temperature,
    topP: options.topP ?? LLM_GENERATION_DEFAULTS.topP,
    stopSequences: options.stopSequences ?? [...LLM_GENERATION_DEFAULTS.stopSequences],
  };
}

// ---------------------------------------------------------------------------
// VLM — proto-ts canonical types + Web-only browser shapes
// ---------------------------------------------------------------------------
// VLMImage and VLMResult are re-exported as runtime values (not `export
// type`) because the lifecycle VLM adapter calls `.encode()` / `.decode()`
// on them. ts-proto generates a dual interface + const for each message, so
// the runtime export still carries the full type shape as well.
//
// `VLMConfiguration`, `VLMServiceState`, and `VLMImageFormat` were deleted
// outright from idl/vlm_options.proto. `VLMGenerationOptions` was replaced
// by the plain `LLMGenerationOptions` (same text-generation knobs) plus the
// narrower `VLMVisionOptions` for the vision-only knobs.
export {
  VLMImage,
  VLMResult,
} from '@runanywhere/proto-ts/vlm_options';
export type {
  VLMGenerationRequest,
  VLMStreamEvent,
  VLMVisionOptions,
} from '@runanywhere/proto-ts/vlm_options';
export {
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
import type { STTOptions } from '@runanywhere/proto-ts/stt_options';

// Raw browser PCM buffers do not carry sample rate, so the Web adapter accepts
// that one transport hint alongside canonical STTOptions.
export type STTTranscribeOptions =
  Partial<STTOptions> & {
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
// `TTSConfiguration`, `TTSPhonemeTimestamp`, and `TTSVoiceGender` were
// deleted outright from idl/tts_options.proto.
export type {
  TTSOptions,
  TTSOutput,
  TTSSpeakResult,
  TTSVoiceInfo,
  TTSSynthesisMetadata,
} from '@runanywhere/proto-ts/tts_options';
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
import { lLMGenerationOptionsDefaults } from '@runanywhere/proto-ts/convenience/llm_options_convenience';

export type SpeechActivityCallback = (activity: SpeechActivityKind) => void;

export interface SpeechSegment {
  startTime: number;
  samples: Float32Array;
}

// ---------------------------------------------------------------------------
// LoRA — proto-ts canonical types
// ---------------------------------------------------------------------------
// Web SDK uses proto names directly. `LoraAdapterCatalogEntry` was trimmed
// to 6 adapter-specific fields (id/name/compatibleModels/defaultScale/tags/
// localPath) — generic artifact facts now live on the ModelInfo record.
// `LoraAdapterDownloadCompletedRequest`/`Result` and
// `LoraAdapterImportRequest`/`Result` were deleted outright: adapter files
// are acquired through the models domain's download/import verbs now.
export type {
  LoraAdapterCatalogEntry,
  LoraAdapterCatalogGetRequest,
  LoraAdapterCatalogGetResult,
  LoraAdapterCatalogListRequest,
  LoraAdapterCatalogListResult,
  LoraAdapterCatalogQuery,
  LoraAdapterConfig,
  LoraAdapterInfo,
  LoraApplyRequest,
  LoraApplyResult,
  LoraCompatibilityResult,
  LoraRemoveRequest,
  LoraState,
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
// `VoiceSessionConfig` was deleted outright; `VoiceAgentComposeConfig` is the
// sole session-configuration message now.
export type {
  VoiceAgentResult,
  VoiceAgentComposeConfig,
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
// `ModelQuerySortField` was deleted outright.
export {
  AudioFormat,
  InferenceFramework,
  ModelArtifactType,
  ModelCategory,
  ModelFileRole,
  ModelFormat,
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
// `DownloadStage` was deleted outright; `DownloadState` is the sole
// download-phase enum now.
export { DownloadState } from '@runanywhere/proto-ts/download_service';
export { AccelerationPreference } from '@runanywhere/proto-ts/hardware_profile';

export type {
  ModelInfo,
  SDKInitOptions,
  StorageInfo,
} from './models.js';
export type { DeviceInfo } from '@runanywhere/proto-ts/device_info';
export type { ModelInfoMetadata } from '@runanywhere/proto-ts/model_types';
export type { ThinkingTagPattern } from '@runanywhere/proto-ts/thinking_tag_pattern';
