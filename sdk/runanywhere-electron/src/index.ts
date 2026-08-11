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
  DownloadEvent,
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
export type { RefreshOptions } from './api/assets';
export { ResidencyPolicy } from './api/residency';
export type { ResidencyDecision, ResidencySlots, ResidentModel } from './api/residency';
export type { AuthState, MemoryInfo } from './api/backend';
export type { VoiceSession, VoiceSessionConfig } from './api/speech';
export type { RagSession } from './api/data';

// ---- errors, platform helpers, and the model store ----
// Not a second API surface: these are the pieces a host application needs that
// have no namespace of their own — typed errors, renderer-side audio helpers
// (commons DSP via the N-API addon), and the staged catalog it hands the SDK
// before initialize().
export { SDKException, ErrorCode, ErrorCategory, isSDKException, asSDKException, raiseForRac } from './errors';
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
export type { NativeAddon } from './bridge';
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
