// Public friendly types for the v3 surface, mirroring the Swift SDK's shapes.
// These are the values consumers see; the namespaces map them to and from the
// generated runanywhere.v1 protos so proto wire types never leak into the API.

/** Deployment environment. */
export enum Environment {
  DEVELOPMENT = 'development',
  STAGING = 'staging',
  PRODUCTION = 'production',
}

/** A chat turn's author. Mirrors Swift `ChatMessage.Role`. */
export enum Role {
  SYSTEM = 'system',
  USER = 'user',
  ASSISTANT = 'assistant',
  TOOL = 'tool',
}

/** One conversation turn. `toolCallId` is set on `tool` turns. */
export interface ChatMessage {
  role: Role;
  content: string;
  toolCallId?: string;
}

/** Why a generation ended. Mirrors Swift `FinishReason`. */
export enum FinishReason {
  STOP = 'stop',
  LENGTH = 'length',
  TOOL_CALLS = 'toolCalls',
  CANCELLED = 'cancelled',
}

/** A tool the model chose to call. */
export interface ToolCall {
  id: string;
  name: string;
  /** Raw JSON arguments string, as commons emitted it. */
  argumentsJson: string;
}

/** Names a model to load, optionally with a TTS voice id. Mirrors Swift `ModelRef`. */
export interface ModelRef {
  id: string;
  voice?: string;
}

/** Timing and token metrics for a completed generation. */
export interface GenerationMetrics {
  inputTokens: number;
  outputTokens: number;
  totalTokens: number;
  timeToFirstTokenMs: number;
  totalTimeMs: number;
  tokensPerSecond: number;
}

/** A completed generation. */
export interface GenerationResult {
  text: string;
  /** Extracted reasoning, when the model produced any. */
  thinking: string;
  /** Tools the model called during the run (empty when none). */
  toolCalls: ToolCall[];
  finishReason: string;
  metrics: GenerationMetrics;
}

/** What a streamed generation yields: token deltas, then a terminal result. */
export interface GenerationEvent {
  /** The token text (empty on the final event). */
  token: string;
  /** True on the terminal event, which carries `result`. */
  isFinal: boolean;
  /** Whether this delta is reasoning rather than answer text. */
  isThinking: boolean;
  /** Present only on the terminal event. */
  result?: GenerationResult;
}

/** One text's embedding vector. Mirrors Swift `Embedding`. */
export interface Embedding {
  index: number;
  vector: number[];
}

/** A reranked document: its position in the input list and its relevance. Mirrors Swift `RankedResult`. */
export interface RankedResult {
  index: number;
  relevanceScore: number;
}

/** A model as the registry reports it. */
export interface ModelInfo {
  id: string;
  name: string;
  /** Absolute path once downloaded, else empty. */
  localPath: string;
  downloaded: boolean;
}

/** Download progress for a model pull. */
export interface DownloadProgress {
  modelId: string;
  receivedBytes: number;
  totalBytes: number;
  /** 0..1. */
  fraction: number;
  stage: string;
}

/** Lifecycle and model breadcrumbs from {@link RunAnywhereApi.events}. */
export type SdkEvent =
  | { type: 'ready' }
  | { type: 'shutdown' }
  | { type: 'modelLoaded'; modality: string; id: string }
  | { type: 'modelUnloaded'; modality: string }
  | { type: 'error'; code: number; message: string };

/** A modality present in the surface but not usable in this build. */
export interface UnavailableCapability {
  name: string;
  reason: string;
}

/** Honest snapshot of what this build can reach. */
export interface SDKCapabilities {
  modalities: string[];
  /** GPU backend the addon was compiled with (metal/cuda/webgpu/cpu). */
  device: string;
  unavailable: UnavailableCapability[];
}

/**
 * Audio handed to stt/vad/diarization. The SDK converts to the PCM the proto
 * expects, mirroring Swift `AudioInput`. `file` and `wav` are decoded by commons.
 */
export type AudioInput =
  | { kind: 'pcm16'; samples: Int16Array; sampleRate: number; channels?: number }
  | { kind: 'float32'; samples: Float32Array; sampleRate: number; channels?: number }
  | { kind: 'wav'; bytes: Uint8Array }
  | { kind: 'file'; path: string };

/** Image handed to vlm/segmentation. Mirrors the Swift `ImageInput` cases the desktop build supports. */
export type ImageInput =
  | { kind: 'file'; path: string }
  | { kind: 'bytes'; data: Uint8Array }
  | { kind: 'rawRgb'; data: Uint8Array; width: number; height: number };

/** A step in a model pull. Mirrors Swift `DownloadEvent`. */
export type DownloadEvent =
  | { type: 'started'; modelId: string }
  | { type: 'progress'; modelId: string; receivedBytes: number; totalBytes: number; percent: number; file?: string }
  | { type: 'verifying' }
  | { type: 'extracting'; percent?: number }
  | { type: 'completed'; model: ModelInfo }
  | { type: 'failed'; message: string }
  | { type: 'cancelled' };

/** Filter for {@link ModelsNamespace.list}. */
export interface ModelFilter {
  category?: string;
  framework?: string;
  downloadedOnly?: boolean;
  search?: string;
}

/** A model resolved into a component. Mirrors Swift `LoadedModel`. */
export interface LoadedModel {
  id: string;
  category: string;
  actualBackend?: string;
  resolvedPath: string;
}

/** A snapshot of loaded models and storage. Mirrors Swift `ModelsState`. */
export interface ModelsState {
  loaded: { category: string; id: string }[];
  storageUsedBytes: number;
  storageFreeBytes: number;
}
