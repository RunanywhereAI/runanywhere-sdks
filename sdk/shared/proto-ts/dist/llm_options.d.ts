import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
import { SDKError } from "./errors";
import { InferenceFramework } from "./model_types";
import { StructuredOutputOptions, StructuredOutputValidation } from "./structured_output";
import { ReasoningOptions } from "./thinking_tag_pattern";
import { TokenUsage } from "./token_usage";
import { ToolCall, ToolCallingOptions, ToolResult } from "./tool_calling";
export declare const protobufPackage = "runanywhere.v1";
/**
 * One declared vocabulary, used in every place a finish reason is reported
 * on the LLM generation path (LLMGenerationResult, LLMStreamEvent).
 */
export declare enum FinishReason {
    FINISH_REASON_UNSPECIFIED = 0,
    /** FINISH_REASON_STOP - End-of-turn token. OpenAI "stop" / Anthropic "end_turn". */
    FINISH_REASON_STOP = 1,
    /** FINISH_REASON_LENGTH - Hit max_output_tokens. OpenAI "length" / Anthropic "max_tokens". */
    FINISH_REASON_LENGTH = 2,
    /** FINISH_REASON_STOP_SEQUENCE - One of options.stop_sequences fired; see `stop_sequence`. */
    FINISH_REASON_STOP_SEQUENCE = 3,
    /** FINISH_REASON_TOOL_CALLS - Model wants a tool run before it can continue. */
    FINISH_REASON_TOOL_CALLS = 4,
    /** FINISH_REASON_CANCELLED - Caller cancelled. No cloud analogue. */
    FINISH_REASON_CANCELLED = 5,
    /** FINISH_REASON_CONTEXT_OVERFLOW - Conversation exceeded the allocated context window. */
    FINISH_REASON_CONTEXT_OVERFLOW = 6,
    /** FINISH_REASON_ERROR - Generation failed; see `error`. */
    FINISH_REASON_ERROR = 7,
    UNRECOGNIZED = -1
}
export declare function finishReasonFromJSON(object: any): FinishReason;
export declare function finishReasonToJSON(object: FinishReason): string;
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
    /**
     * Every knob below has explicit presence: ABSENT means the annotated
     * default applies, and any value the caller sets -- including 0 -- is
     * honoured verbatim. Nothing treats 0 as unset.
     *
     * Sampler chain order is fixed: repeat_penalty -> top_k -> top_p ->
     * min_p -> temperature (llama.cpp order, minus the samplers we do not
     * expose). top_k/min_p/repeat_penalty default ON to match llama.cpp and
     * Ollama, which both ship these on because small quantized models loop
     * without them.
     */
    maxOutputTokens?: number | undefined;
    /** 0.0 = greedy decoding, and is honoured as an explicit request. */
    temperature?: number | undefined;
    topP?: number | undefined;
    topK?: number | undefined;
    /** Industry name: llama.cpp and Ollama both spell this repeat_penalty. */
    repeatPenalty?: number | undefined;
    stopSequences: string[];
    preferredFramework: InferenceFramework;
    systemPrompt?: string | undefined;
    reasoning?: ReasoningOptions | undefined;
    /** No consumer reads this today. */
    executionTarget?: ExecutionTarget | undefined;
    structuredOutput?: StructuredOutputOptions | undefined;
    seed?: number | undefined;
    frequencyPenalty?: number | undefined;
    presencePenalty?: number | undefined;
    /** No engine reads repeat_last_n or echo_prompt. */
    repeatLastN: number;
    minP?: number | undefined;
    echoPrompt: boolean;
    toolCalling?: ToolCallingOptions | undefined;
}
export interface LLMGenerationResult {
    text: string;
    thinkingContent?: string | undefined;
    modelUsed: string;
    generationTimeMs: number;
    framework?: string | undefined;
    thinkingTokens: number;
    responseTokens: number;
    jsonOutput?: string | undefined;
    finishReason: FinishReason;
    /**
     * Which of options.stop_sequences fired. Set only when finish_reason ==
     * FINISH_REASON_STOP_SEQUENCE. Industry: Anthropic `stop_sequence`,
     * llama.cpp `stopping_word`.
     */
    stopSequence?: string | undefined;
    /** Nothing reads performance or executed_on. */
    performance?: PerformanceMetrics | undefined;
    executedOn?: ExecutionTarget | undefined;
    structuredOutputValidation?: StructuredOutputValidation | undefined;
    cachedPromptTokens: number;
    promptEvalTimeMs: number;
    decodeTimeMs: number;
    toolCalls: ToolCall[];
    toolResults: ToolResult[];
    usage?: TokenUsage | undefined;
    error?: SDKError | undefined;
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
    usage?: TokenUsage | undefined;
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
