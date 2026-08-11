/**
 * Canonical public stream-event grammars shared by Web / React Native / Electron.
 *
 * HAND-AUTHORED companion to the generated proto bindings. Discriminated unions
 * keyed by `type` — the v4 public API grammar (`started` → deltas → terminal
 * `completed` / `failed` / `cancelled`).
 *
 * Design rules:
 *   - `failed.error` is always the structured proto {@link SDKError} (Electron's
 *     IPC-safe choice). SDKs that historically used `Error` must adapt at the
 *     re-export boundary, not widen the shared type back to `Error`.
 *   - Result / match / transcription shapes differ across SDKs; those payload
 *     slots are type parameters so each SDK can bind its local public types
 *     without forking the discriminant arms.
 *   - Deprecated RN-only arms (`token`, `toolCall`) live in the
 *     `*WithDeprecated` aliases — keep them out of the canonical unions so new
 *     SDKs do not inherit dead surface area.
 */
import type { SDKError } from '../errors';
import type { ModelCategory } from '../model_types';
import type { TokenUsage } from '../token_usage';
import type { ToolCall } from '../tool_calling';
/** Whether a streamed delta is answer text or a thought. */
export declare const TokenKind: {
    readonly TEXT: "text";
    readonly THOUGHT: "thought";
};
export type TokenKind = (typeof TokenKind)[keyof typeof TokenKind];
/** What a voice session is doing right now. */
export declare const AgentState: {
    readonly LISTENING: "listening";
    readonly THINKING: "thinking";
    readonly SPEAKING: "speaking";
};
export type AgentState = (typeof AgentState)[keyof typeof AgentState];
/** One alternative transcript for a still-revising partial segment. */
export interface TranscriptAlternative {
    text: string;
    confidence?: number;
}
/**
 * Progress of one text generation (`llm` / `vlm` `generateStream`).
 *
 * @typeParam TResult - SDK-local generation result shape.
 * @typeParam TPartial - What a mid-flight failure/cancel may still carry.
 * @typeParam TToolCall - Tool-call payload (defaults to proto {@link ToolCall}).
 * @typeParam TUsage - Usage payload (defaults to proto {@link TokenUsage}).
 * @typeParam TItem - Payload of `outputItemAdded` (Web: `unknown`, Electron: `string`).
 */
export type GenerationEvent<TResult = unknown, TPartial = Partial<TResult>, TToolCall = ToolCall, TUsage = TokenUsage, TItem = unknown> = {
    type: 'started';
    requestId: string;
} | {
    type: 'outputItemAdded';
    requestId: string;
    sequence: number;
    itemId: string;
    index: number;
    item: TItem;
} | {
    type: 'textDelta';
    requestId: string;
    sequence: number;
    itemId: string;
    index: number;
    text: string;
} | {
    type: 'reasoningDelta';
    requestId: string;
    sequence: number;
    itemId: string;
    index: number;
    text: string;
} | {
    type: 'toolCallAdded';
    requestId: string;
    sequence: number;
    itemId: string;
    index: number;
    call: TToolCall;
} | {
    type: 'toolArgumentsDelta';
    requestId: string;
    sequence: number;
    itemId: string;
    delta: string;
} | {
    type: 'toolArgumentsDone';
    requestId: string;
    sequence: number;
    itemId: string;
    arguments: string;
} | {
    type: 'usage';
    requestId: string;
    sequence: number;
    usage: TUsage;
} | {
    type: 'completed';
    requestId: string;
    result: TResult;
} | {
    type: 'failed';
    requestId: string;
    partial?: TPartial;
    error: SDKError;
} | {
    type: 'cancelled';
    requestId: string;
    partial?: TPartial;
};
/**
 * RN-local widening of {@link GenerationEvent} that keeps the deprecated
 * `token` / `toolCall` arms for one release. New SDKs must not re-export this.
 */
export type GenerationEventWithDeprecated<TResult = unknown, TPartial = Partial<TResult>, TToolCall = ToolCall, TUsage = TokenUsage, TItem = unknown> = GenerationEvent<TResult, TPartial, TToolCall, TUsage, TItem> | {
    type: 'token';
    text: string;
    kind: TokenKind;
} | {
    type: 'toolCall';
    toolCall: TToolCall;
};
/** Progress of one streamed transcription (`stt.openStream`). */
export type TranscriptionEvent<TSegment = unknown, TAlternative = TranscriptAlternative> = {
    type: 'started';
    requestId: string;
} | {
    type: 'speechStarted';
    requestId: string;
    sequence: number;
    timestampMs?: number;
} | {
    type: 'partial';
    requestId: string;
    sequence: number;
    segmentId: string;
    revision: number;
    alternatives: TAlternative[];
} | {
    type: 'transcriptFinal';
    requestId: string;
    sequence: number;
    segment: TSegment;
} | {
    type: 'speechEnded';
    requestId: string;
    sequence: number;
    timestampMs?: number;
} | {
    type: 'usage';
    requestId: string;
    sequence: number;
    usage: TokenUsage;
} | {
    type: 'completed';
    requestId: string;
} | {
    type: 'failed';
    requestId: string;
    error: SDKError;
} | {
    type: 'cancelled';
    requestId: string;
};
/** Progress of a live voice conversation. */
export type VoiceEvent = {
    type: 'userTranscribed';
    text: string;
    isFinal: boolean;
    requestId?: string;
} | {
    type: 'agentStateChanged';
    state: AgentState;
} | {
    type: 'agentResponse';
    text: string;
    speechId?: string;
} | {
    type: 'speechStarted';
    speechId?: string;
} | {
    type: 'speechEnded';
    speechId?: string;
}
/**
 * Recoverable "hearing nothing usable" signal (Electron surfaces this;
 * Web/RN may omit locally until producers exist).
 */
 | {
    type: 'inputSilent';
    detail: string;
} | {
    type: 'error';
    message: string;
    recoverable: boolean;
    source?: string;
    code?: string;
};
/** Progress of one streamed RAG answer. */
export type RagEvent<TMatch = unknown, TResult = unknown> = {
    type: 'retrieved';
    matches: TMatch[];
} | {
    type: 'textDelta';
    text: string;
    kind: TokenKind;
} | {
    type: 'completed';
    result: TResult;
} | {
    type: 'failed';
    error: SDKError;
};
/**
 * RN-local widening that keeps the deprecated `token` arm.
 * Prefer {@link RagEvent} for new code.
 */
export type RagEventWithDeprecated<TMatch = unknown, TResult = unknown> = RagEvent<TMatch, TResult> | {
    type: 'token';
    text: string;
    kind: TokenKind;
};
/** Progress of one image generation. */
export type ImageEvent<TResult = unknown, TPartialImage = Uint8Array> = {
    type: 'started';
} | {
    type: 'progress';
    step: number;
    totalSteps: number;
    partialImage?: TPartialImage;
} | {
    type: 'completed';
    result: TResult;
} | {
    type: 'failed';
    error: SDKError;
};
/** Progress of one model download. */
export type DownloadEvent<TCompleted = {
    modelId: string;
}, TProgress = {
    bytesDone: number;
    bytesTotal: number;
    file?: string;
}> = {
    type: 'started';
    operationId: string;
    sequence: number;
} | ({
    type: 'progress';
    operationId: string;
    sequence: number;
} & TProgress) | {
    type: 'verifying';
    operationId: string;
    sequence: number;
} | {
    type: 'extracting';
    operationId: string;
    sequence: number;
    percent?: number;
} | ({
    type: 'completed';
    operationId: string;
    sequence: number;
} & TCompleted) | {
    type: 'failed';
    operationId: string;
    sequence: number;
    error: SDKError;
} | {
    type: 'cancelled';
    operationId: string;
    sequence: number;
};
/** Speech-detection deltas over a chunk stream (`vad.openStream`). */
export type VadEvent = {
    type: 'speechStarted';
    timestampMs?: number;
} | {
    type: 'speechEnded';
    timestampMs?: number;
} | {
    type: 'activity';
    isSpeech: boolean;
    probability: number;
    timestampMs?: number;
} | {
    type: 'failed';
    error: SDKError;
} | {
    type: 'completed';
};
/** Lifecycle, download, and error breadcrumbs of the whole SDK. */
export type SdkEvent<TBackend = string> = {
    type: 'ready';
} | {
    type: 'modelLoaded';
    id: string;
    category: ModelCategory;
    actualBackend?: TBackend;
} | {
    type: 'modelUnloaded';
    id: string;
} | {
    type: 'error';
    message: string;
    recoverable: boolean;
    source?: string;
    code?: string;
};
