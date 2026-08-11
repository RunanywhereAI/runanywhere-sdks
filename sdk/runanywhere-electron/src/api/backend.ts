// backend.ts — the contract between the shared v3 namespaces and whichever host
// owns the native addon.
//
// Two implementations exist: `NativeBackend` (in-process, holds the addon handles)
// and `RpcBackend` (a renderer talking to the utility host over a MessagePort).
// Every operation takes and returns only structured-cloneable values plus at most
// one chunk callback, so the RPC implementation is a mechanical forward and the
// two public surfaces are the same code.
//
// Native handles are integers owned entirely by `NativeBackend`; nothing in this
// interface exposes one, which is what keeps raw handles out of the renderer.

import type { DownloadProgress, ResolvedModel } from '../download';
import type {
  NativeDiarizationOptions,
  NativeEmbedOptions,
  NativeGenerateOptions,
  NativeSttOptions,
  NativeTtsOptions,
  NativeVadConfig,
} from './options';

/** Model slots the backend can hold one loaded artifact in at a time. */
export type LoadSlot =
  | 'llm'
  | 'vlm'
  | 'stt'
  | 'tts'
  | 'embedder'
  | 'rerank'
  | 'diarization'
  | 'segmentation';

/** Placement knobs forwarded to a load. */
export interface BackendLoadOptions {
  framework?: string;
  contextLength?: number;
  threads?: number;
  useGpu?: boolean;
}

/** What is loaded in a slot. */
export interface LoadedModel {
  /** The source the caller asked for (catalog id, repo, URL, or path). */
  id: string;
  /** Resolved primary artifact on disk. */
  path: string;
}

/** Terminal payload of a native generation stream. */
export interface NativeStreamResult {
  cancelled: boolean;
  hasMetrics: boolean;
  inputTokens: number;
  outputTokens: number;
  totalTokens: number;
  timeToFirstTokenMs: number;
  totalTimeMs: number;
  tokensPerSecond: number;
}

/**
 * What the tool-calling run loop asks of its host: `handle` once, so a caller
 * can cancel, then one `toolCall` per call commons wants executed. The reply to
 * a `toolCall` is serialized ToolResult bytes; commons is parked on it.
 */
export interface ToolRunLoopEvent {
  handle?: number;
  toolCall?: Uint8Array;
}

/** One timed word as the addon reports it. */
export interface NativeWord {
  text: string;
  startMs: number;
  endMs: number;
  confidence: number;
}

/** A transcription as the addon reports it. */
export interface NativeTranscription {
  text: string;
  language?: string;
  confidence: number;
  processingTimeMs: number;
  words: NativeWord[];
}

/** Synthesized audio as the addon reports it. */
export interface NativeAudio {
  sampleRate: number;
  samples: Float32Array;
  audioFormat: number;
  durationMs: number;
}

/** STT readiness as the addon reports it. */
export interface NativeSttInfo {
  isReady: boolean;
  modelId?: string;
  supportsStreaming: boolean;
  /** JSON array of BCP-47 tags, straight from commons. */
  languagesJson?: string;
}

/** TTS voice metadata as the addon reports it. */
export interface NativeTtsInfo {
  voiceId?: string;
  languagesJson?: string;
}

/** An image in one of the addon's three accepted shapes. */
export interface NativeImagePayload {
  path?: string;
  base64?: string;
  rgb?: Uint8Array;
  width?: number;
  height?: number;
}

/** A reranked candidate as the addon reports it. */
export interface NativeRanked {
  index: number;
  score: number;
  rank: number;
}

/** A diarization as the addon reports it. */
export interface NativeDiarization {
  segments: Array<{ speakerId: string; speakerIndex: number; startMs: number; endMs: number }>;
  speakerCount: number;
  durationMs: number;
}

/** A segmentation as the addon reports it. */
export interface NativeSegmentation {
  width: number;
  height: number;
  classMask: Uint16Array;
  classes: Array<{ classId: number; label?: string; pixelCount: number; fraction: number }>;
  diagnosticRgba?: Uint8Array;
}

/** An applied LoRA adapter as the addon reports it. */
export interface NativeLoraEntry {
  id: string;
  scale: number;
}

/** A partial transcript from a streamed transcription. */
export interface NativeSttPartial {
  text: string;
  isFinal: boolean;
}

/** One chunk of streamed synthesis. */
export interface NativeAudioChunk {
  samples: Float32Array;
}

/** Free space and usage of the model store. */
export interface StorageReport {
  usedBytes: number;
  freeBytes: number;
}

/** Physical RAM as the platform adapter reports it. Zero means "unknown". */
export interface MemoryInfo {
  totalBytes: number;
  availableBytes: number;
  usedBytes: number;
}

/** Inputs for {@link RaBackend.configureControlPlane}. Phase bytes are serialized
 * SdkInit{Phase1,Phase2}Request; `environment` is a rac_environment_t (0=dev, 2=prod). */
export interface ControlPlaneRequest {
  environment: number;
  apiKey: string;
  baseUrl: string;
  deviceId: string;
  platform: string;
  sdkVersion: string;
  sdkBinding: string;
  appIdentifier: string;
  appName: string;
  appVersion: string;
  phase1Bytes: Uint8Array;
  phase2Bytes: Uint8Array;
}

/** What the auth manager and rac_state currently hold. All fields are reads,
 * never inferences: `authenticated` means a live non-expired access token. */
export interface AuthState {
  authenticated: boolean;
  needsRefresh: boolean;
  /** Unix seconds; 0 when no token is held. */
  expiresAtUnixSec: number;
  userId: string;
  organizationId: string;
  deviceRegistered: boolean;
}

/** Everything a v3 namespace needs from its host. */
export interface RaBackend {
  // ---- lifecycle ----
  version(): Promise<string>;
  initialize(opts: { secureDir?: string; baseDir?: string }): Promise<void>;
  shutdown(): Promise<void>;
  /** Physical RAM, straight from the platform adapter commons itself reads. */
  memoryInfo(): Promise<MemoryInfo>;

  // ---- desktop control plane (telemetry + auth) ----
  /** Whether this build carries the desktop libcurl transport (auth + telemetry). */
  hasControlPlane(): Promise<boolean>;
  /** The persistent per-device UUID commons mints (empty if unavailable). */
  devicePersistentId(): Promise<string>;
  /** Baked staging backend URL for keyless development (empty when none). */
  devStagingBaseUrl(): Promise<string>;
  /** Register the transport, seed state, and run two-phase init. Returns SdkInitResult bytes. */
  configureControlPlane(req: ControlPlaneRequest): Promise<Uint8Array>;
  /** Re-run the HTTP setup an offline start skipped. Returns SdkInitResult bytes. */
  retryControlPlane(): Promise<Uint8Array>;
  /** Tokens, expiry, and device registration as commons holds them right now. */
  authState(): Promise<AuthState>;
  /** Forget the stored tokens; the next initialize authenticates from scratch. */
  clearAuth(): Promise<void>;
  /** Send whatever telemetry is queued instead of waiting for the periodic flush. */
  telemetryFlush(): Promise<void>;

  // ---- model store ----
  resolveModel(source: string, onProgress?: (p: DownloadProgress) => void): Promise<ResolvedModel>;
  modelStatus(): Promise<Record<string, { downloaded: boolean; sizeBytes: number }>>;
  pathExists(path: string): Promise<boolean>;
  storage(): Promise<StorageReport>;
  deleteModel(id: string): Promise<void>;
  registerModel(id: string, localPath: string, category: number, framework: number): Promise<void>;

  // ---- downloads over the commons orchestrator (proto bytes in, proto bytes out) ----
  //
  // Handle-free: commons keys every task by model id and task id. Progress is
  // one process-wide callback rather than a per-call stream, so `downloadWatch`
  // opens it once and resolves when `downloadUnwatch` closes it.
  downloadPlan(requestBytes: Uint8Array): Promise<Uint8Array>;
  downloadStart(requestBytes: Uint8Array): Promise<Uint8Array>;
  downloadCancel(requestBytes: Uint8Array): Promise<Uint8Array>;
  downloadProgress(requestBytes: Uint8Array): Promise<Uint8Array>;
  /** Purge terminal task slots; resolves the number commons erased. */
  downloadCleanup(): Promise<number>;
  /**
   * Sync `rac_download_progress_percent`. NativeBackend calls the C ABI;
   * RpcBackend forwards to the utility host (Promise) so bytes-ratio policy
   * is never re-derived in the renderer.
   */
  downloadProgressPercent(
    overallProgress: number,
    bytesDownloaded: number,
    totalBytes: number,
  ): number | Promise<number>;
  downloadWatch(onProgress: (progressBytes: Uint8Array) => void): Promise<void>;
  downloadUnwatch(): Promise<void>;

  // ---- storage over the commons analyzer (proto bytes in, proto bytes out) ----
  storageInfoProto(requestBytes: Uint8Array): Promise<Uint8Array>;
  storageAvailabilityProto(requestBytes: Uint8Array): Promise<Uint8Array>;
  storageDeletePlanProto(requestBytes: Uint8Array): Promise<Uint8Array>;
  storageDeleteProto(requestBytes: Uint8Array): Promise<Uint8Array>;

  /** Load `source` into `slot`, downloading first when it is not on disk. */
  ensure(slot: LoadSlot, source: string, options?: BackendLoadOptions): Promise<LoadedModel>;
  /** What occupies `slot`, or null. */
  loaded(slot: LoadSlot): Promise<LoadedModel | null>;
  /** Release `slot`, or every slot when omitted. */
  unload(slot?: LoadSlot): Promise<void>;

  // ---- llm ----
  llmGenerate(
    prompt: string,
    options: NativeGenerateOptions,
    onToken: (token: string) => void
  ): Promise<NativeStreamResult>;
  llmCancel(): Promise<void>;
  // ---- lora over the lifecycle proto ABI ----
  loraApplyProto(requestBytes: Uint8Array): Promise<Uint8Array>;
  loraRemoveProto(requestBytes: Uint8Array): Promise<Uint8Array>;
  loraStateProto(requestBytes: Uint8Array): Promise<Uint8Array>;

  loraApply(adapterPath: string, scale: number): Promise<void>;
  loraRemove(adapterPath?: string): Promise<void>;
  loraList(): Promise<NativeLoraEntry[]>;

  // ---- vlm over the proto ABI (proto bytes in, proto bytes out) ----
  //
  // Handle-free like the llm entry points: commons resolves the vision model the
  // lifecycle load made resident, and the image rides inside the request.
  vlmGenerateProto(requestBytes: Uint8Array): Promise<Uint8Array>;
  vlmStreamProto(
    requestBytes: Uint8Array,
    onEvent: (eventBytes: Uint8Array) => void
  ): Promise<void>;
  vlmCancelProto(): Promise<Uint8Array>;

  // ---- stt / tts / vad over the lifecycle proto ABI ----
  //
  // Handle-free: each reads whatever the lifecycle load made resident for its
  // component. Typed decode happens once, in `speech-abi.ts`.
  sttTranscribeProto(requestBytes: Uint8Array): Promise<Uint8Array>;
  sttTranscribeStreamProto(
    requestBytes: Uint8Array,
    onEvent: (eventBytes: Uint8Array) => void
  ): Promise<void>;
  sttStateProto(): Promise<Uint8Array>;
  ttsSynthesizeProto(requestBytes: Uint8Array): Promise<Uint8Array>;
  ttsSynthesizeStreamProto(
    requestBytes: Uint8Array,
    onEvent: (eventBytes: Uint8Array) => void
  ): Promise<void>;
  ttsStopProto(): Promise<Uint8Array>;
  ttsListVoicesProto(): Promise<Uint8Array>;
  ttsStateProto(): Promise<Uint8Array>;
  vadProcessProto(requestBytes: Uint8Array): Promise<Uint8Array>;
  vadConfigureProto(requestBytes: Uint8Array): Promise<Uint8Array>;
  vadStartProto(): Promise<Uint8Array>;
  vadStopProto(): Promise<Uint8Array>;
  vadResetProto(): Promise<Uint8Array>;

  // ---- voice agent (proto bytes in, proto bytes out; sessions keyed by opaque id) ----
  //
  // Handle-bound, unlike the rest of the migrated surface: every commons entry
  // point takes a rac_voice_agent_handle_t. The handle stays in `NativeBackend`
  // and the renderer sees an opaque session id, the same arrangement RAG uses.
  voiceOpen(configBytes: Uint8Array): Promise<string>;
  voiceInitialize(session: string, configBytes: Uint8Array): Promise<Uint8Array>;
  voiceStates(session: string): Promise<Uint8Array>;
  /** One captured frame in; a VoiceAgentResult out, empty unless a turn closed. */
  voiceFeed(session: string, frameBytes: Uint8Array): Promise<Uint8Array>;
  /** One complete utterance as raw PCM16 in, one finished turn out. */
  voiceTurn(session: string, pcm16: Uint8Array): Promise<Uint8Array>;
  voiceProcessTurn(
    session: string,
    requestBytes: Uint8Array,
    onEvent: (eventBytes: Uint8Array) => void
  ): Promise<void>;
  voiceCancelTurn(session: string, requestBytes: Uint8Array): Promise<void>;
  /** Every VoiceEvent the agent emits; resolves when the session closes. */
  voiceEvents(session: string, onEvent: (eventBytes: Uint8Array) => void): Promise<void>;
  voiceClose(session: string): Promise<void>;

  // ---- stt ----
  sttTranscribe(pcm16: Uint8Array, options: NativeSttOptions): Promise<NativeTranscription>;
  sttTranscribeStream(
    pcm16: Uint8Array,
    options: NativeSttOptions,
    onPartial: (p: NativeSttPartial) => void
  ): Promise<void>;
  sttInfo(): Promise<NativeSttInfo>;

  // ---- tts ----
  ttsSynthesize(text: string, options: NativeTtsOptions): Promise<NativeAudio>;
  ttsSynthesizeStream(
    text: string,
    options: NativeTtsOptions,
    onChunk: (c: NativeAudioChunk) => void
  ): Promise<void>;
  ttsStop(): Promise<void>;
  ttsInfo(): Promise<NativeTtsInfo>;

  // ---- vad ----
  vadOpen(config: NativeVadConfig): Promise<void>;
  vadProcess(samples: Float32Array): Promise<boolean>;
  vadReset(): Promise<void>;
  vadClose(): Promise<void>;
  /** Register SPEECH_ACTIVITY stream callback (sync on native; RPC may await). */
  vadSetStreamCallback(onEvent: (eventBytes: Uint8Array) => void): void | Promise<void>;
  vadUnsetStreamCallback(): Promise<void>;
  vadStreamStart(optionsBytes: Uint8Array): Promise<number>;
  vadStreamFeed(sessionId: number, audioBytes: Uint8Array): Promise<void>;
  vadStreamStop(sessionId: number): Promise<void>;
  vadStreamCancel(sessionId: number): Promise<void>;

  // ---- embeddings / rerank / diarization / segmentation over the proto ABI ----
  //
  // Embeddings, diarization, and segmentation read the lifecycle-loaded model.
  // Rerank is the exception: commons exposes only the component-handle form
  // (rac_rerank_component_rerank_proto), so the backend supplies the handle.
  embedBatchProto(requestBytes: Uint8Array): Promise<Uint8Array>;
  rerankProto(requestBytes: Uint8Array): Promise<Uint8Array>;
  diarizeProto(requestBytes: Uint8Array): Promise<Uint8Array>;
  segmentProto(requestBytes: Uint8Array): Promise<Uint8Array>;

  // ---- embeddings and rerank ----
  embed(texts: string[], options: NativeEmbedOptions): Promise<Float32Array[]>;
  rerank(query: string, documents: string[], topN?: number): Promise<NativeRanked[]>;

  /**
   * Sync commons vector math (`rac_embeddings_norm` / `rac_embeddings_similarity`)
   * owned by the process that holds the native addon. Always Promise-shaped so
   * the preload can RPC them; NativeBackend resolves immediately.
   */
  embeddingsNorm(vector: Float32Array): Promise<number>;
  embeddingsSimilarity(lhs: Float32Array, rhs: Float32Array): Promise<number>;

  /**
   * Sync commons audio DSP (`rac_audio_*`) owned by the process that holds the
   * native addon. Preload/renderer must reach these over RPC — never by loading
   * `runanywhere_native.node` in the renderer.
   */
  audioFloat32ToPcm16(samples: Float32Array): Promise<Int16Array>;
  audioPcm16ToFloat32(samples: Int16Array): Promise<Float32Array>;
  audioResampleF32(
    samples: Float32Array,
    inRate: number,
    outRate: number
  ): Promise<Float32Array>;
  audioComputeRms(samples: Float32Array): Promise<number>;
  audioFloat32ToWav(samples: Float32Array, sampleRate: number): Promise<Uint8Array>;
  audioWavToFloat32(
    bytes: Uint8Array
  ): Promise<{ sampleRate: number; samples: Float32Array }>;
  audioPcmBytesToMs(
    byteCount: number,
    format: { sampleRate: number; channels?: number; bitsPerSample?: number }
  ): Promise<number>;

  // ---- diarization and segmentation ----
  diarize(samples: Float32Array, options: NativeDiarizationOptions): Promise<NativeDiarization>;
  segment(
    image: { data: Uint8Array; width: number; height: number; pixelFormat?: number },
    options: { includeDiagnosticImage?: boolean }
  ): Promise<NativeSegmentation>;

  // ---- model lifecycle and registry (proto bytes in, proto bytes out) ----
  //
  // Commons owns which model is resident and what the registry contains; these are
  // pass-throughs so the typed decode happens once, in `model-abi.ts`.
  modelLoad(requestBytes: Uint8Array): Promise<Uint8Array>;
  modelResolvePaths(requestBytes: Uint8Array): Promise<Uint8Array>;
  modelUnload(requestBytes: Uint8Array): Promise<Uint8Array>;
  modelCurrent(requestBytes: Uint8Array): Promise<Uint8Array>;
  modelRegistryRegister(modelInfoBytes: Uint8Array): Promise<Uint8Array>;
  modelRegistryUpdate(modelInfoBytes: Uint8Array): Promise<Uint8Array>;
  modelRegistryGet(requestBytes: Uint8Array): Promise<Uint8Array>;
  modelRegistryList(requestBytes: Uint8Array): Promise<Uint8Array>;
  modelRegistryRemove(modelId: string): Promise<Uint8Array>;
  modelRegistryRefresh(requestBytes: Uint8Array): Promise<Uint8Array>;
  modelRegistryDiscover(requestBytes: Uint8Array): Promise<Uint8Array>;
  /** ModelCompatibilityRequest bytes in, ModelCompatibilityResult bytes out. */
  modelCompatibility(requestBytes: Uint8Array): Promise<Uint8Array>;
  modelRegisterFromUrl(requestBytes: Uint8Array): Promise<Uint8Array>;
  modelRegisterMultiFile(requestBytes: Uint8Array): Promise<Uint8Array>;

  // ---- llm over the proto ABI (proto bytes in, proto bytes out) ----
  //
  // Handle-free: commons resolves the model the lifecycle load made resident.
  // The typed decode happens once, in `llm-abi.ts`.
  llmGenerateProto(requestBytes: Uint8Array): Promise<Uint8Array>;
  llmGenerateStreamProto(
    requestBytes: Uint8Array,
    onEvent: (eventBytes: Uint8Array) => void
  ): Promise<void>;
  llmCancelProto(): Promise<Uint8Array>;
  structuredGenerate(requestBytes: Uint8Array): Promise<Uint8Array>;
  structuredParse(requestBytes: Uint8Array): Promise<Uint8Array>;
  structuredValidate(requestBytes: Uint8Array): Promise<Uint8Array>;

  // ---- tool calling (the commons run loop, with a host executor) ----
  //
  // ToolCallingSessionCreateRequest bytes in, ToolCallingResult bytes out.
  // `onEvent` is the only duplex operation in this contract: commons blocks its
  // loop on the reply, so a `toolCall` event must resolve to ToolResult bytes.
  toolRunLoop(
    requestBytes: Uint8Array,
    onEvent: (event: ToolRunLoopEvent) => Promise<Uint8Array | undefined>
  ): Promise<Uint8Array>;
  toolRunLoopCancel(handle: number): Promise<void>;

  // ---- rag (proto bytes in, proto bytes out; sessions keyed by opaque id) ----
  ragOpen(configBytes: Uint8Array): Promise<string>;
  ragIngest(session: string, documentBytes: Uint8Array): Promise<Uint8Array>;
  ragQuery(session: string, queryBytes: Uint8Array): Promise<Uint8Array>;
  ragSearch(session: string, requestBytes: Uint8Array): Promise<Uint8Array>;
  ragQueryStream(
    session: string,
    queryBytes: Uint8Array,
    onEvent: (eventBytes: Uint8Array) => void
  ): Promise<void>;
  ragStats(session: string): Promise<Uint8Array>;
  ragClear(session: string): Promise<Uint8Array>;
  ragCancel(session: string): Promise<void>;
  ragClose(session: string): Promise<void>;

  // ---- secure store ----
  secureSet(key: string, value: string): Promise<void>;
  secureGet(key: string): Promise<string | null>;
  secureDelete(key: string): Promise<void>;
}

/**
 * Backend operations whose last argument is a per-chunk callback. The RPC
 * transport needs to know which ones stream; the allowlist is derived from the
 * union of this set and {@link BACKEND_METHODS}.
 */
export const BACKEND_STREAMING_METHODS: ReadonlySet<string> = new Set([
  'resolveModel',
  'llmGenerate',
  'llmGenerateStreamProto',
  'vlmStreamProto',
  'sttTranscribeStream',
  'sttTranscribeStreamProto',
  'ttsSynthesizeStream',
  'ttsSynthesizeStreamProto',
  'voiceEvents',
  'voiceProcessTurn',
  'ragQueryStream',
  'downloadWatch',
  'vadSetStreamCallback',
]);

/** Every backend operation name, used to build the RPC allowlist. */
export const BACKEND_METHODS: readonly string[] = [
  'version',
  'initialize',
  'shutdown',
  'hasControlPlane',
  'devicePersistentId',
  'devStagingBaseUrl',
  'configureControlPlane',
  'retryControlPlane',
  'authState',
  'clearAuth',
  'telemetryFlush',
  'resolveModel',
  'modelStatus',
  'pathExists',
  'storage',
  'deleteModel',
  'registerModel',
  'downloadPlan',
  'downloadStart',
  'downloadCancel',
  'downloadProgress',
  'downloadCleanup',
  'downloadProgressPercent',
  'downloadWatch',
  'downloadUnwatch',
  'storageInfoProto',
  'storageAvailabilityProto',
  'storageDeletePlanProto',
  'storageDeleteProto',
  'ensure',
  'loaded',
  'unload',
  'memoryInfo',
  'modelLoad',
  'modelResolvePaths',
  'modelUnload',
  'modelCurrent',
  'modelRegistryRegister',
  'modelRegistryUpdate',
  'modelRegistryGet',
  'modelRegistryList',
  'modelRegistryRemove',
  'modelRegistryRefresh',
  'modelRegistryDiscover',
  'modelCompatibility',
  'modelRegisterFromUrl',
  'modelRegisterMultiFile',
  'llmGenerate',
  'llmCancel',
  'llmGenerateProto',
  'llmGenerateStreamProto',
  'llmCancelProto',
  'structuredGenerate',
  'structuredParse',
  'structuredValidate',
  'toolRunLoop',
  'toolRunLoopCancel',
  'loraApply',
  'loraRemove',
  'loraList',
  'loraApplyProto',
  'loraRemoveProto',
  'loraStateProto',
  'vlmGenerateProto',
  'vlmStreamProto',
  'vlmCancelProto',
  'sttTranscribe',
  'sttTranscribeStream',
  'sttInfo',
  'sttTranscribeProto',
  'sttTranscribeStreamProto',
  'sttStateProto',
  'ttsSynthesizeProto',
  'ttsSynthesizeStreamProto',
  'ttsStopProto',
  'ttsListVoicesProto',
  'ttsStateProto',
  'vadProcessProto',
  'vadConfigureProto',
  'vadStartProto',
  'vadStopProto',
  'vadResetProto',
  'voiceOpen',
  'voiceInitialize',
  'voiceStates',
  'voiceFeed',
  'voiceTurn',
  'voiceProcessTurn',
  'voiceCancelTurn',
  'voiceEvents',
  'voiceClose',
  'ttsSynthesize',
  'ttsSynthesizeStream',
  'ttsStop',
  'ttsInfo',
  'vadOpen',
  'vadProcess',
  'vadReset',
  'vadClose',
  'vadSetStreamCallback',
  'vadUnsetStreamCallback',
  'vadStreamStart',
  'vadStreamFeed',
  'vadStreamStop',
  'vadStreamCancel',
  'embed',
  'rerank',
  'embeddingsNorm',
  'embeddingsSimilarity',
  'audioFloat32ToPcm16',
  'audioPcm16ToFloat32',
  'audioResampleF32',
  'audioComputeRms',
  'audioFloat32ToWav',
  'audioWavToFloat32',
  'audioPcmBytesToMs',
  'diarize',
  'segment',
  'embedBatchProto',
  'rerankProto',
  'diarizeProto',
  'segmentProto',
  'ragOpen',
  'ragIngest',
  'ragQuery',
  'ragSearch',
  'ragQueryStream',
  'ragStats',
  'ragClear',
  'ragCancel',
  'ragClose',
  'secureSet',
  'secureGet',
  'secureDelete',
];

/** RPC method name for a backend operation (namespaced so it cannot collide). */
export function rpcMethodFor(op: string): string {
  return `v3.${op}`;
}
