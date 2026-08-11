import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
import { SDKError } from "./errors";
export declare const protobufPackage = "runanywhere.v1";
/**
 * The required public spelling in every SDK is exactly "mean" / "cls" / "last".
 * LAST is the final token's hidden state (llama.cpp --pooling last), which
 * decoder-style embedders require. It is NOT max-pooling; no SDK may expose
 * it as "max".
 */
export declare enum EmbeddingsPoolingStrategy {
    /** EMBEDDINGS_POOLING_STRATEGY_UNSPECIFIED - inherit the bundle's pooling */
    EMBEDDINGS_POOLING_STRATEGY_UNSPECIFIED = 0,
    EMBEDDINGS_POOLING_STRATEGY_MEAN = 1,
    EMBEDDINGS_POOLING_STRATEGY_CLS = 2,
    EMBEDDINGS_POOLING_STRATEGY_LAST = 3,
    UNRECOGNIZED = -1
}
export declare function embeddingsPoolingStrategyFromJSON(object: any): EmbeddingsPoolingStrategy;
export declare function embeddingsPoolingStrategyToJSON(object: EmbeddingsPoolingStrategy): string;
export declare enum EmbeddingsInputType {
    /** EMBEDDINGS_INPUT_TYPE_UNSPECIFIED - model default / symmetric model */
    EMBEDDINGS_INPUT_TYPE_UNSPECIFIED = 0,
    EMBEDDINGS_INPUT_TYPE_QUERY = 1,
    EMBEDDINGS_INPUT_TYPE_DOCUMENT = 2,
    UNRECOGNIZED = -1
}
export declare function embeddingsInputTypeFromJSON(object: any): EmbeddingsInputType;
export declare function embeddingsInputTypeToJSON(object: EmbeddingsInputType): string;
/** Per-call overrides. Unset fields fall back to the loaded bundle's defaults. */
export interface EmbeddingsOptions {
    /**
     * true  = clip an over-long input to the model's context and embed it.
     * false = fail the call.
     * Unset = true. A backend may instead aggregate over a sliding window,
     * which embeds the whole document rather than discarding its tail.
     */
    truncate?: boolean | undefined;
    /** Unset = backend chooses (512, capped at 8192). */
    batchSize?: number | undefined;
    /**
     * L2-normalize every vector to unit length (what cosine search expects).
     * Unset = true. false returns the raw pooled vector.
     */
    normalize?: boolean | undefined;
    pooling: EmbeddingsPoolingStrategy;
    /** 0 = auto */
    nThreads: number;
    /**
     * What the vector will be used for. Asymmetric embedders (bge, e5,
     * nomic-embed, gte, EmbeddingGemma) prepend a different prompt for a query
     * than for a document. The prefix table must be added to the model manifest
     * as part of honouring this field; it does not exist today. A bundle that
     * declares no prompts ignores input_type and returns the identical vector
     * for QUERY and DOCUMENT — it never errors.
     */
    inputType: EmbeddingsInputType;
    /**
     * Matryoshka (MRL) output width: truncate each vector to this many floats
     * and re-normalize. Unset = the model's native width. Accepts any width in
     * [1, the native width]; a width the model was not MRL-trained at is
     * silently worse. This is the request-side width — EmbeddingsResult.dimension
     * reports the width actually produced.
     */
    dimensions?: number | undefined;
}
export interface EmbeddingVector {
    /** Length equals EmbeddingsResult.dimension. */
    values: number[];
    /**
     * Zero-based position in the request batch. ALWAYS set, on every entry
     * point, including index 0.
     */
    inputIndex: number;
}
/** One text = embed, multiple texts = embed_batch. */
export interface EmbeddingsRequest {
    texts: string[];
    options?: EmbeddingsOptions | undefined;
    requestId: string;
    modelId?: string | undefined;
}
export interface EmbeddingsResult {
    /** One vector per input text, in input order. */
    vectors: EmbeddingVector[];
    /** The width of every vector above, so consumers can size buffers in O(1). */
    dimension: number;
    processingTimeMs: number;
    /** Across all inputs, post-truncation. */
    tokensUsed: number;
    modelId?: string | undefined;
    requestId: string;
}
export interface EmbeddingsCreateRequest {
    /** Registry id or absolute model path. */
    modelId: string;
    /** For backends needing companion file paths, e.g. {"vocab_path":"..."}. */
    configJson?: string | undefined;
}
export interface EmbeddingsCreateResult {
    /** rac_handle_t cast to u64. Zero on failure. */
    handle: number;
    /** Echoed so callers can store it beside the handle. */
    modelId: string;
    /** Backend-resolved after load. 0 = unknown until the first embed call. */
    dimension: number;
    maxTokens: number;
    error?: SDKError | undefined;
}
export declare const EmbeddingsOptions: MessageFns<EmbeddingsOptions>;
export declare const EmbeddingVector: MessageFns<EmbeddingVector>;
export declare const EmbeddingsRequest: MessageFns<EmbeddingsRequest>;
export declare const EmbeddingsResult: MessageFns<EmbeddingsResult>;
export declare const EmbeddingsCreateRequest: MessageFns<EmbeddingsCreateRequest>;
export declare const EmbeddingsCreateResult: MessageFns<EmbeddingsCreateResult>;
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
