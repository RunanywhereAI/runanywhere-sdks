/**
 * Result types of the v3 public API.
 *
 * Nothing here carries a `success` flag or an error message in a text field —
 * failures throw a typed [SDKException].
 */

import type { ModelCategory, ModelInfo } from '@runanywhere/proto-ts/model_types';
import type { ToolCall } from '@runanywhere/proto-ts/tool_calling';

/** Why generation stopped. */
export type FinishReason = 'stop' | 'length' | 'toolCalls' | 'cancelled';

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
}

/** Completed structured generation, with the parsed value alongside the raw text. */
export interface StructuredResult extends GenerationMetrics {
  value: unknown;
  raw: string;
  valid: boolean;
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

export type { ModelInfo };
