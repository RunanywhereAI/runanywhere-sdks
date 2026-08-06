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
     * Request start to first output token. The canonical spelling for every
     * result type: LLMGenerationResult, LLMStreamFinalResult and VLMResult all
     * report TTFT here and nowhere else. SDKEvent's own telemetry fields
     * (GenerationEvent.time_to_first_token_ms, first_token_latency_ms) keep
     * their separate event-stream spelling.
     */
    ttftMs: number;
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
