import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
import { ChatMessage } from "./chat";
import { LLMGenerationOptions } from "./llm_options";
import { ToolCall, ToolResult } from "./tool_calling";
import { TokenKind } from "./voice_events";
export declare const protobufPackage = "runanywhere.v1";
export declare enum LLMStreamEventKind {
    LLM_STREAM_EVENT_KIND_UNSPECIFIED = 0,
    LLM_STREAM_EVENT_KIND_STARTED = 1,
    LLM_STREAM_EVENT_KIND_TOKEN = 2,
    LLM_STREAM_EVENT_KIND_THINKING = 3,
    LLM_STREAM_EVENT_KIND_TOOL_CALL = 4,
    LLM_STREAM_EVENT_KIND_PROGRESS = 5,
    LLM_STREAM_EVENT_KIND_COMPLETED = 6,
    LLM_STREAM_EVENT_KIND_ERROR = 7,
    UNRECOGNIZED = -1
}
export declare function lLMStreamEventKindFromJSON(object: any): LLMStreamEventKind;
export declare function lLMStreamEventKindToJSON(object: LLMStreamEventKind): string;
/**
 * Generation settings live exclusively in `options`. Reserved field numbers
 * prevent unsafe wire reuse.
 */
export interface LLMGenerateRequest {
    prompt: string;
    /** chain-of-thought tokens emit as TokenKind.THOUGHT */
    emitThoughts: boolean;
    requestId: string;
    modelId: string;
    conversationId: string;
    metadata: {
        [key: string]: string;
    };
    /**
     * Canonical generation settings. When absent, commons applies its SDK
     * defaults; callers that need explicit controls populate this message.
     */
    options?: LLMGenerationOptions | undefined;
    /**
     * Prior conversation turns (excludes the current `prompt`, which
     * stays the live user turn, and `options.system_prompt`, which stays
     * separate).
     * Alternating user/assistant ChatMessages in chronological order. An engine
     * that owns its chat template renders {system_prompt, history, prompt} from
     * its model's markers; engines that don't simply ignore this field.
     */
    history: ChatMessage[];
}
export interface LLMGenerateRequest_MetadataEntry {
    key: string;
    value: string;
}
/**
 * Aggregate terminal payload emitted by LLMStreamEvent. It intentionally keeps
 * stream-native token, timing, and error fields distinct from the unary
 * LLMGenerationResult shape.
 */
export interface LLMStreamFinalResult {
    text: string;
    thinkingContent?: string | undefined;
    promptTokens: number;
    completionTokens: number;
    totalTokens: number;
    totalTimeMs: number;
    timeToFirstTokenMs: number;
    tokensPerSecond: number;
    finishReason: string;
    errorCode: number;
    errorMessage: string;
    promptEvalTimeMs: number;
    decodeTimeMs: number;
    /**
     * Tool calls actually executed during the streaming session (mirrors
     * LLMGenerationResult.tool_calls / .tool_results in llm_options.proto).
     * Populated only on terminal events when the backend completed at least
     * one tool call.
     */
    toolCalls: ToolCall[];
    toolResults: ToolResult[];
}
/**
 * Unified per-token streaming event. Replaces
 * LLMToken (deleted) and the per-SDK hand-rolled AsyncThrowingStream /
 * callbackFlow / StreamController / tokenQueue. One serialized event
 * per generated token. Mirrors VoiceEvent's seq + timestamp_us pattern
 * from voice_events.proto so frontends can reuse gap-detection logic.
 */
export interface LLMStreamEvent {
    /**
     * Monotonic per-process sequence number. Useful for frontends that
     * need to detect gaps or out-of-order delivery.
     */
    seq: number;
    /**
     * Wall-clock timestamp captured at the C++ edge, in microseconds
     * since Unix epoch. Frontends may re-timestamp for UI display.
     */
    timestampUs: number;
    /**
     * Generated token text. Empty on terminal events where only
     * finish_reason or error_message is populated.
     */
    token: string;
    /** True on the last event of a generation. */
    isFinal: boolean;
    /**
     * Token semantic category (answer / thought / tool-call).
     * Canonical TokenKind from voice_events.proto.
     */
    kind: TokenKind;
    /**
     * Backend-provided token id when the engine exposes it; 0 = unset
     * (proto3 scalar default).
     */
    tokenId: number;
    /** Per-token log-probability when supported; 0.0 = unset. */
    logprob: number;
    /**
     * Reason the stream stopped: "stop", "length", "cancelled", "error",
     * "" = unset (proto3 scalar default). Only populated when is_final.
     */
    finishReason: string;
    /**
     * Error message on failure events (kind may be unset, is_final true).
     * Empty on success.
     */
    errorMessage: string;
    /**
     * Final aggregate result. Only populated on terminal events
     * (is_final=true) when the backend can report result metrics.
     */
    result?: LLMStreamFinalResult | undefined;
    /**
     * Numeric backend status code when the terminal event represents a
     * failure. 0 = unset/success.
     */
    errorCode: number;
    /** Event classification distinct from token semantic kind. */
    eventKind: LLMStreamEventKind;
    /** Request/session correlation fields. */
    requestId: string;
    conversationId: string;
    /** Running counters for progress UIs. */
    promptTokensProcessed: number;
    completionTokensGenerated: number;
    elapsedMs: number;
    /**
     * Structured tool-call payload emitted when event_kind is
     * LLM_STREAM_EVENT_KIND_TOOL_CALL.
     */
    toolCall?: ToolCall | undefined;
}
export declare const LLMGenerateRequest: MessageFns<LLMGenerateRequest>;
export declare const LLMGenerateRequest_MetadataEntry: MessageFns<LLMGenerateRequest_MetadataEntry>;
export declare const LLMStreamFinalResult: MessageFns<LLMStreamFinalResult>;
export declare const LLMStreamEvent: MessageFns<LLMStreamEvent>;
type Builtin = Date | Function | Uint8Array | string | number | boolean | undefined;
export type DeepPartial<T> = T extends Builtin ? T : T extends globalThis.Array<infer U> ? globalThis.Array<DeepPartial<U>> : T extends ReadonlyArray<infer U> ? ReadonlyArray<DeepPartial<U>> : T extends {} ? {
    [K in keyof T]?: DeepPartial<T[K]>;
} : Partial<T>;
type KeysOfUnion<T> = T extends T ? keyof T : never;
export type Exact<P, I extends P> = P extends Builtin ? P : P & {
    [K in keyof P]: Exact<P[K], I[K]>;
} & {
    [K in Exclude<keyof I, KeysOfUnion<P>>]: never;
};
export interface MessageFns<T> {
    encode(message: T, writer?: BinaryWriter): BinaryWriter;
    decode(input: BinaryReader | Uint8Array, length?: number): T;
    fromJSON(object: any): T;
    toJSON(message: T): unknown;
    create<I extends Exact<DeepPartial<T>, I>>(base?: I): T;
    fromPartial<I extends Exact<DeepPartial<T>, I>>(object: I): T;
}
export {};
