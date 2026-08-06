import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
import { ChatMessage } from "./chat";
import { SDKError } from "./errors";
import { FinishReason, LLMGenerationOptions, LLMGenerationResult } from "./llm_options";
import { ToolCall } from "./tool_calling";
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
/** The single request envelope for both unary and streaming generation. */
export interface LLMGenerateRequest {
    /**
     * Correlation id, echoed on every LLMStreamEvent for this call. Empty =
     * commons generates one, which is the normal case and matches industry
     * practice (provider-generated: OpenAI `id`, Anthropic `request-id`). A
     * non-empty caller value is honoured verbatim.
     */
    requestId: string;
    modelId: string;
    conversationId: string;
    options?: LLMGenerationOptions | undefined;
    /**
     * The whole conversation, oldest first, ending with the turn the model
     * must answer. Never empty. System turns belong in
     * options.system_prompt, not here.
     */
    messages: ChatMessage[];
}
/**
 * LLMStreamFinalResult is deleted: the stream terminates with the same
 * LLMGenerationResult type the unary call returns (see `result` below), so
 * one mapper serves both paths instead of two near-identical ones.
 *
 * Exactly one terminal event per stream: event_kind == COMPLETED (with
 * `result` set) or == ERROR (with `error` set). `event_kind` is the primary
 * discriminator.
 */
export interface LLMStreamEvent {
    /** Monotonic sequence for tool-calling session streams (#607). */
    seq: number;
    /**
     * The delta. Answer text when event_kind == TOKEN, reasoning text when
     * event_kind == THINKING.
     */
    token: string;
    eventKind: LLMStreamEventKind;
    /** Correlation id, echoed from the request on every event. */
    requestId: string;
    finishReason: FinishReason;
    /** Present exactly when event_kind == COMPLETED. */
    result?: LLMGenerationResult | undefined;
    /** Present exactly when event_kind == TOOL_CALL. */
    toolCall?: ToolCall | undefined;
    /** Present exactly when event_kind == ERROR. */
    error?: SDKError | undefined;
    /**
     * Largest complete JSON value visible in the output so far, when
     * LLMGenerationOptions.structured_output is set.
     */
    partialJson?: string | undefined;
}
export declare const LLMGenerateRequest: MessageFns<LLMGenerateRequest>;
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
