import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
export declare const protobufPackage = "runanywhere.v1";
/**
 * One token-accounting shape embedded by every result and metrics message,
 * replacing the input/output/total/throughput quadruple that was copied inline
 * across LLM, VLM, and RAG results. Names follow the OpenAI Responses API; the
 * timing fields follow llama.cpp's `timings` object, which names the phase it
 * measures.
 */
export interface TokenUsage {
    inputTokens: number;
    outputTokens: number;
    totalTokens: number;
    /**
     * Decode-phase throughput only: output_tokens / decode_ms. Excludes
     * prefill. cf. llama.cpp timings.predicted_per_second.
     */
    decodeTokensPerSecond: number;
    /**
     * Prefill (prompt eval) wall time. cf. llama.cpp timings.prompt_ms,
     * Ollama prompt_eval_duration. 0 when the backend does not report it.
     */
    prefillMs: number;
    /**
     * Request start to first output token of any kind (reasoning or content).
     * The canonical spelling for every result type: LLMGenerationResult and
     * VLMResult report TTFT here and nowhere else. SDKEvent's own telemetry
     * fields (GenerationEvent.time_to_first_token_ms, first_token_latency_ms)
     * keep their separate event-stream spelling.
     */
    ttftMs: number;
    /**
     * Request start to the first CONTENT delta — what the user actually waits
     * for when the model reasons first. 0 when no content token was ever
     * delivered. Distinct from ttft_ms; do not alias the two.
     */
    timeToFirstContentTokenMs: number;
    /**
     * Content-only throughput over first-content-delta → last delta. Excludes
     * reasoning tokens the accelerator also decoded. 0 when content count or
     * window is unavailable.
     */
    contentTokensPerSecond: number;
    /**
     * True when the backend buffered the whole generation and flushed deltas
     * at once, so the decode window is an artifact of the flush. Platforms
     * must not re-derive this heuristic.
     */
    batchBuffered: boolean;
    /**
     * True when input_tokens / output_tokens were estimated (e.g. chars/4)
     * rather than reported by the engine. Absence of the flag (false) means
     * the counts are engine-measured.
     */
    countsEstimated: boolean;
}
export declare const TokenUsage: MessageFns<TokenUsage>;
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
