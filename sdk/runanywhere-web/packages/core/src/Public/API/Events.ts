/**
 * Event types of the v3 public API.
 *
 * One grammar throughout: `started`, then deltas, then `completed`. In-flight
 * failures throw into the consumer rather than arriving as an event — except on
 * long-lived sessions, which additionally emit a recoverable `error`.
 */

import type { ModelCategory } from '@runanywhere/proto-ts/model_types';
import type { ToolCall } from '@runanywhere/proto-ts/tool_calling';
import type {
  GenerationResult,
  ImageResult,
  Match,
  ModelInfo,
  RagResult,
  Transcription,
} from './Results.js';

/** Whether a streamed token is answer text or a thought. */
export type TokenKind = 'text' | 'thought';

/** Progress of one text generation. */
export type GenerationEvent =
  | { type: 'started'; requestId: string }
  | { type: 'token'; text: string; kind: TokenKind }
  | { type: 'toolCall'; toolCall: ToolCall }
  | { type: 'completed'; result: GenerationResult };

/** Progress of one streamed transcription. */
export type TranscriptionEvent =
  | { type: 'started' }
  | { type: 'partial'; text: string }
  | { type: 'final'; transcription: Transcription };

/** What a voice session is doing right now. */
export type AgentState = 'listening' | 'thinking' | 'speaking';

/** Progress of a live voice conversation. */
export type VoiceEvent =
  | { type: 'userTranscribed'; text: string; isFinal: boolean }
  | { type: 'agentStateChanged'; state: AgentState }
  | { type: 'agentResponse'; text: string }
  | { type: 'speechStarted' }
  | { type: 'speechEnded' }
  | { type: 'error'; message: string; recoverable: boolean };

/** Progress of one streamed RAG answer. */
export type RagEvent =
  | { type: 'retrieved'; matches: Match[] }
  | { type: 'token'; text: string; kind: TokenKind }
  | { type: 'completed'; result: RagResult };

/** Progress of one image generation. */
export type ImageEvent =
  | { type: 'started' }
  | { type: 'progress'; step: number; totalSteps: number; partialImage?: Uint8Array }
  | { type: 'completed'; result: ImageResult };

/** Progress of one model download. */
export type DownloadEvent =
  | { type: 'progress'; bytesDone: number; bytesTotal: number; percent: number }
  | { type: 'extracting' }
  | { type: 'completed'; model: ModelInfo };

/** Speech-detection deltas over a chunk stream. */
export type VadEvent =
  | { type: 'speechStarted'; timestampMs: number }
  | { type: 'speechEnded'; timestampMs: number; durationMs: number }
  | { type: 'activity'; isSpeech: boolean; probability: number; timestampMs: number };

/** Lifecycle, download, and error breadcrumbs of the whole SDK. */
export type SdkEvent =
  | { type: 'ready' }
  | { type: 'modelLoaded'; id: string; category: ModelCategory }
  | { type: 'modelUnloaded'; id: string }
  | { type: 'error'; message: string; recoverable: boolean };
