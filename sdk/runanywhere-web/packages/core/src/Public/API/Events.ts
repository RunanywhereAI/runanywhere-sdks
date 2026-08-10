/**
 * Event types of the v4 public API.
 *
 * One grammar throughout: `started`, then deltas, then a terminal
 * `completed`/`failed`/`cancelled`. Streams never fabricate a successful
 * `completed` — an in-flight failure is a `failed` event (or, where the
 * language stream cannot carry a typed terminal, a thrown exception), and a
 * stream that ends without a terminal signal simply stops. Long-lived
 * sessions (`VoiceSession`, `RunAnywhere.events`) additionally emit a
 * recoverable `error` breadcrumb for per-component trouble.
 */

import type { ModelCategory } from '@runanywhere/proto-ts/model_types';
import type { ToolCall } from '@runanywhere/proto-ts/tool_calling';
import type { TokenUsage } from '@runanywhere/proto-ts/token_usage';
import type { Backend } from './Options.js';
import type {
  GenerationResult,
  ImageResult,
  Match,
  RagResult,
  Transcription,
} from './Results.js';
import type { ProtoSDKError as SDKError } from '../../Foundation/SDKException.js';

/** Whether a streamed delta is answer text or a thought. */
export type TokenKind = 'text' | 'thought';

/** One alternative transcript for a still-revising partial segment. */
export interface TranscriptAlternative {
  text: string;
  confidence?: number;
}

/** Progress of one text generation (`llm`/`vlm` `generateStream`). */
export type GenerationEvent =
  | { type: 'started'; requestId: string }
  | {
      type: 'outputItemAdded';
      requestId: string;
      sequence: number;
      itemId: string;
      index: number;
      item: unknown;
    }
  | {
      type: 'textDelta';
      requestId: string;
      sequence: number;
      itemId: string;
      index: number;
      text: string;
    }
  | {
      type: 'reasoningDelta';
      requestId: string;
      sequence: number;
      itemId: string;
      index: number;
      text: string;
    }
  | {
      type: 'toolCallAdded';
      requestId: string;
      sequence: number;
      itemId: string;
      index: number;
      call: ToolCall;
    }
  | {
      type: 'toolArgumentsDelta';
      requestId: string;
      sequence: number;
      itemId: string;
      delta: string;
    }
  | {
      type: 'toolArgumentsDone';
      requestId: string;
      sequence: number;
      itemId: string;
      arguments: string;
    }
  | { type: 'usage'; requestId: string; sequence: number; usage: TokenUsage }
  | { type: 'completed'; requestId: string; result: GenerationResult }
  | { type: 'failed'; requestId: string; partial?: Partial<GenerationResult>; error: SDKError }
  | { type: 'cancelled'; requestId: string; partial?: Partial<GenerationResult> };

/** Progress of one streamed transcription (`stt.openStream`). */
export type TranscriptionEvent =
  | { type: 'started'; requestId: string }
  | { type: 'speechStarted'; requestId: string; sequence: number; timestampMs?: number }
  | {
      type: 'partial';
      requestId: string;
      sequence: number;
      segmentId: string;
      revision: number;
      alternatives: TranscriptAlternative[];
    }
  | { type: 'transcriptFinal'; requestId: string; sequence: number; segment: Transcription }
  | { type: 'speechEnded'; requestId: string; sequence: number; timestampMs?: number }
  | { type: 'usage'; requestId: string; sequence: number; usage: TokenUsage }
  | { type: 'completed'; requestId: string }
  | { type: 'failed'; requestId: string; error: SDKError }
  | { type: 'cancelled'; requestId: string };

/** What a voice session is doing right now. */
export type AgentState = 'listening' | 'thinking' | 'speaking';

/** Progress of a live voice conversation. */
export type VoiceEvent =
  | { type: 'userTranscribed'; text: string; isFinal: boolean; requestId?: string }
  | { type: 'agentStateChanged'; state: AgentState }
  | { type: 'agentResponse'; text: string; speechId?: string }
  | { type: 'speechStarted'; speechId?: string }
  | { type: 'speechEnded'; speechId?: string }
  | { type: 'error'; message: string; recoverable: boolean; source?: string; code?: string };

/** Progress of one streamed RAG answer. */
export type RagEvent =
  | { type: 'retrieved'; matches: Match[] }
  | { type: 'textDelta'; text: string; kind: TokenKind }
  | { type: 'completed'; result: RagResult }
  | { type: 'failed'; error: SDKError };

/** Progress of one image generation. */
export type ImageEvent =
  | { type: 'started' }
  | { type: 'progress'; step: number; totalSteps: number; partialImage?: Uint8Array }
  | { type: 'completed'; result: ImageResult }
  | { type: 'failed'; error: SDKError };

/** Progress of one model download, correlated by `operationId`/`sequence`. */
export type DownloadEvent =
  | { type: 'started'; operationId: string; sequence: number }
  | {
      type: 'progress';
      operationId: string;
      sequence: number;
      bytesDone: number;
      bytesTotal: number;
      file?: string;
    }
  | { type: 'verifying'; operationId: string; sequence: number }
  | { type: 'extracting'; operationId: string; sequence: number; percent?: number }
  | { type: 'completed'; operationId: string; sequence: number; modelId: string }
  | { type: 'failed'; operationId: string; sequence: number; error: SDKError }
  | { type: 'cancelled'; operationId: string; sequence: number };

/** Speech-detection deltas over a chunk stream (`vad.openStream`). */
export type VadEvent =
  | { type: 'speechStarted'; timestampMs?: number }
  | { type: 'speechEnded'; timestampMs?: number }
  | { type: 'activity'; isSpeech: boolean; probability: number; timestampMs?: number }
  | { type: 'failed'; error: SDKError }
  | { type: 'completed' };

/** Lifecycle, download, and error breadcrumbs of the whole SDK. */
export type SdkEvent =
  | { type: 'ready' }
  | { type: 'modelLoaded'; id: string; category: ModelCategory; actualBackend?: Backend }
  | { type: 'modelUnloaded'; id: string }
  | { type: 'error'; message: string; recoverable: boolean; source?: string; code?: string };
