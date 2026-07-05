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
 * pass3-syn-025: the inline scalar fields below historically existed to avoid
 * importing llm_options.proto. The cycle-avoidance rationale no longer holds
 * (sdk_events.proto has no transitive dependency on llm_options.proto), so
 * idl-005 introduces the canonical `LLMGenerationOptions options` embedded
 * message at field 26. The inline scalar fields are RETAINED for wire-format
 * backwards compatibility but are deprecated; new code SHOULD populate
 * `options.*` and consumers SHOULD prefer `options.*` when set (falling back
 * to the inline fields for legacy callers). The companion fix for
 * VoiceAgentConfig.tts_voice_id (the actual content of syn-025's "VoiceAgent
 * proto carries tts_model_id but not tts_voice_id" issue) lives in
 * idl/solutions.proto where VoiceAgentConfig is declared.
 */
export interface LLMGenerateRequest {
    prompt: string;
    /** @deprecated */
    maxTokens: number;
    /** @deprecated */
    temperature: number;
    /** @deprecated */
    topP: number;
    /** @deprecated */
    topK: number;
    /** @deprecated */
    systemPrompt: string;
    /** chain-of-thought tokens emit as TokenKind.THOUGHT */
    emitThoughts: boolean;
    /**
     * Inline LLMGenerationOptions fields — DEPRECATED, prefer `options` (field 26).
     *
     * Streaming gaps below remain intentional: a streaming consumer that
     * requires these advanced knobs MUST set them on `options.*` rather than
     * inline (no inline duplicate exists):
     *   - thinking_pattern (LLMGenerationOptions field 11)
     *   - structured_output (LLMGenerationOptions field 13)
     *   - enable_real_time_tracking (LLMGenerationOptions field 14)
     *   - repeat_last_n (LLMGenerationOptions field 18)
     *   - tool_calling (LLMGenerationOptions field 24) — tool-driven streaming
     *     is not yet supported on the LLM.Generate rpc; tool sessions must
     *     use the non-streaming generation path with LLMGenerationOptions.
     * Note the inline `preferred_framework` (field 11) and `execution_target`
     * (field 13) are degraded to `string` for backwards compatibility;
     * `options.preferred_framework` and `options.execution_target` carry the
     * canonical InferenceFramework / ExecutionTarget enums.
     *
     * @deprecated
     */
    repetitionPenalty: number;
    /** @deprecated */
    stopSequences: string[];
    /** @deprecated */
    streamingEnabled: boolean;
    /** @deprecated */
    preferredFramework: string;
    /** @deprecated */
    jsonSchema: string;
    /** @deprecated */
    executionTarget: string;
    requestId: string;
    modelId: string;
    conversationId: string;
    /** @deprecated */
    seed: number;
    /** @deprecated */
    frequencyPenalty: number;
    /** @deprecated */
    presencePenalty: number;
    /** @deprecated */
    minP: number;
    /** @deprecated */
    grammar: string;
    /** @deprecated */
    responseFormat: string;
    /** @deprecated */
    echoPrompt: boolean;
    /** @deprecated */
    nThreads: number;
    metadata: {
        [key: string]: string;
    };
    /**
     * idl-005: canonical generation options. When set, consumers SHOULD use
     * the values here in preference to the legacy inline scalar fields above.
     * The wire schema retains the inline fields to avoid breaking existing
     * serialized requests; new callers should only populate `options`.
     */
    options?: LLMGenerationOptions | undefined;
    /**
     * idl-chat: PRIOR conversation turns (excludes the current `prompt`, which
     * stays the live user turn, and `system_prompt`, which stays separate).
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
     * hotspot-idl-002: structured tool-call payload emitted alongside an
     * event with event_kind=LLM_STREAM_EVENT_KIND_TOOL_CALL. Without this
     * field the tool-call event kind carries no proto-typed payload and
     * SDK consumers must fall back to JSON-parsing the raw `token` text.
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
