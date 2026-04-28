import _m0 from "protobufjs/minimal";
import { InferenceFramework } from "./model_types";
export declare const protobufPackage = "runanywhere.v1";
/**
 * ---------------------------------------------------------------------------
 * Options for a single text generation invocation.
 *
 * Field names match Swift LLMGenerationOptions exactly; consumers may treat
 * proto3 scalar defaults as "unset" (Swift handled this via Optionals — proto
 * represents optional reference fields explicitly via `optional` keyword).
 * ---------------------------------------------------------------------------
 */
export interface LLMGenerationOptions {
    /**
     * Maximum number of tokens to generate. 0 (default) = unset → engine
     * default (typically 100).
     */
    maxTokens: number;
    /** Sampling temperature (0.0 - 2.0). 0.0 = greedy decoding. */
    temperature: number;
    /** Nucleus sampling (top-p). 1.0 = no nucleus truncation. */
    topP: number;
    /** Top-K sampling (Kotlin/Dart/RN field). 0 = disabled. */
    topK: number;
    /** Repetition penalty (Kotlin/Dart/RN field). 1.0 = no penalty. */
    repetitionPenalty: number;
    /**
     * Stop sequences. Generation halts when any of these strings appears in
     * the output stream.
     */
    stopSequences: string[];
    /** Whether to stream tokens vs return result at end (Swift field). */
    streamingEnabled: boolean;
    /** Preferred inference framework. UNSPECIFIED = pick automatically. */
    preferredFramework: InferenceFramework;
    /** System prompt to define AI behavior and formatting rules. */
    systemPrompt?: string | undefined;
    /**
     * Optional structured-output mode (JSON schema). Engine returns text
     * that conforms to this schema. Swift wraps this in a StructuredOutputConfig
     * struct with the Generatable.Type — proto carries just the schema string.
     */
    jsonSchema?: string | undefined;
}
/**
 * ---------------------------------------------------------------------------
 * Result of a single text generation. Same fields as the Swift
 * LLMGenerationResult plus the fields RN/Web carry that Swift derives from
 * the rac_llm_stream_result_t C struct.
 * ---------------------------------------------------------------------------
 */
export interface LLMGenerationResult {
    /** Generated text (with thinking content removed if extracted). */
    text: string;
    /** Optional thinking/reasoning content extracted from the response. */
    thinkingContent?: string | undefined;
    /** Number of input/prompt tokens (from tokenizer). */
    inputTokens: number;
    /** Number of tokens used (output / completion tokens). */
    tokensGenerated: number;
    /** Model used for generation. */
    modelUsed: string;
    /** Total wall-clock generation time in milliseconds. */
    generationTimeMs: number;
    /** Time-to-first-token in milliseconds (only set in streaming mode). */
    ttftMs?: number | undefined;
    /** Tokens-per-second throughput. */
    tokensPerSecond: number;
    /**
     * Framework that actually performed the generation. Optional because
     * some C ABI paths don't surface it.
     */
    framework?: string | undefined;
    /**
     * Reason the generation stopped: "stop", "length", "cancelled", "error".
     * Empty = unset.
     */
    finishReason: string;
    /** Number of tokens used for thinking/reasoning. 0 = not applicable. */
    thinkingTokens: number;
    /** Number of tokens in the actual response content (vs thinking). */
    responseTokens: number;
    /**
     * Optional JSON output (when structured-output mode was requested).
     * Empty = no structured output.
     */
    jsonOutput?: string | undefined;
}
export declare const LLMGenerationOptions: {
    encode(message: LLMGenerationOptions, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): LLMGenerationOptions;
    fromJSON(object: any): LLMGenerationOptions;
    toJSON(message: LLMGenerationOptions): unknown;
    create<I extends Exact<DeepPartial<LLMGenerationOptions>, I>>(base?: I): LLMGenerationOptions;
    fromPartial<I extends Exact<DeepPartial<LLMGenerationOptions>, I>>(object: I): LLMGenerationOptions;
};
export declare const LLMGenerationResult: {
    encode(message: LLMGenerationResult, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): LLMGenerationResult;
    fromJSON(object: any): LLMGenerationResult;
    toJSON(message: LLMGenerationResult): unknown;
    create<I extends Exact<DeepPartial<LLMGenerationResult>, I>>(base?: I): LLMGenerationResult;
    fromPartial<I extends Exact<DeepPartial<LLMGenerationResult>, I>>(object: I): LLMGenerationResult;
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
//# sourceMappingURL=llm_options.d.ts.map