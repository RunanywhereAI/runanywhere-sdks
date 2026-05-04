import _m0 from "protobufjs/minimal";
export declare const protobufPackage = "runanywhere.v1";
export declare enum LLMTokenKind {
    LLM_TOKEN_KIND_UNSPECIFIED = 0,
    LLM_TOKEN_KIND_ANSWER = 1,
    LLM_TOKEN_KIND_THOUGHT = 2,
    LLM_TOKEN_KIND_TOOL_CALL = 3,
    UNRECOGNIZED = -1
}
export declare function lLMTokenKindFromJSON(object: any): LLMTokenKind;
export declare function lLMTokenKindToJSON(object: LLMTokenKind): string;
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
     */
    repetitionPenalty: number;
    stopSequences: string[];
    streamingEnabled: boolean;
    preferredFramework: string;
    jsonSchema: string;
    executionTarget: string;
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
    /** Token semantic category (answer / thought / tool-call). */
    kind: LLMTokenKind;
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
}
export declare const LLMGenerateRequest: {
    encode(message: LLMGenerateRequest, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): LLMGenerateRequest;
    fromJSON(object: any): LLMGenerateRequest;
    toJSON(message: LLMGenerateRequest): unknown;
    create<I extends Exact<DeepPartial<LLMGenerateRequest>, I>>(base?: I): LLMGenerateRequest;
    fromPartial<I extends Exact<DeepPartial<LLMGenerateRequest>, I>>(object: I): LLMGenerateRequest;
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
//# sourceMappingURL=llm_service.d.ts.map