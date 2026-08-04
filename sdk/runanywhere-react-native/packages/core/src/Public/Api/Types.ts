/**
 * Public v3 surface types: options, inputs, results, and events.
 *
 * Option defaults are never written here — they are resolved from the
 * generated proto defaults in `Options.ts` so the IDL stays the only place a
 * default is declared.
 */

import type { SDKEnvironment } from '@runanywhere/proto-ts/model_types';
import type { ModelCategory, InferenceFramework, ModelInfo } from '@runanywhere/proto-ts/model_types';
import type { JSONSchema } from '@runanywhere/proto-ts/structured_output';
import type { ToolCall, ToolDefinition } from '@runanywhere/proto-ts/tool_calling';

export type { ModelCategory, InferenceFramework, ModelInfo };
export type { ToolCall, ToolDefinition };

/** Control-plane environment the SDK talks to. */
export type Environment = SDKEnvironment;

/** JSON schema describing a structured generation result. */
export type JsonSchema = JSONSchema;

// ---------------------------------------------------------------------------
// Core
// ---------------------------------------------------------------------------

/** Everything `initialize` needs; all fields are optional. */
export interface InitializeOptions {
  /** Omit for keyless local mode. */
  apiKey?: string;
  /** Omit to use the default control plane for the environment. */
  baseUrl?: string;
  environment?: Environment;
}

/** Lifecycle, download, and error breadcrumbs from the SDK. */
export type SdkEvent =
  | { type: 'ready' }
  | { type: 'modelLoaded'; id: string; category: ModelCategory }
  | { type: 'modelUnloaded'; id: string }
  | { type: 'error'; message: string; recoverable: boolean };

// ---------------------------------------------------------------------------
// Inputs
// ---------------------------------------------------------------------------

/** How the bytes in an {@link AudioInput} are laid out. */
export type AudioEncoding = 'pcm16' | 'float32' | 'container';

/** Audio bytes (or a file path) plus the format spec needed to decode them. */
export interface AudioInput {
  data?: Uint8Array;
  filePath?: string;
  encoding: AudioEncoding;
  sampleRate: number;
  channels: number;
}

/** Pixel layout of raw {@link ImageInput} bytes. */
export type ImagePixelFormat = 'rgb8' | 'rgba8' | 'bgra8';

/** An image supplied as a file path, encoded bytes, base64, or raw pixels. */
export interface ImageInput {
  filePath?: string;
  bytes?: Uint8Array;
  base64?: string;
  rawPixels?: Uint8Array;
  width?: number;
  height?: number;
  pixelFormat?: ImagePixelFormat;
}

/** Who authored a turn in a chat transcript. */
export type ChatRole = 'system' | 'user' | 'assistant' | 'tool';

/** One turn of a conversation. */
export interface ChatMessage {
  role: ChatRole;
  content: string;
  toolCallId?: string;
}

/** A model id plus, for TTS, the voice to speak with. */
export interface ModelRef {
  id: string;
  voice?: string;
}

/** A document to index into a RAG session. */
export interface RagDocument {
  text?: string;
  filePath?: string;
  id?: string;
  metadata?: Record<string, string>;
}

// ---------------------------------------------------------------------------
// Options
// ---------------------------------------------------------------------------

/** Whether the model may think, and whether thoughts reach the caller. */
export interface ReasoningOptions {
  mode?: 'on' | 'off';
  includeInOutput?: boolean;
  /** Custom thinking tag pattern; omit to use the model's own tags. */
  pattern?: string;
}

/** Schema-constrained output for a generation. */
export interface StructuredOutput {
  schema: JsonSchema;
  strict?: boolean;
}

/** How the model may use tools on this request. */
export type ToolChoice =
  | 'auto'
  | 'none'
  | 'required'
  | { forced: string };

/** Sampling, reasoning, and tool knobs for one generation. */
export interface LlmOptions {
  /** Model slug; an absent model auto-loads, downloading when needed. */
  model?: string;
  maxOutputTokens?: number;
  temperature?: number;
  topP?: number;
  topK?: number;
  minP?: number;
  frequencyPenalty?: number;
  presencePenalty?: number;
  repetitionPenalty?: number;
  seed?: number;
  stopSequences?: string[];
  systemPrompt?: string;
  reasoning?: ReasoningOptions;
  structuredOutput?: StructuredOutput;
  /** Leave empty to use the tools registered through `llm.tools`. */
  tools?: ToolDefinition[];
  toolChoice?: ToolChoice;
  maxToolCalls?: number;
}

/** Transcription knobs. */
export interface SttOptions {
  /** BCP-47 tag; omit to auto-detect. */
  language?: string;
  punctuation?: boolean;
  wordTimestamps?: boolean;
  diarization?: boolean;
  maxSpeakers?: number;
  translateToEnglish?: boolean;
}

/** Audio container of synthesized speech. */
export type AudioFormatName = 'pcm' | 'wav' | 'mp3' | 'opus' | 'flac' | 'aac';

/** Synthesis knobs. */
export interface TtsOptions {
  voice?: string;
  language?: string;
  speed?: number;
  pitch?: number;
  format?: AudioFormatName;
  sampleRate?: number;
}

/** Speech-detection knobs. */
export interface VadOptions {
  /**
   * Detector model slug; an absent model auto-loads, downloading when needed.
   *
   * Outside the v3 spec's `VadOptions`, which always uses the catalogued
   * default. Without it a caller with its own VAD choice would have to load the
   * model behind the SDK's back before opening a voice session.
   */
  model?: string;
  /** Omit to use the model's calibrated default. */
  activationThreshold?: number;
  minSpeechMs?: number;
  minSilenceMs?: number;
  prefixPaddingMs?: number;
}

/** Token pooling used to collapse an embedding sequence into one vector. */
export type PoolingMode = 'mean' | 'cls' | 'last';

/** Embedding knobs. */
export interface EmbedOptions {
  /** L2-normalize the output vectors. */
  normalize?: boolean;
  pooling?: PoolingMode;
}

/** Whether an image request generates fresh pixels or inpaints existing ones. */
export type ImageMode =
  | 'generate'
  | { inpaint: { input: ImageInput; mask: ImageInput } };

/** Image-generation knobs. */
export interface ImageOptions {
  negativePrompt?: string;
  width?: number;
  height?: number;
  steps?: number;
  guidanceScale?: number;
  seed?: number;
  mode?: ImageMode;
  reportPartials?: boolean;
}

/** Speaker-diarization knobs. */
export interface DiarizationOptions {
  threshold?: number;
  minimumDurationMs?: number;
  mergeGapMs?: number;
}

/** Image-segmentation knobs. */
export interface SegmentationOptions {
  includeDiagnosticImage?: boolean;
}

/** When a user's turn is considered over, and whether the agent can be cut off. */
export interface TurnHandlingOptions {
  endpointing?: { minDelayMs?: number; maxDelayMs?: number };
  interruption?: { enabled?: boolean; minDurationMs?: number };
}

/** Chunking, retrieval, and persistence knobs for a RAG session. */
export interface RagConfig {
  topK?: number;
  chunkSize?: number;
  chunkOverlap?: number;
  similarityThreshold?: number;
  persistPath?: string;
}

/** Placement knobs applied when a model is loaded. */
export interface LoadOptions {
  /** Engine pin, honoured at load time only. */
  framework?: InferenceFramework;
  contextLength?: number;
  threads?: number;
  useGpu?: boolean;
}

/** Narrows `models.list`. */
export interface ModelFilter {
  category?: ModelCategory;
  framework?: InferenceFramework;
  downloadedOnly?: boolean;
  availableOnly?: boolean;
  search?: string;
}

/** One file of a multi-file model registration. */
export interface ModelFile {
  url: string;
  filename: string;
  required?: boolean;
}

/** On-disk layout of an archived model. */
export type ArchiveLayout = 'singleFile' | 'directory' | 'nestedDirectory';

/** A model to add to the registry: single url, archive, or multi-file set. */
export interface ModelRegistration {
  name: string;
  id?: string;
  category?: ModelCategory;
  framework?: InferenceFramework;
  memoryRequirementBytes?: number;
  supportsThinking?: boolean;
  supportsLora?: boolean;
  /** Single-file download url. */
  url?: string;
  /** Archive download url; pair with `archiveLayout`. */
  archiveUrl?: string;
  archiveLayout?: ArchiveLayout;
  /** Multi-file bundle; requires `id`. */
  files?: ModelFile[];
  /**
   * Computer-Use-Agent profile id (e.g. `'fara'`) for a CUA-capable model.
   * Lands on `ModelInfo.cuaProfile` so callers can discover which registered
   * models are drivable through the CUA namespace.
   */
  cuaProfile?: string;
}

// ---------------------------------------------------------------------------
// Results
// ---------------------------------------------------------------------------

/** Why a generation stopped. */
export type FinishReason = 'stop' | 'length' | 'toolCalls' | 'cancelled';

/** Generated text plus the metrics every generation reports. */
export interface GenerationResult {
  text: string;
  thinkingText?: string;
  toolCalls: ToolCall[];
  finishReason: FinishReason;
  inputTokens: number;
  outputTokens: number;
  timeToFirstTokenMs: number;
  tokensPerSecond: number;
  requestId: string;
  model: string;
}

/** A parsed structured generation alongside its raw text and metrics. */
export interface StructuredResult<T = unknown> extends GenerationResult {
  value: T | null;
  raw: string;
  valid: boolean;
}

/** One recognized word with its timing. */
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
  data: Uint8Array;
  sampleRate: number;
  format: AudioFormatName;
  durationMs: number;
}

/** One chunk of a streamed synthesis. */
export interface AudioChunk {
  data: Uint8Array;
  index: number;
  isFinal: boolean;
}

/** A voice a TTS model can speak with. */
export interface Voice {
  id: string;
  name: string;
  language: string;
  gender?: 'male' | 'female' | 'neutral';
}

/** A span of detected speech. */
export interface Segment {
  startMs: number;
  endMs: number;
}

/** Speech-detection verdict for one audio buffer. */
export interface VadResult {
  isSpeech: boolean;
  probability: number;
  segments: Segment[];
}

/** One embedding vector, tagged with its position in the input list. */
export interface Embedding {
  index: number;
  vector: number[];
}

/** A rerank score pointing back at an input document. */
export interface RankedResult {
  index: number;
  relevanceScore: number;
}

/** One generated image. */
export interface ImageData {
  data: Uint8Array;
  width: number;
  height: number;
  mediaType?: string;
}

/** Generated images plus the settings that produced them. */
export interface ImageResult {
  images: ImageData[];
  seed: number;
  steps: number;
}

/** One speaker turn in a diarized recording. */
export interface SpeakerSegment {
  speakerId: string;
  startMs: number;
  endMs: number;
}

/** Speaker turns detected across a recording. */
export interface DiarizationResult {
  segments: SpeakerSegment[];
  speakerCount: number;
}

/** A class present in a segmentation mask. */
export interface ClassInfo {
  id: number;
  label: string;
  pixelCount: number;
  fraction: number;
}

/** Per-pixel class mask for an image. */
export interface SegmentationResult {
  /** One uint16 class id per pixel, row-major. */
  classMask: Uint16Array;
  width: number;
  height: number;
  classes: ClassInfo[];
  /** RGBA overlay, present only when `includeDiagnosticImage` was set. */
  diagnosticImage?: Uint8Array;
}

/** A retrieved chunk with its similarity score. */
export interface Match {
  text: string;
  score: number;
  metadata: Record<string, string>;
}

/** A grounded answer plus its sources and generation metrics. */
export interface RagResult extends GenerationResult {
  answer: string;
  sources: Match[];
}

/** Readiness of the speech-recognition component. */
export interface SttState {
  isReady: boolean;
  modelId?: string;
  supportsStreaming: boolean;
  languages: string[];
}

/** What is loaded and how much room is left. */
export interface ModelsState {
  loaded: Partial<Record<ModelCategory, ModelInfo>>;
  storageUsedBytes: number;
  storageFreeBytes: number;
}

/** A LoRA adapter currently mixed into the loaded model. */
export interface AppliedAdapter {
  id: string;
  scale: number;
}

/** The adapters currently applied. */
export interface LoraState {
  applied: AppliedAdapter[];
}

/** Index counters for a RAG session. */
export interface RagStats {
  documentCount: number;
  chunkCount: number;
  indexSizeBytes: number;
}

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

/** Whether a streamed token is answer text or private reasoning. */
export type TokenKind = 'text' | 'thought';

/** `started`, then deltas, then `completed`. */
export type GenerationEvent =
  | { type: 'started'; requestId: string }
  | { type: 'token'; text: string; kind: TokenKind }
  | { type: 'toolCall'; toolCall: ToolCall }
  | { type: 'completed'; result: GenerationResult };

/** `started`, then partials, then `final`. */
export type TranscriptionEvent =
  | { type: 'started' }
  | { type: 'partial'; text: string }
  | { type: 'final'; transcription: Transcription };

/** Frame-level speech detection. */
export type VadEvent =
  | { type: 'speechStarted' }
  | { type: 'speechEnded' }
  | { type: 'frame'; result: VadResult };

/** What the agent is doing right now. */
export type AgentState = 'listening' | 'thinking' | 'speaking';

/** Turn-by-turn progress of a voice session. */
export type VoiceEvent =
  | { type: 'userTranscribed'; text: string; isFinal: boolean }
  | { type: 'agentStateChanged'; state: AgentState }
  | { type: 'agentResponse'; text: string }
  | { type: 'speechStarted' }
  | { type: 'speechEnded' }
  | { type: 'error'; message: string; recoverable: boolean };

/** Retrieval, then answer deltas, then `completed`. */
export type RagEvent =
  | { type: 'retrieved'; matches: Match[] }
  | { type: 'token'; text: string; kind: TokenKind }
  | { type: 'completed'; result: RagResult };

/** Diffusion progress, then `completed`. */
export type ImageEvent =
  | { type: 'started' }
  | {
      type: 'progress';
      step: number;
      totalSteps: number;
      partialImage?: ImageData;
    }
  | { type: 'completed'; result: ImageResult };

/** Byte progress, optional extraction, then `completed`. */
export type DownloadEvent =
  | { type: 'progress'; bytesDone: number; bytesTotal: number; percent: number }
  | { type: 'extracting' }
  | { type: 'completed'; model: ModelInfo };

// ---------------------------------------------------------------------------
// Sessions
// ---------------------------------------------------------------------------

/** A live voice conversation that owns its models, microphone, and playback. */
export interface VoiceSession {
  /** Turn events for this session; subscribing never opens the microphone. */
  readonly events: AsyncIterable<VoiceEvent>;
  /** Open the microphone and begin the turn loop. */
  start(): Promise<void>;
  /** Speak this text now, outside the turn loop. */
  say(text: string): Promise<void>;
  /** Stop the agent mid-utterance. */
  interrupt(): Promise<void>;
  /** Release the microphone, playback, and the underlying pipeline. */
  close(): Promise<void>;
}

/** A retrieval corpus with optional grounded generation over it. */
export interface RagSession {
  /** Chunk, embed, and index one document or a batch of them. */
  ingest(document: RagDocument | RagDocument[]): Promise<void>;
  /** Chunk, embed, and index a batch; the same work as `ingest` on an array. */
  ingestAll(documents: RagDocument[]): Promise<void>;
  /** Retrieve the closest chunks without generating an answer. */
  search(query: string, topK?: number): Promise<Match[]>;
  /** Answer a question grounded in the indexed chunks. */
  query(question: string, options?: LlmOptions): Promise<RagResult>;
  /** Answer a question, streaming retrieval and answer tokens. */
  queryStream(question: string, options?: LlmOptions): AsyncIterable<RagEvent>;
  /** Index counters for this session. */
  stats(): Promise<RagStats>;
  /** Drop every indexed chunk, keeping the session open. */
  clear(): Promise<void>;
  /** Release the session and its index. */
  close(): Promise<void>;
}

/** Executes one tool call for the LLM and returns its result payload. */
export type ToolExecutor = (
  args: Record<string, unknown>
) => Promise<Record<string, unknown>>;
