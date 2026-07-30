// types.ts — the v3 public vocabulary: enums, inputs, results, and events.
//
// Enum members are string constants rather than TypeScript `enum`s so every value
// survives a structured clone across the contextBridge unchanged — the renderer
// surface hands these exact objects to the page.

import { SDKException } from '../errors';

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

/** Deployment environment the SDK reports to the control plane. */
export const Environment = {
  DEVELOPMENT: 'development',
  STAGING: 'staging',
  PRODUCTION: 'production',
} as const;
export type Environment = (typeof Environment)[keyof typeof Environment];

/** Why generation stopped. */
export const FinishReason = {
  STOP: 'STOP',
  LENGTH: 'LENGTH',
  TOOL_CALLS: 'TOOL_CALLS',
  CANCELLED: 'CANCELLED',
} as const;
export type FinishReason = (typeof FinishReason)[keyof typeof FinishReason];

/** Whether a streamed token is answer text or model reasoning. */
export const TokenKind = { TEXT: 'TEXT', THOUGHT: 'THOUGHT' } as const;
export type TokenKind = (typeof TokenKind)[keyof typeof TokenKind];

/** Whether the model may think, and whether callers see the thoughts. */
export const ReasoningMode = { ON: 'ON', OFF: 'OFF' } as const;
export type ReasoningMode = (typeof ReasoningMode)[keyof typeof ReasoningMode];

/** How the model is allowed to use registered tools. */
export const ToolChoice = {
  AUTO: 'AUTO',
  NONE: 'NONE',
  REQUIRED: 'REQUIRED',
} as const;
export type ToolChoice =
  | (typeof ToolChoice)[keyof typeof ToolChoice]
  /** Force one specific tool by name. */
  | { forced: string };

/** Post-processing applied to an embedding vector. */
export const NormalizeMode = { NONE: 'NONE', L2: 'L2' } as const;
export type NormalizeMode = (typeof NormalizeMode)[keyof typeof NormalizeMode];

/** How token vectors collapse into one sentence vector. */
export const PoolingMode = { MEAN: 'MEAN', CLS: 'CLS', LAST: 'LAST' } as const;
export type PoolingMode = (typeof PoolingMode)[keyof typeof PoolingMode];

/** Whether an image request paints from scratch or fills a masked region. */
export const ImageMode = { GENERATE: 'GENERATE', INPAINT: 'INPAINT' } as const;
export type ImageMode = (typeof ImageMode)[keyof typeof ImageMode];

/** Container/encoding of an audio payload. */
export const AudioFormat = {
  PCM: 'PCM',
  WAV: 'WAV',
  MP3: 'MP3',
  OPUS: 'OPUS',
  AAC: 'AAC',
  FLAC: 'FLAC',
} as const;
export type AudioFormat = (typeof AudioFormat)[keyof typeof AudioFormat];

/** Which modality a model serves. */
export const ModelCategory = {
  LANGUAGE: 'LANGUAGE',
  VISION: 'VISION',
  EMBEDDING: 'EMBEDDING',
  SPEECH_TO_TEXT: 'SPEECH_TO_TEXT',
  TEXT_TO_SPEECH: 'TEXT_TO_SPEECH',
  VOICE_ACTIVITY: 'VOICE_ACTIVITY',
  RERANK: 'RERANK',
  DIARIZATION: 'DIARIZATION',
  SEGMENTATION: 'SEGMENTATION',
  IMAGE: 'IMAGE',
  LORA: 'LORA',
} as const;
export type ModelCategory = (typeof ModelCategory)[keyof typeof ModelCategory];

/** Engine that executes a model. */
export const InferenceFramework = {
  LLAMA_CPP: 'LLAMA_CPP',
  ONNX: 'ONNX',
  SHERPA: 'SHERPA',
} as const;
export type InferenceFramework =
  (typeof InferenceFramework)[keyof typeof InferenceFramework];

/** What an agent is doing during a voice turn. */
export const AgentState = {
  LISTENING: 'LISTENING',
  THINKING: 'THINKING',
  SPEAKING: 'SPEAKING',
} as const;
export type AgentState = (typeof AgentState)[keyof typeof AgentState];

// ---------------------------------------------------------------------------
// Inputs
// ---------------------------------------------------------------------------

/** Sample layout of a raw audio buffer. */
export interface AudioFormatSpec {
  encoding: AudioFormat;
  sampleRate: number;
  channels: number;
}

/** Audio handed to stt, vad, or diarization. Build one with {@link audio}. */
export interface AudioInput {
  /** PCM16 little-endian bytes, or the encoded file's bytes for WAV. */
  bytes?: Uint8Array;
  /** Float32 samples in [-1, 1]; takes precedence over `bytes` when present. */
  samples?: Float32Array;
  /** Path to an audio file on disk (WAV). */
  path?: string;
  format: AudioFormatSpec;
}

/** Constructors for {@link AudioInput}, one per source shape. */
export const audio = {
  /** Wrap little-endian PCM16 bytes. */
  pcm16(bytes: Uint8Array, sampleRate = 16000, channels = 1): AudioInput {
    return { bytes, format: { encoding: AudioFormat.PCM, sampleRate, channels } };
  },
  /** Wrap float32 samples in [-1, 1]. */
  float32(samples: Float32Array, sampleRate = 16000): AudioInput {
    return { samples, format: { encoding: AudioFormat.PCM, sampleRate, channels: 1 } };
  },
  /** Wrap the bytes of a RIFF/WAVE file. */
  wav(bytes: Uint8Array): AudioInput {
    return { bytes, format: { encoding: AudioFormat.WAV, sampleRate: 0, channels: 1 } };
  },
  /** Reference an audio file on disk. */
  file(path: string): AudioInput {
    return { path, format: { encoding: AudioFormat.WAV, sampleRate: 0, channels: 1 } };
  },
};

/** Image handed to vlm or segmentation. Build one with {@link image}. */
export interface ImageInput {
  /** Path to a JPEG/PNG on disk. */
  path?: string;
  /** Encoded image bytes (JPEG/PNG). */
  bytes?: Uint8Array;
  /** Packed 8-bit RGB pixels; needs `width` and `height`. */
  rgb?: Uint8Array;
  width?: number;
  height?: number;
}

/** Constructors for {@link ImageInput}, one per source shape. */
export const image = {
  /** Reference an image file on disk. */
  file(path: string): ImageInput {
    return { path };
  },
  /** Wrap encoded JPEG/PNG bytes. */
  bytes(data: Uint8Array): ImageInput {
    return { bytes: data };
  },
  /** Wrap packed 8-bit RGB pixels. */
  rawRgb(data: Uint8Array, width: number, height: number): ImageInput {
    return { rgb: data, width, height };
  },
};

/** Who authored a turn in a conversation. */
export const Role = {
  SYSTEM: 'system',
  USER: 'user',
  ASSISTANT: 'assistant',
  TOOL: 'tool',
} as const;
export type Role = (typeof Role)[keyof typeof Role];

/** One turn of a conversation. */
export interface ChatMessage {
  role: Role;
  content: string;
  /** Links a TOOL message back to the call it answers. */
  toolCallId?: string;
}

/** Points at a model, and for TTS optionally a voice inside it. */
export interface ModelRef {
  id: string;
  voice?: string;
}

/** A document to index into a RAG session. */
export interface RagDocument {
  text?: string;
  /** Read the document's text from this file instead of `text`. */
  path?: string;
  id?: string;
  metadata?: Record<string, string>;
}

/** Constructors for {@link RagDocument}. */
export const ragDocument = {
  /** Wrap in-memory text. */
  text(text: string, metadata?: Record<string, string>): RagDocument {
    return { text, metadata };
  },
  /** Read the document from a UTF-8 text file. */
  file(path: string): RagDocument {
    return { path };
  },
};

// ---------------------------------------------------------------------------
// Tools
// ---------------------------------------------------------------------------

/** JSON Schema subset the SDK can turn into a decoding grammar. */
export type { JsonSchema } from '../grammar';

/** A tool the model may call. */
export interface ToolDefinition {
  name: string;
  description?: string;
  /** JSON Schema (object) describing the call arguments. */
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  parameters: any;
}

/** A call the model asked for. */
export interface ToolCall {
  id: string;
  name: string;
  arguments: Record<string, unknown>;
  /** Present once the registered executor has run. */
  result?: Record<string, unknown>;
}

/** Runs a tool call's arguments and returns its result. */
export type ToolExecutor = (
  args: Record<string, unknown>
) => Record<string, unknown> | Promise<Record<string, unknown>>;

// ---------------------------------------------------------------------------
// Results
// ---------------------------------------------------------------------------

/** Throughput and token accounting carried by every generation result. */
export interface GenerationMetrics {
  inputTokens: number;
  outputTokens: number;
  timeToFirstTokenMs: number;
  tokensPerSecond: number;
  requestId: string;
  model: string;
}

/** A completed text (or vision) generation. */
export interface GenerationResult extends GenerationMetrics {
  text: string;
  /** The model's reasoning, when it emitted any and `reasoning` allowed it. */
  thinkingText?: string;
  toolCalls: ToolCall[];
  finishReason: FinishReason;
}

/** A completed schema-constrained generation. */
export interface StructuredResult<T = unknown> extends GenerationMetrics {
  value: T;
  raw: string;
  valid: boolean;
  finishReason: FinishReason;
}

/** One timed word of a transcript. */
export interface Word {
  text: string;
  startMs: number;
  endMs: number;
  confidence: number;
  speakerId?: string;
}

/** A completed transcription. */
export interface Transcription {
  text: string;
  language?: string;
  confidence: number;
  words: Word[];
  durationMs: number;
}

/** Synthesized speech. */
export interface Audio {
  data: Float32Array;
  sampleRate: number;
  format: AudioFormat;
  durationMs: number;
}

/** One chunk of a streamed synthesis. */
export interface AudioChunk {
  data: Float32Array;
  index: number;
  isFinal: boolean;
}

/** A span of speech within an audio input. */
export interface Segment {
  startMs: number;
  endMs: number;
}

/** Voice-activity decision over a whole audio input. */
export interface VadResult {
  isSpeech: boolean;
  probability: number;
  segments: Segment[];
}

/** One embedding vector, tagged with its position in the input list. */
export interface Embedding {
  index: number;
  vector: Float32Array;
}

/** One reranked document, pointing back at its input position. */
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

/** A completed image generation. */
export interface ImageResult {
  images: ImageData[];
  seed: number;
  steps: number;
}

/** One speaker's turn in a diarized recording. */
export interface SpeakerSegment {
  speakerId: string;
  startMs: number;
  endMs: number;
}

/** A completed diarization. */
export interface DiarizationResult {
  segments: SpeakerSegment[];
  speakerCount: number;
}

/** One class present in a segmentation mask. */
export interface ClassInfo {
  classId: number;
  label?: string;
  pixelCount: number;
  fraction: number;
}

/** A completed segmentation. */
export interface SegmentationResult {
  /** One class id per pixel, row-major. */
  classMask: Uint16Array;
  width: number;
  height: number;
  classes: ClassInfo[];
}

/** One retrieved chunk of a RAG corpus. */
export interface Match {
  text: string;
  score: number;
  metadata: Record<string, string>;
}

/** A completed grounded answer. */
export interface RagResult extends GenerationMetrics {
  answer: string;
  sources: Match[];
  thinkingText?: string;
}

/** Readiness of the speech-to-text stack. */
export interface SttState {
  isReady: boolean;
  modelId?: string;
  supportsStreaming: boolean;
  languages: string[];
}

/** A voice the loaded TTS model can speak with. */
export interface Voice {
  id: string;
  name: string;
  language: string;
}

/** A model known to the SDK. */
export interface ModelInfo {
  id: string;
  name: string;
  category: ModelCategory;
  framework?: InferenceFramework;
  /** Local path of the primary artifact, once downloaded. */
  localPath?: string;
  downloaded: boolean;
  sizeBytes: number;
  /** Parameter count as published, e.g. "1.5B". */
  parameters?: string;
}

/** What is loaded and how much room is left. */
export interface ModelsState {
  loaded: Partial<Record<ModelCategory, ModelInfo>>;
  storageUsedBytes: number;
  storageFreeBytes: number;
}

/** One adapter currently applied to the loaded LLM. */
export interface AppliedAdapter {
  id: string;
  scale: number;
}

/** Which adapters are applied. */
export interface LoraState {
  applied: AppliedAdapter[];
}

/** Size of a RAG index. */
export interface RagStats {
  documentCount: number;
  chunkCount: number;
  indexSizeBytes: number;
}

/** Narrows which models {@link ModelsNamespace.list} returns. */
export interface ModelFilter {
  category?: ModelCategory;
  downloadedOnly?: boolean;
}

/** Describes an artifact to add to the registry. */
export interface ModelRegistration {
  id?: string;
  category: ModelCategory;
  /** A single file, or the archive to extract. */
  url?: string;
  /** True when `url` points at a .tar.bz2 to extract in place. */
  archive?: boolean;
  /** Several files that make up one model, e.g. an ONNX plus its vocab. */
  files?: Array<{ url: string; as: string }>;
  /** A model already on disk. */
  path?: string;
  name?: string;
}

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

/** One step of a streamed generation: started, then deltas, then completed. */
export type GenerationEvent =
  | { type: 'started'; requestId: string }
  | { type: 'token'; text: string; kind: TokenKind }
  | { type: 'toolCall'; toolCall: ToolCall }
  | { type: 'completed'; result: GenerationResult };

/** One step of a streamed transcription. */
export type TranscriptionEvent =
  | { type: 'started' }
  | { type: 'partial'; text: string }
  | { type: 'final'; transcription: Transcription };

/** One step of a voice conversation. */
export type VoiceEvent =
  | { type: 'userTranscribed'; text: string; isFinal: boolean }
  | { type: 'agentStateChanged'; state: AgentState }
  | { type: 'agentResponse'; text: string }
  | { type: 'speechStarted' }
  | { type: 'speechEnded' }
  | { type: 'error'; message: string; recoverable: boolean };

/** One step of a streamed grounded answer. */
export type RagEvent =
  | { type: 'retrieved'; matches: Match[] }
  | { type: 'token'; text: string; kind: TokenKind }
  | { type: 'completed'; result: RagResult };

/** One step of a streamed image generation. */
export type ImageEvent =
  | { type: 'started' }
  | { type: 'progress'; step: number; totalSteps: number; partialImage?: ImageData }
  | { type: 'completed'; result: ImageResult };

/** One step of a model download. */
export type DownloadEvent =
  | { type: 'progress'; bytesDone: number; bytesTotal: number; percent: number }
  | { type: 'extracting' }
  | { type: 'completed'; model: ModelInfo };

/** A lifecycle, model, or error breadcrumb from the SDK itself. */
export type SdkEvent =
  | { type: 'ready' }
  | { type: 'modelLoaded'; id: string; category: ModelCategory }
  | { type: 'modelUnloaded'; id: string }
  | { type: 'error'; message: string; recoverable: boolean };

/** One frame of a streamed VAD pass. */
export type VadEvent =
  | { type: 'speechStarted'; atMs: number }
  | { type: 'speechEnded'; atMs: number; segment: Segment }
  | { type: 'frame'; isSpeech: boolean; probability: number; atMs: number };

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

let requestCounter = 0;

/** Fresh id correlating a request with its stream events and result. */
export function newRequestId(prefix = 'req'): string {
  requestCounter += 1;
  return `${prefix}_${Date.now().toString(36)}_${requestCounter.toString(36)}`;
}

/** Reject an input that carries none of its accepted payload shapes. */
export function requireOneOf(value: object, fields: string[], fieldPath: string): void {
  const present = fields.some((f) => (value as Record<string, unknown>)[f] != null);
  if (!present) {
    throw SDKException.validationFailed({
      fieldPath,
      message: `${fieldPath} needs one of: ${fields.join(', ')}`,
    });
  }
}
