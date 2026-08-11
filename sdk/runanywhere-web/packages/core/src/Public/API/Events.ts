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
 *
 * Discriminated unions live in `@runanywhere/proto-ts/events/public_events`.
 * This module only binds the shared generics to Web's concrete result types
 * so the published public API shape stays local.
 */

import type {
  AgentState as CanonicalAgentState,
  DownloadEvent as CanonicalDownloadEvent,
  GenerationEvent as CanonicalGenerationEvent,
  ImageEvent as CanonicalImageEvent,
  RagEvent as CanonicalRagEvent,
  SdkEvent as CanonicalSdkEvent,
  TokenKind as CanonicalTokenKind,
  TranscriptAlternative as CanonicalTranscriptAlternative,
  TranscriptionEvent as CanonicalTranscriptionEvent,
  VadEvent as CanonicalVadEvent,
  VoiceEvent as CanonicalVoiceEvent,
} from '@runanywhere/proto-ts/events/public_events';
import type { Backend } from './Options.js';
import type {
  GenerationResult,
  ImageResult,
  Match,
  RagResult,
  Transcription,
} from './Results.js';

/**
 * Whether a streamed delta is answer text or a thought.
 *
 * Value type matches the shared lowercase grammar (`'text' | 'thought'`).
 * The shared const object (`TokenKind.TEXT`) is intentionally not re-exported
 * here — Web's public surface has always been the string-union type only.
 */
export type TokenKind = CanonicalTokenKind;

/** One alternative transcript for a still-revising partial segment. */
export type TranscriptAlternative = CanonicalTranscriptAlternative;

/** Progress of one text generation (`llm`/`vlm` `generateStream`). */
export type GenerationEvent = CanonicalGenerationEvent<
  GenerationResult,
  Partial<GenerationResult>
>;

/** Progress of one streamed transcription (`stt.openStream`). */
export type TranscriptionEvent = CanonicalTranscriptionEvent<
  Transcription,
  TranscriptAlternative
>;

/**
 * What a voice session is doing right now.
 *
 * Same lowercase string union as the shared module; const-object export is
 * omitted to keep Web's historical type-only public surface.
 */
export type AgentState = CanonicalAgentState;

/**
 * Progress of a live voice conversation.
 *
 * Includes the additive shared `inputSilent` arm (Web producers may not emit
 * it yet — non-breaking for consumers).
 */
export type VoiceEvent = CanonicalVoiceEvent;

/** Progress of one streamed RAG answer. */
export type RagEvent = CanonicalRagEvent<Match, RagResult>;

/** Progress of one image generation. */
export type ImageEvent = CanonicalImageEvent<ImageResult, Uint8Array>;

/** Progress of one model download, correlated by `operationId`/`sequence`. */
export type DownloadEvent = CanonicalDownloadEvent<
  { modelId: string },
  {
    bytesDone: number;
    bytesTotal: number;
    file?: string;
  }
>;

/** Speech-detection deltas over a chunk stream (`vad.openStream`). */
export type VadEvent = CanonicalVadEvent;

/** Lifecycle, download, and error breadcrumbs of the whole SDK. */
export type SdkEvent = CanonicalSdkEvent<Backend>;
