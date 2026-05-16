import _m0 from "protobufjs/minimal";
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
export interface LLMGenerateRequest {
    prompt: string;
    maxTokens: number;
    temperature: number;
    topP: number;
    topK: number;
    systemPrompt: string;
    /** chain-of-thought tokens emit as TokenKind.THOUGHT */
    emitThoughts: boolean;
    /**
     * Additional LLMGenerationOptions fields kept inline to avoid a codegen
     * package cycle between service stubs and option messages.
     *
     * idl-002: Intentionally omitted from this streaming request (no current
     * streaming consumer; route them through the non-streaming
     * rac_llm_generate_proto path which carries the full LLMGenerationOptions):
     *   - thinking_pattern (LLMGenerationOptions field 11)
     *   - structured_output (LLMGenerationOptions field 13)
     *   - enable_real_time_tracking (LLMGenerationOptions field 14)
     *   - repeat_last_n (LLMGenerationOptions field 18)
     *   - tool_calling (LLMGenerationOptions field 24) — tool-driven streaming
     *     is not yet supported on the LLM.Generate rpc; tool sessions must
     *     use the non-streaming generation path with LLMGenerationOptions.
     * Additionally, preferred_framework (field 11) and execution_target
     * (field 13) are degraded to `string` here instead of the InferenceFramework
     * / ExecutionTarget enums to keep this file decoupled from llm_options.proto.
     * Callers must use the canonical enum string values (see
     * llm_options.proto:69 and :85). See also synthesis idl-002.
     */
    repetitionPenalty: number;
    stopSequences: string[];
    streamingEnabled: boolean;
    preferredFramework: string;
    jsonSchema: string;
    executionTarget: string;
    requestId: string;
    modelId: string;
    conversationId: string;
    seed: number;
    frequencyPenalty: number;
    presencePenalty: number;
    minP: number;
    grammar: string;
    responseFormat: string;
    echoPrompt: boolean;
    nThreads: number;
    metadata: {
        [key: string]: string;
    };
}
export interface LLMGenerateRequest_MetadataEntry {
    key: string;
    value: string;
}
/**
 * Aggregate result carried on the terminal LLMStreamEvent. This intentionally
 * duplicates the scalar result fields instead of importing llm_options.proto:
 * Square Wire treats files with/without go_package as different Kotlin
 * packages, and that import creates a package cycle through sdk_events.
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
     * hotspot-idl-002: tool calls actually executed during the streaming
     * session (mirrors LLMGenerationResult.tool_calls / .tool_results in
     * llm_options.proto). Populated only on terminal events when the
     * backend completed at least one tool call.
     */
    toolCalls: ToolCall[];
    toolResults: ToolResult[];
}
/**
 * v2 close-out Phase G-2: unified per-token streaming event. Replaces
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
     * Token semantic category (answer / thought / tool-call). IDL-06:
     * canonical TokenKind from voice_events.proto.
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
     * hotspot-idl-002: structured tool-call payload emitted alongside an
     * event with event_kind=LLM_STREAM_EVENT_KIND_TOOL_CALL. Without this
     * field the tool-call event kind carries no proto-typed payload and
     * SDK consumers must fall back to JSON-parsing the raw `token` text.
     */
    toolCall?: ToolCall | undefined;
}
export declare const LLMGenerateRequest: {
    encode(message: LLMGenerateRequest, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): LLMGenerateRequest;
    fromJSON(object: any): LLMGenerateRequest;
    toJSON(message: LLMGenerateRequest): unknown;
    create<I extends Exact<DeepPartial<LLMGenerateRequest>, I>>(base?: I): LLMGenerateRequest;
    fromPartial<I extends Exact<DeepPartial<LLMGenerateRequest>, I>>(object: I): LLMGenerateRequest;
};
export declare const LLMGenerateRequest_MetadataEntry: {
    encode(message: LLMGenerateRequest_MetadataEntry, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): LLMGenerateRequest_MetadataEntry;
    fromJSON(object: any): LLMGenerateRequest_MetadataEntry;
    toJSON(message: LLMGenerateRequest_MetadataEntry): unknown;
    create<I extends Exact<DeepPartial<LLMGenerateRequest_MetadataEntry>, I>>(base?: I): LLMGenerateRequest_MetadataEntry;
    fromPartial<I extends Exact<DeepPartial<LLMGenerateRequest_MetadataEntry>, I>>(object: I): LLMGenerateRequest_MetadataEntry;
};
export declare const LLMStreamFinalResult: {
    encode(message: LLMStreamFinalResult, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): LLMStreamFinalResult;
    fromJSON(object: any): LLMStreamFinalResult;
    toJSON(message: LLMStreamFinalResult): unknown;
    create<I extends Exact<DeepPartial<LLMStreamFinalResult>, I>>(base?: I): LLMStreamFinalResult;
    fromPartial<I extends Exact<DeepPartial<LLMStreamFinalResult>, I>>(object: I): LLMStreamFinalResult;
};
export declare const LLMStreamEvent: {
    encode(message: LLMStreamEvent, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): LLMStreamEvent;
    fromJSON(object: any): LLMStreamEvent;
    toJSON(message: LLMStreamEvent): unknown;
    create<I extends Exact<DeepPartial<LLMStreamEvent>, I>>(base?: I): LLMStreamEvent;
    fromPartial<I extends Exact<DeepPartial<LLMStreamEvent>, I>>(object: I): LLMStreamEvent;
};
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
export {};
