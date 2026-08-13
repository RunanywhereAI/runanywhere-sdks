/**
 * `@runanywhere/web` — the public RunAnywhere Web SDK surface.
 *
 * Applications import `RunAnywhere` plus the option, result, and event types
 * below. Backend packages integrate through `@runanywhere/web/backend`;
 * browser device helpers live in `@runanywhere/web/browser`. Nothing under
 * `@runanywhere/web/internal` is part of this contract.
 */

import { RunAnywhere as RunAnywhereV3 } from './Public/API/RunAnywhere.js';
import { deprecatedForwarders } from './Public/API/Deprecated.js';

/**
 * The RunAnywhere on-device AI SDK.
 *
 * Descriptors are copied rather than spread: `isReady`, `version`, `deviceId`,
 * and `events` are getters, and a spread would freeze them at import time.
 */
export const RunAnywhere: typeof RunAnywhereV3 & typeof deprecatedForwarders =
  Object.defineProperties(
    {} as typeof RunAnywhereV3 & typeof deprecatedForwarders,
    {
      ...Object.getOwnPropertyDescriptors(RunAnywhereV3),
      ...Object.getOwnPropertyDescriptors(deprecatedForwarders),
    },
  );

export type { Environment, InitializeOptions } from './Public/API/RunAnywhere.js';

// Inputs
export { AudioInput, ImageInput, RagDocument } from './Public/API/Inputs.js';
export type {
  AudioContainerFormat,
  AudioEncoding,
  AudioFormatSpec,
  AudioFrame,
  ChatMessage,
  ChatRole,
  ModelRef,
} from './Public/API/Inputs.js';

// Options
export { inpaintMode } from './Public/API/Options.js';
export type {
  AcceleratorPolicy,
  Backend,
  BackendPreference,
  DiarizationOptions,
  EmbedOptions,
  ImageMode,
  ImageOptions,
  JsonSchema,
  LlmOptions,
  LoadOptions,
  ModelFileRegistration,
  ModelFilter,
  ModelRegistration,
  RagConfig,
  RagQueryOptions,
  RagRetrievalOptions,
  ReasoningOptions,
  SegmentationOptions,
  SttOptions,
  StructuredOutput,
  StructuredOutputMode,
  ToolChoice,
  TtsOptions,
  TurnHandlingOptions,
  VadOptions,
} from './Public/API/Options.js';

// Computer-Use Agent scaffold (cross-SDK parity with Swift RunAnywhere.CUA).
// Stateless, model-agnostic profile ABI surfaced via `RunAnywhere.CUA.*`.
export { CUA, CuaActionKind } from './Public/Extensions/RunAnywhere+CUA.js';
export type {
  CuaAction,
  CuaCoordinate,
  CuaDisplaySize,
} from './Public/Extensions/RunAnywhere+CUA.js';

// Results
export type {
  AppliedAdapter,
  Audio,
  AudioChunk,
  ClassInfo,
  DiarizationResult,
  Embedding,
  FinishReason,
  GenerationMetrics,
  GenerationResult,
  ImageData,
  ImageResult,
  LoadedModel,
  LoraState,
  Match,
  ModelInfo,
  ModelsState,
  RagCapabilities,
  RagResult,
  RagStats,
  RankedResult,
  SDKCapabilities,
  Segment,
  SegmentationResult,
  SpeakerSegment,
  SpeechHandle,
  StreamingCapabilities,
  StructuredResult,
  SttState,
  SttStream,
  ToolCapabilities,
  Transcription,
  UnavailableCapability,
  VadResult,
  VadStream,
  Voice,
  Word,
} from './Public/API/Results.js';

// Events
export type {
  AgentState,
  DownloadEvent,
  GenerationEvent,
  ImageEvent,
  RagEvent,
  SdkEvent,
  TokenKind,
  TranscriptAlternative,
  TranscriptionEvent,
  VadEvent,
  VoiceEvent,
} from './Public/API/Events.js';

// Sessions
export type { RagSession } from './Public/API/Namespaces/rag.js';
export type { VoiceSession, VoiceSessionOptions } from './Public/API/Namespaces/voice.js';

// `RunAnywhere.solutions.run(input)` takes SolutionRunInput and returns a
// SolutionHandle, so a consumer cannot annotate either side of that call
// without these. Type-only: SolutionHandle is constructed by SolutionAdapter.run,
// never by callers. SolutionConfig is deliberately absent: it comes straight
// from @runanywhere/proto-ts/solutions, which consumers depend on directly.
export type {
  SolutionHandle,
  SolutionRunInput,
} from './Public/Extensions/RunAnywhere+Solutions.js';

// Errors — one typed exception carrying the generated proto error taxonomy.
export { SDKException, isSDKException } from './Foundation/SDKException.js';
export type { ProtoSDKError } from './Foundation/SDKException.js';
export {
  ProtoErrorCategory,
  ProtoErrorCode,
  ProtoErrorSeverity,
} from './Foundation/SDKException.js';

// Generated enums referenced by public option and result fields.
export {
  InferenceFramework,
  ModelCategory,
  ModelFormat,
  SDKEnvironment,
} from '@runanywhere/proto-ts/model_types';
export type { ToolDefinition } from '@runanywhere/proto-ts/tool_calling';

/** Human-readable label for an inference framework, from the commons table. */
export { formatFramework } from './Public/Helpers/formatFramework.js';

// SDK metadata.
export { SDK_NAME, SDK_PLATFORM, SDK_VERSION } from './Foundation/Version.js';
