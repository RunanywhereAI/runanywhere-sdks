import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
import { ChatMessage } from "./chat";
import { LLMGenerationOptions } from "./llm_options";
import { ToolCall, ToolCallingResult, ToolResult } from "./tool_calling";
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
/** The single request envelope for both unary and streaming generation. */
export interface LLMGenerateRequest {
    prompt: string;
    requestId: string;
    modelId: string;
    conversationId: string;
    metadata: {
        [key: string]: string;
    };
    options?: LLMGenerationOptions | undefined;
    /**
     * Prior turns, excluding `prompt` (the live user turn) and
     * options.system_prompt.
     */
    history: ChatMessage[];
}
export interface LLMGenerateRequest_MetadataEntry {
    key: string;
    value: string;
}
export interface LLMStreamFinalResult {
    text: string;
    thinkingContent?: string | undefined;
    inputTokens: number;
    outputTokens: number;
    totalTokens: number;
    totalTimeMs: number;
    timeToFirstTokenMs: number;
    tokensPerSecond: number;
    finishReason: string;
    errorCode: number;
    errorMessage: string;
    promptEvalTimeMs: number;
    decodeTimeMs: number;
    toolCalls: ToolCall[];
    toolResults: ToolResult[];
}
/** `result` is populated only on the terminal event. */
export interface LLMStreamEvent {
    seq: number;
    timestampUs: number;
    token: string;
    isFinal: boolean;
    kind: TokenKind;
    tokenId: number;
    logprob: number;
    finishReason: string;
    errorMessage: string;
    result?: LLMStreamFinalResult | undefined;
    errorCode: number;
    eventKind: LLMStreamEventKind;
    requestId: string;
    conversationId: string;
    promptTokensProcessed: number;
    completionTokensGenerated: number;
    elapsedMs: number;
    toolCall?: ToolCall | undefined;
}
/** Tool-driven streaming uses this session path, not LLMGenerateRequest. */
export interface ToolCallingSessionCreateRequest {
    prompt: string;
    generation?: LLMGenerationOptions | undefined;
    /** Unset preserves commons' secure default of validate=true. */
    validateCalls?: boolean | undefined;
    history: ChatMessage[];
}
export interface ToolCallingSessionEvent {
    /** serialized LLMStreamEvent */
    llmStreamEventBytes?: Uint8Array | undefined;
    toolCall?: ToolCall | undefined;
    finalResult?: ToolCallingResult | undefined;
    /** serialized SDKError */
    errorBytes?: Uint8Array | undefined;
    seq: number;
}
/** Hands a caller-executed tool result back into a running session. */
export interface ToolCallingSessionStepWithResultRequest {
    sessionHandle: number;
    toolCallId: string;
    resultJson: string;
    error?: string | undefined;
}
export declare const LLMGenerateRequest: MessageFns<LLMGenerateRequest>;
export declare const LLMGenerateRequest_MetadataEntry: MessageFns<LLMGenerateRequest_MetadataEntry>;
export declare const LLMStreamFinalResult: MessageFns<LLMStreamFinalResult>;
export declare const LLMStreamEvent: MessageFns<LLMStreamEvent>;
export declare const ToolCallingSessionCreateRequest: MessageFns<ToolCallingSessionCreateRequest>;
export declare const ToolCallingSessionEvent: MessageFns<ToolCallingSessionEvent>;
export declare const ToolCallingSessionStepWithResultRequest: MessageFns<ToolCallingSessionStepWithResultRequest>;
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
