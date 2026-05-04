import _m0 from "protobufjs/minimal";
import { InferenceFramework } from "./model_types";
import { StructuredOutputOptions, StructuredOutputValidation } from "./structured_output";
export declare const protobufPackage = "runanywhere.v1";
/**
 * ---------------------------------------------------------------------------
 * Routing destination for a generation (Web SDK ExecutionTarget in
 * types/models.ts:79). Drives the cloud-vs-on-device dispatcher.
 * ---------------------------------------------------------------------------
 */
export declare enum ExecutionTarget {
    EXECUTION_TARGET_UNSPECIFIED = 0,
    EXECUTION_TARGET_ON_DEVICE = 1,
    EXECUTION_TARGET_CLOUD = 2,
    /** EXECUTION_TARGET_AUTO - Let the SDK decide based on policy (cost, latency, privacy, etc.). */
    EXECUTION_TARGET_AUTO = 3,
    UNRECOGNIZED = -1
}
export declare function executionTargetFromJSON(object: any): ExecutionTarget;
export declare function executionTargetToJSON(object: ExecutionTarget): string;
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
    /**
     * Optional thinking-tag pattern for extracting reasoning content from
     * models like Qwen3 / LFM2 that emit <think>...</think> blocks.
     */
    thinkingPattern?: ThinkingTagPattern | undefined;
    /**
     * Routing hint: where this generation should run (on-device, cloud, or
     * SDK-decided AUTO). Mirrors the Web SDK ExecutionTarget knob.
     */
    executionTarget?: ExecutionTarget | undefined;
    /**
     * Optional structured-output configuration. Detailed message lives in
     * structured_output.proto so the schema/format details aren't duplicated
     * here. When set, supersedes the simpler `json_schema` string above.
     */
    structuredOutput?: StructuredOutputOptions | undefined;
    /**
     * Enable per-token/cost dashboard tracking for SDKs that surface live
     * generation telemetry. No-op for backends without a telemetry sink.
     */
    enableRealTimeTracking: boolean;
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
    /**
     * Optional aggregated performance metrics. Web SDK surfaces this as a
     * separate object alongside the result; consumers may ignore it if they
     * already use the per-field timings above.
     */
    performance?: PerformanceMetrics | undefined;
    /**
     * Where the generation actually ran (on-device, cloud, etc.). Useful
     * when execution_target was AUTO and the SDK picked the route.
     */
    executedOn?: ExecutionTarget | undefined;
    /**
     * Structured-output validation details, when a structured-output request
     * was used. Mirrors the Swift/RN validation payload.
     */
    structuredOutputValidation?: StructuredOutputValidation | undefined;
    /**
     * Total tokens consumed (prompt + completion). Some C ABI paths expose
     * this directly; consumers may also compute it from the per-field counts.
     */
    totalTokens: number;
    /**
     * Backend error text for result-producing APIs that return a terminal
     * result envelope instead of throwing through the host language.
     */
    errorMessage?: string | undefined;
}
/**
 * ---------------------------------------------------------------------------
 * Lightweight LLM configuration used at component-init time (Swift
 * LLMConfiguration in LLMTypes.swift:15). Distinct from LLMGenerationOptions
 * — this is the "load the model" knob set, not the per-call sampling knobs.
 * ---------------------------------------------------------------------------
 */
export interface LLMConfiguration {
    /** Model context window length in tokens. 0 = use model default. */
    contextLength: number;
    /** Default sampling temperature applied when a per-call value is unset. */
    temperature: number;
    /** Default max output tokens applied when a per-call value is unset. */
    maxTokens: number;
    /** Default system prompt baked into the component. Empty = no default. */
    systemPrompt?: string | undefined;
    /** Whether streaming generation is enabled by default for this component. */
    streaming: boolean;
    /**
     * Model identifier/path resolved by the component loader. Present in the
     * C ABI rac_llm_config_t and needed for generated-proto service handles.
     */
    modelId?: string | undefined;
    /**
     * Preferred inference framework for this component. UNSPECIFIED / absent
     * means "auto".
     */
    preferredFramework?: InferenceFramework | undefined;
}
/**
 * ---------------------------------------------------------------------------
 * Per-prompt generation hints (Swift GenerationHints in LLMTypes.swift:550).
 * Carried alongside a prompt as a "soft" override of LLMConfiguration
 * defaults when the engine has no explicit LLMGenerationOptions to use.
 * ---------------------------------------------------------------------------
 */
export interface GenerationHints {
    /** Suggested sampling temperature. */
    temperature: number;
    /** Suggested max output tokens. */
    maxTokens: number;
    /**
     * Suggested role to use for the system prompt (e.g. "system", "developer").
     * Empty = engine default ("system").
     */
    systemRole?: string | undefined;
}
/**
 * ---------------------------------------------------------------------------
 * Pattern used to extract a model's "thinking" / reasoning block from its
 * raw output (Swift ThinkingTagPattern in LLMTypes.swift:344). Used by
 * Qwen3 and LFM2 family models that emit <think>...</think> wrappers.
 * ---------------------------------------------------------------------------
 */
export interface ThinkingTagPattern {
    /** Opening tag string. Default if empty: "<think>". */
    openingTag: string;
    /** Closing tag string. Default if empty: "</think>". */
    closingTag: string;
}
/**
 * ---------------------------------------------------------------------------
 * Single streamed token (Swift StreamToken in LLMTypes.swift:563). Emitted
 * once per token in streaming mode.
 * ---------------------------------------------------------------------------
 */
export interface StreamToken {
    /** Decoded text fragment for this token. */
    text: string;
    /** Wall-clock timestamp (ms since Unix epoch) the token was produced. */
    timestampMs: number;
    /** Sequence index within the current generation (0-based). */
    index: number;
}
/**
 * ---------------------------------------------------------------------------
 * Aggregated performance metrics for a generation (Web SDK
 * PerformanceMetrics in types/models.ts:57). Higher-level summary that
 * rolls up the timing fields scattered across LLMGenerationResult.
 * ---------------------------------------------------------------------------
 */
export interface PerformanceMetrics {
    /** Total latency from request to last token, in milliseconds. */
    latencyMs: number;
    /** Peak memory used by the inference engine, in bytes. */
    memoryBytes: number;
    /** Decode throughput in tokens/second. */
    throughputTokensPerSec: number;
    /** Prompt (input) token count. */
    promptTokens: number;
    /** Completion (output) token count. */
    completionTokens: number;
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
export declare const LLMConfiguration: {
    encode(message: LLMConfiguration, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): LLMConfiguration;
    fromJSON(object: any): LLMConfiguration;
    toJSON(message: LLMConfiguration): unknown;
    create<I extends Exact<DeepPartial<LLMConfiguration>, I>>(base?: I): LLMConfiguration;
    fromPartial<I extends Exact<DeepPartial<LLMConfiguration>, I>>(object: I): LLMConfiguration;
};
export declare const GenerationHints: {
    encode(message: GenerationHints, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): GenerationHints;
    fromJSON(object: any): GenerationHints;
    toJSON(message: GenerationHints): unknown;
    create<I extends Exact<DeepPartial<GenerationHints>, I>>(base?: I): GenerationHints;
    fromPartial<I extends Exact<DeepPartial<GenerationHints>, I>>(object: I): GenerationHints;
};
export declare const ThinkingTagPattern: {
    encode(message: ThinkingTagPattern, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ThinkingTagPattern;
    fromJSON(object: any): ThinkingTagPattern;
    toJSON(message: ThinkingTagPattern): unknown;
    create<I extends Exact<DeepPartial<ThinkingTagPattern>, I>>(base?: I): ThinkingTagPattern;
    fromPartial<I extends Exact<DeepPartial<ThinkingTagPattern>, I>>(object: I): ThinkingTagPattern;
};
export declare const StreamToken: {
    encode(message: StreamToken, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): StreamToken;
    fromJSON(object: any): StreamToken;
    toJSON(message: StreamToken): unknown;
    create<I extends Exact<DeepPartial<StreamToken>, I>>(base?: I): StreamToken;
    fromPartial<I extends Exact<DeepPartial<StreamToken>, I>>(object: I): StreamToken;
};
export declare const PerformanceMetrics: {
    encode(message: PerformanceMetrics, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): PerformanceMetrics;
    fromJSON(object: any): PerformanceMetrics;
    toJSON(message: PerformanceMetrics): unknown;
    create<I extends Exact<DeepPartial<PerformanceMetrics>, I>>(base?: I): PerformanceMetrics;
    fromPartial<I extends Exact<DeepPartial<PerformanceMetrics>, I>>(object: I): PerformanceMetrics;
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