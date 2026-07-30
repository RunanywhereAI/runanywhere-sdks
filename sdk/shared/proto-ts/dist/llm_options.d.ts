import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
import { InferenceFramework } from "./model_types";
import { StructuredOutputOptions, StructuredOutputValidation } from "./structured_output";
import { ReasoningOptions } from "./thinking_tag_pattern";
import { ToolCall, ToolCallingOptions, ToolResult } from "./tool_calling";
export declare const protobufPackage = "runanywhere.v1";
export declare enum ExecutionTarget {
    EXECUTION_TARGET_UNSPECIFIED = 0,
    EXECUTION_TARGET_ON_DEVICE = 1,
    EXECUTION_TARGET_CLOUD = 2,
    EXECUTION_TARGET_AUTO = 3,
    UNRECOGNIZED = -1
}
export declare function executionTargetFromJSON(object: any): ExecutionTarget;
export declare function executionTargetToJSON(object: ExecutionTarget): string;
export interface LLMGenerationOptions {
    /** 0 = unset, so the annotated default applies. */
    maxOutputTokens: number;
    /** 0.0 = greedy decoding. */
    temperature: number;
    topP: number;
    /** Commons treats 0 as unset for every sampling knob below. */
    topK: number;
    repetitionPenalty: number;
    stopSequences: string[];
    preferredFramework: InferenceFramework;
    systemPrompt?: string | undefined;
    reasoning?: ReasoningOptions | undefined;
    /** No consumer reads this today. */
    executionTarget?: ExecutionTarget | undefined;
    structuredOutput?: StructuredOutputOptions | undefined;
    seed: number;
    frequencyPenalty: number;
    presencePenalty: number;
    /** No engine reads repeat_last_n or echo_prompt. */
    repeatLastN: number;
    minP: number;
    echoPrompt: boolean;
    nThreads: number;
    toolCalling?: ToolCallingOptions | undefined;
}
export interface LLMGenerationResult {
    text: string;
    thinkingContent?: string | undefined;
    inputTokens: number;
    outputTokens: number;
    modelUsed: string;
    generationTimeMs: number;
    ttftMs?: number | undefined;
    tokensPerSecond: number;
    framework?: string | undefined;
    finishReason: string;
    thinkingTokens: number;
    responseTokens: number;
    jsonOutput?: string | undefined;
    /** Nothing reads performance or executed_on. */
    performance?: PerformanceMetrics | undefined;
    executedOn?: ExecutionTarget | undefined;
    structuredOutputValidation?: StructuredOutputValidation | undefined;
    /** input_tokens + output_tokens. */
    totalTokens: number;
    errorMessage?: string | undefined;
    errorCode: number;
    cachedPromptTokens: number;
    promptEvalTimeMs: number;
    decodeTimeMs: number;
    toolCalls: ToolCall[];
    toolResults: ToolResult[];
}
export interface LLMConfiguration {
    contextLength: number;
    modelId?: string | undefined;
    preferredFramework?: InferenceFramework | undefined;
    /** Applied when a per-call LLMGenerationOptions leaves a field unset. */
    defaultOptions?: LLMGenerationOptions | undefined;
}
export interface StreamToken {
    text: string;
    timestampMs: number;
    index: number;
}
/** Referenced only by LLMGenerationResult.performance, which no SDK reads. */
export interface PerformanceMetrics {
    latencyMs: number;
    memoryBytes: number;
    throughputTokensPerSec: number;
    inputTokens: number;
    outputTokens: number;
}
export declare const LLMGenerationOptions: MessageFns<LLMGenerationOptions>;
export declare const LLMGenerationResult: MessageFns<LLMGenerationResult>;
export declare const LLMConfiguration: MessageFns<LLMConfiguration>;
export declare const StreamToken: MessageFns<StreamToken>;
export declare const PerformanceMetrics: MessageFns<PerformanceMetrics>;
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
