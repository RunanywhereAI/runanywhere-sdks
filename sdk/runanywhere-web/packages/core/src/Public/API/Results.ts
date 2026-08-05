/**
 * Result types of the v4 public API.
 *
 * Nothing here carries a `success` flag or an error message in a text field —
 * failures throw a typed [SDKException].
 */

import type { ModelCategory, ModelInfo } from '@runanywhere/proto-ts/model_types';
import type { ToolCall } from '@runanywhere/proto-ts/tool_calling';
import type { ProtoSDKError } from '../../Foundation/SDKException.js';
import type { AudioFrame } from './Inputs.js';
import type { Backend, BackendPreference, StructuredOutputMode } from './Options.js';
import type { TranscriptionEvent, VadEvent } from './Events.js';

/** Why generation stopped. */
export type FinishReason = 'stop' | 'length' | 'toolCalls' | 'cancelled' | 'contentFilter' | 'unknown';

/** Throughput and token accounting shared by every generation result. */
export interface GenerationMetrics {
  inputTokens: number;
  outputTokens: number;
  timeToFirstTokenMs: number;
  tokensPerSecond: number;
  requestId: string;
  model: string;
}

/** Completed text generation. */
export interface GenerationResult extends GenerationMetrics {
  text: string;
  thinkingText?: string;
  toolCalls: ToolCall[];
  finishReason: FinishReason;
  /** Backend-native finish-reason string, before normalization into [FinishReason]. */
  rawFinishReason?: string;
  actualBackend?: Backend;
  actualDevice?: string;
}

/** Completed structured generation, with the parsed value alongside the raw text. */
export interface StructuredResult extends GenerationMetrics {
  value: unknown;
  raw: string;
  valid: boolean;
  mode: StructuredOutputMode;
}

/** One recognized word of a transcription. */
export interface Word {
  text: string;
  startMs: number;
  endMs: number;
  confidence: number;
  speakerId?: string;
}

/** Completed transcription. */
export interface Transcription {
  text: string;
  language?: string;
  confidence: number;
  words: Word[];
  durationMs: number;
}

/** Synthesized audio. */
export interface Audio {
  data: Uint8Array;
  sampleRate: number;
  format: 'pcm' | 'pcm16' | 'wav';
  durationMs: number;
}

/** One chunk of a streamed synthesis. */
export interface AudioChunk {
  data: Uint8Array;
  index: number;
  isFinal: boolean;
}

/** A span of detected speech. */
export interface Segment {
  startMs: number;
  endMs: number;
}

/** Speech-detection verdict for one audio payload. */
export interface VadResult {
  isSpeech: boolean;
  probability: number;
  segments: Segment[];
}

/** One embedding, tagged with the index of its input text. */
export interface Embedding {
  index: number;
  vector: Float32Array;
}

/** One reranked document, pointing back at its input index. */
export interface RankedResult {
  index: number;
  relevanceScore: number;
}

/** One generated image. */
export interface ImageData {
  bytes: Uint8Array;
  width: number;
  height: number;
}

/** Completed image generation. */
export interface ImageResult {
  images: ImageData[];
  seed: number;
  steps: number;
}

/** One diarized span attributed to a speaker. */
export interface SpeakerSegment {
  speakerId: string;
  startMs: number;
  endMs: number;
}

/** Completed speaker diarization. */
export interface DiarizationResult {
  segments: SpeakerSegment[];
  speakerCount: number;
}

/** One class present in a segmentation mask. */
export interface ClassInfo {
  id: number;
  label: string;
  pixelCount: number;
  fraction: number;
}

/** Completed semantic segmentation. */
export interface SegmentationResult {
  /** Per-pixel class ids, u16 little-endian, row-major. */
  classMask: Uint8Array;
  width: number;
  height: number;
  classes: ClassInfo[];
  /** RGBA preview, present when `includeDiagnosticImage` was set. */
  diagnosticImage?: Uint8Array;
}

/** One retrieved chunk of a RAG corpus. */
export interface Match {
  text: string;
  score: number;
  metadata: Record<string, string>;
}

/** Completed RAG answer with the context it was grounded in. */
export interface RagResult extends GenerationMetrics {
  answer: string;
  sources: Match[];
}

/** Readiness of the loaded speech-to-text model. */
export interface SttState {
  isReady: boolean;
  modelId?: string;
  supportsStreaming: boolean;
  languages: string[];
}

/** One voice the loaded synthesis model can render. */
export interface Voice {
  id: string;
  name: string;
  language: string;
  isNeural: boolean;
}

/** What is resident and how much room is left. */
export interface ModelsState {
  loaded: Partial<Record<ModelCategory, ModelInfo>>;
  storageUsedBytes: number;
  storageFreeBytes: number;
}

/** One applied LoRA adapter. */
export interface AppliedAdapter {
  id: string;
  scale: number;
}

/** Adapters currently layered onto the base model. */
export interface LoraState {
  applied: AppliedAdapter[];
}

/** Size of a RAG corpus. */
export interface RagStats {
  documentCount: number;
  chunkCount: number;
  indexSizeBytes: number;
}

/**
 * Ownership handle for one resident model, returned by `models.load`.
 *
 * `close()` and `models.unload(id)` release the same residency; calling
 * either after the other is a no-op.
 */
export interface LoadedModel {
  readonly id: string;
  readonly category: ModelCategory;
  /** The backend preference that was requested, when one was given. */
  readonly requestedBackend?: BackendPreference;
  readonly actualBackend: Backend;
  readonly actualDevice: string;
  readonly runtimeVersion?: string;
  readonly abiVersion?: string;
  /** Set when the requested backend/accelerator could not be honored. */
  readonly fallbackReason?: string;
  /** Release this model's residency. Idempotent. */
  close(): Promise<void>;
}

/**
 * Handle to one in-flight or completed `tts.speak`/`VoiceSession.say` utterance.
 */
export interface SpeechHandle {
  readonly id: string;
  readonly interrupted: boolean;
  readonly error?: ProtoSDKError;
  /** Stop playback and any in-flight synthesis. Resolves once stopped. */
  interrupt(): Promise<void>;
  /** Resolve once playback finishes, is interrupted, or fails. */
  waitForPlayout(): Promise<void>;
}

/**
 * Live speech-to-text session opened by `stt.openStream`. Establishes its
 * audio format once; every pushed frame carries PCM samples in that format.
 */
export interface SttStream {
  readonly events: AsyncIterable<TranscriptionEvent>;
  /** Push one frame of PCM audio in the stream's established format. */
  pushFrame(frame: AudioFrame): void;
  /** Request the backend surface partials for audio pushed so far. */
  flush(): void;
  /** Signal that no more audio is coming; the backend finalizes the transcript. */
  finish(): void;
  /** Release the stream's resources. Idempotent. */
  close(): Promise<void>;
}

/**
 * Live voice-activity session opened by `vad.openStream`. Establishes its
 * audio format once; every pushed frame carries PCM samples in that format.
 */
export interface VadStream {
  readonly events: AsyncIterable<VadEvent>;
  /** Push one frame of PCM audio in the stream's established format. */
  pushFrame(frame: AudioFrame): void;
  /** No-op on Web: there is no partial-result buffer to flush. */
  flush(): void;
  /** Signal that no more audio is coming; completes the event stream. */
  finish(): void;
  /** Release the stream's resources. Idempotent. */
  close(): Promise<void>;
}

/** Whether a modality/backend/feature is honestly available right now. */
export interface UnavailableCapability {
  name: string;
  reason: string;
}

/** Per-modality streaming support, keyed by namespace name. */
export interface StreamingCapabilities {
  llm: boolean;
  vlm: boolean;
  stt: boolean;
  tts: boolean;
  vad: boolean;
  rag: boolean;
  images: boolean;
}

/** Tool-calling support of the currently registered backends. */
export interface ToolCapabilities {
  registry: boolean;
  parallel: boolean;
  cancellation: boolean;
}

/** RAG-session support of the currently registered backends. */
export interface RagCapabilities {
  multiSession: boolean;
  persistent: boolean;
}

/**
 * Installed, packaged, and executable surface of this SDK build, generated
 * from packaging and runtime probes rather than from IDL enum presence
 * alone. `capabilities()` is the source of truth apps should consult before
 * calling into a modality that might not ship on this platform.
 */
export interface SDKCapabilities {
  modalities: string[];
  backends: Backend[];
  audioFormats: string[];
  streaming: StreamingCapabilities;
  tools: ToolCapabilities;
  rag: RagCapabilities;
  unavailable: UnavailableCapability[];
}

export type { ModelInfo };
