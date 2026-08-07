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

/** Everything a v3 namespace needs from its host. */
export interface RaBackend {
  // ---- lifecycle ----
  version(): Promise<string>;
  initialize(opts: { secureDir?: string; baseDir?: string }): Promise<void>;
  shutdown(): Promise<void>;

  // ---- desktop control plane (telemetry + auth) ----
  /** Whether this build carries the desktop libcurl transport (auth + telemetry). */
  hasControlPlane(): Promise<boolean>;
  /** The persistent per-device UUID commons mints (empty if unavailable). */
  devicePersistentId(): Promise<string>;
  /** Baked staging backend URL for keyless development (empty when none). */
  devStagingBaseUrl(): Promise<string>;
  /** Register the transport, seed state, and run two-phase init. Returns SdkInitResult bytes. */
  configureControlPlane(req: ControlPlaneRequest): Promise<Uint8Array>;

  // ---- model store ----
  resolveModel(source: string, onProgress?: (p: DownloadProgress) => void): Promise<ResolvedModel>;
  modelStatus(): Promise<Record<string, { downloaded: boolean; sizeBytes: number }>>;
  pathExists(path: string): Promise<boolean>;
  storage(): Promise<StorageReport>;
  deleteModel(id: string): Promise<void>;
  registerModel(id: string, localPath: string, category: number, framework: number): Promise<void>;

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
  loraApply(adapterPath: string, scale: number): Promise<void>;
  loraRemove(adapterPath?: string): Promise<void>;
  loraList(): Promise<NativeLoraEntry[]>;

  // ---- vlm ----
  vlmGenerate(
    image: NativeImagePayload,
    prompt: string,
    options: NativeGenerateOptions,
    onToken: (token: string) => void
  ): Promise<NativeStreamResult>;
  vlmCancel(): Promise<void>;

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

  // ---- embeddings and rerank ----
  embed(texts: string[], options: NativeEmbedOptions): Promise<Float32Array[]>;
  rerank(query: string, documents: string[], topN?: number): Promise<NativeRanked[]>;

  // ---- diarization and segmentation ----
  diarize(samples: Float32Array, options: NativeDiarizationOptions): Promise<NativeDiarization>;
  segment(
    image: { data: Uint8Array; width: number; height: number; pixelFormat?: number },
    options: { includeDiagnosticImage?: boolean }
  ): Promise<NativeSegmentation>;

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
  'vlmGenerate',
  'sttTranscribeStream',
  'ttsSynthesizeStream',
  'ragQueryStream',
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
  'resolveModel',
  'modelStatus',
  'pathExists',
  'storage',
  'deleteModel',
  'registerModel',
  'ensure',
  'loaded',
  'unload',
  'llmGenerate',
  'llmCancel',
  'loraApply',
  'loraRemove',
  'loraList',
  'vlmGenerate',
  'vlmCancel',
  'sttTranscribe',
  'sttTranscribeStream',
  'sttInfo',
  'ttsSynthesize',
  'ttsSynthesizeStream',
  'ttsStop',
  'ttsInfo',
  'vadOpen',
  'vadProcess',
  'vadReset',
  'vadClose',
  'embed',
  'rerank',
  'diarize',
  'segment',
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
