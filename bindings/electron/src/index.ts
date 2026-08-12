// @runanywhere/electron — on-device LLM / VLM / STT / TTS / VAD / embeddings /
// rerank / diarization / segmentation / RAG for Electron & Node, over the native
// addon. `createRunAnywhere` is the whole API; the pre-v3 flat surface
// (RunAnywhere, Chat, VoiceAgent and their helpers) has been removed.

// ---- v3 surface ----
export { createRunAnywhere } from './api/facade';
export type {
  AuthInfo,
  AuthNamespace,
  AuthStatus,
  InitializeOptions,
  RunAnywhereApi,
  SecureStore,
  TelemetryNamespace,
} from './api/facade';
export { NativeBackend, RAC_CATEGORY, RAC_FRAMEWORK } from './api/native-backend';
export { RpcBackend } from './api/rpc-backend';
export type { RpcSend } from './api/rpc-backend';
export { BACKEND_METHODS, BACKEND_STREAMING_METHODS, rpcMethodFor } from './api/backend';
export type { RaBackend, LoadSlot } from './api/backend';
export { AsyncQueue, bridgeStream, collect, streamOf } from './api/iter';
export type { StreamSink } from './api/iter';
export { SdkEventHub } from './api/hub';
export {
  ModelAbi,
  categoryFromProto,
  categoryToProto,
  frameworkFromProto,
  frameworkToProto,
  toPublicModelInfo,
} from './api/model-abi';
// Proto messages the public surface takes and returns directly, so a caller can
// build a `models.import` request and read a `componentLifecycleSnapshot`
// without depending on `@runanywhere/proto-ts` itself.
export { ComponentLifecycleSnapshot, ModelImportRequest, SDKComponent } from './api/model-abi';
export type { ModelImportResult } from './api/model-abi';
export {
  audio,
  image,
  ragDocument,
  AgentState,
  AudioEncoding,
  AudioFormat,
  DevicePlacement,
  Environment,
  FinishReason,
  ImageMode,
  InferenceFramework,
  ModelCategory,
  NormalizeMode,
  PoolingMode,
  ReasoningMode,
  Role,
  TokenKind,
  ToolChoice,
  newRequestId,
  toProtoError,
} from './api/types';
export type {
  AppliedAdapter,
  Audio,
  AudioChunk,
  AudioFormatSpec,
  AudioFrame,
  AudioInput,
  ChatMessage,
  ClassInfo,
  DiarizationResult,
  DiscoveredModel,
  DownloadEvent,
  DownloadProgressSnapshot,
  Embedding,
  GenerationEvent,
  GenerationMetrics,
  GenerationResult,
  ImageData,
  ImageEvent,
  ImageInput,
  ImageResult,
  LoadedModel,
  LoraState,
  Match,
  ModelCompatibility,
  ModelFilter,
  ModelInfo,
  ModelRef,
  ModelRegistration,
  ModelsState,
  RagCapabilities,
  RagDocument,
  RagEvent,
  RagResult,
  RagStats,
  RankedResult,
  SDKCapabilities,
  SdkEvent,
  Segment,
  SegmentationResult,
  SpeakerSegment,
  SpeechHandle,
  StreamingCapabilities,
  SttState,
  SttStream,
  StructuredResult,
  TokenUsage,
  ToolCall,
  ToolCapabilities,
  ToolDefinition,
  ToolExecutor,
  Transcription,
  TranscriptionEvent,
  UnavailableCapability,
  VadEvent,
  VadResult,
  VadStream,
  Voice,
  VoiceEvent,
  Word,
} from './api/types';
export type {
  DiarizationOptions,
  EmbedOptions,
  Endpointing,
  ImageOptions,
  Interruption,
  LlmOptions,
  LoadOptions,
  RagConfig,
  ReasoningOptions,
  SegmentationOptions,
  SttOptions,
  StructuredOutput,
  TtsOptions,
  TurnHandlingOptions,
  VadOptions,
} from './api/options';
// The namespace interfaces are reached through `RunAnywhereApi`, not by name.
export type { DiscoverOptions, RefreshOptions } from './api/assets';
// The Node-side half of the HuggingFace bearer. An application calls
// `RunAnywhere.setHfToken(...)`, which drives BOTH this and commons; these are
// exported for a host that runs `resolveModel`/`downloadFile` directly, without
// a facade to route through.
export { huggingFaceBearer, setHuggingFaceToken } from './api/hf';
// `storage` is the exception: its verbs speak the generated storage protos, so a
// caller needs the message types by name to build a request or read a result.
export type { StorageNamespace } from './api/storage';
export {
  StorageAvailabilityRequest,
  StorageDeletePlanRequest,
  StorageDeleteRequest,
  StorageInfoRequest,
} from '@runanywhere/proto-ts/storage_types';
export type {
  StorageAvailability,
  StorageAvailabilityResult,
  StorageDeleteCandidate,
  StorageDeletePlan,
  StorageDeleteResult,
  StorageInfo,
  StorageInfoResult,
} from '@runanywhere/proto-ts/storage_types';
// `lora` is the other one: its catalog verbs take and return the generated LoRA
// messages, so a caller building an entry or reading a query result needs them.
export type { LoraNamespace } from './api/assets';
export {
  LoraAdapterCatalogEntry,
  LoraAdapterCatalogQuery,
  LoraAdapterConfig,
} from '@runanywhere/proto-ts/lora_options';
export type {
  LoraAdapterCatalogGetResult,
  LoraAdapterCatalogListResult,
  LoraAdapterInfo,
  LoraApplyResult,
  LoraCompatibilityResult,
} from '@runanywhere/proto-ts/lora_options';
// `logging` speaks the generated logging protos for the same reason: a
// destination reads a `LogEntry`, and a level is a `LogLevel`.
export type { LogDestination, LoggingNamespace } from './api/logging';
export { LogLevel } from '@runanywhere/proto-ts/logging';
export type { LogEntry, LoggingConfiguration } from '@runanywhere/proto-ts/logging';
export { ResidencyPolicy } from './api/residency';
export type { ResidencyDecision, ResidencySlots, ResidentModel } from './api/residency';
export type { AuthState, MemoryInfo, NativeLogRecord } from './api/backend';
export type { VoiceSession, VoiceSessionConfig } from './api/speech';
export type { RagSession } from './api/data';

// ---- errors, platform helpers, and the model store ----
// Not a second API surface: these are the pieces a host application needs that
// have no namespace of their own — typed errors, renderer-side audio helpers
// (commons DSP via the utility-host / N-API addon), and the staged catalog it
// hands the SDK before initialize().
// `ErrorCode` / `ErrorCategory` / `ErrorSeverity` are the generated proto enums,
// so their members read `ERROR_CODE_MODEL_NOT_FOUND`. `ErrorCodes` /
// `ErrorCategories` are short-name alias objects derived from them, for app code
// that would rather write `ErrorCodes.MODEL_NOT_FOUND`.
// Local JSON-schema→GBNF (`grammar.ts`) is intentionally not exported: structured
// output grammar is commons-owned on the wire.
export {
  SDKException,
  ErrorCode,
  ErrorCodes,
  ErrorCategory,
  ErrorCategories,
  ErrorSeverity,
  categoryForCode,
  isSDKException,
  asSDKException,
  raiseForRac,
} from './errors';
export type { ErrorCategoryName, ErrorCodeName, SDKErrorFields } from './errors';
export type { JsonSchema } from './api/types';
export { speakableText } from './speech';
export {
  float32ToPcm16,
  pcm16ToFloat32,
  pcm16Bytes,
  downsample,
  rms,
  encodeWav,
  decodeWav,
  pcmDurationMs,
  float32DurationMs,
  MicRecorder,
  SpeakerPlayer,
  bindAudioBackend,
  setAudioNativeForTests,
} from './audio';
export type { MicRecorderOptions, AudioNative, AudioDspBackend } from './audio';
export type { NativeAddon, UnavailablePlugin } from './bridge';
export {
  registerCatalog,
  clearCatalog,
  catalogEntries,
  catalogEntry,
  catalogModelInfo,
  isCatalogId,
} from './catalog';
export type { Catalog, CatalogEntry, ModelType } from './catalog';
export { resolveModel, downloadFile, modelsRoot } from './download';
export type { DownloadProgress, ResolvedModel } from './download';
