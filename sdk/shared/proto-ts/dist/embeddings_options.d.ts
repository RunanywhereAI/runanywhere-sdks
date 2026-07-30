import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
import { InferenceFramework } from "./model_types";
export declare const protobufPackage = "runanywhere.v1";
export declare enum EmbeddingsNormalizeMode {
    EMBEDDINGS_NORMALIZE_MODE_UNSPECIFIED = 0,
    EMBEDDINGS_NORMALIZE_MODE_NONE = 1,
    EMBEDDINGS_NORMALIZE_MODE_L2 = 2,
    UNRECOGNIZED = -1
}
export declare function embeddingsNormalizeModeFromJSON(object: any): EmbeddingsNormalizeMode;
export declare function embeddingsNormalizeModeToJSON(object: EmbeddingsNormalizeMode): string;
export declare enum EmbeddingsPoolingStrategy {
    EMBEDDINGS_POOLING_STRATEGY_UNSPECIFIED = 0,
    EMBEDDINGS_POOLING_STRATEGY_MEAN = 1,
    EMBEDDINGS_POOLING_STRATEGY_CLS = 2,
    EMBEDDINGS_POOLING_STRATEGY_LAST = 3,
    UNRECOGNIZED = -1
}
export declare function embeddingsPoolingStrategyFromJSON(object: any): EmbeddingsPoolingStrategy;
export declare function embeddingsPoolingStrategyToJSON(object: EmbeddingsPoolingStrategy): string;
/** Applied at service creation. */
export interface EmbeddingsConfiguration {
    /** Registry id or local path. */
    modelId: string;
    /**
     * Must match the loaded model's hidden size: 384 for all-MiniLM-L6-v2,
     * 768 for bge-base, 1024 for bge-large.
     */
    embeddingDimension: number;
    /** Truncation or sliding window past this length is backend-decided. */
    maxSequenceLength: number;
    preferredFramework?: InferenceFramework | undefined;
    normalizeMode: EmbeddingsNormalizeMode;
    pooling: EmbeddingsPoolingStrategy;
    /** Backend-specific config such as tokenizer or vocab companion paths. */
    configJson?: string | undefined;
}
/** Per-call overrides. Unset fields fall back to the component configuration. */
export interface EmbeddingsOptions {
    /**
     * Truncate over-long inputs instead of erroring. Unset = backend default,
     * currently truncate-on-overflow for ONNX and sliding-window for llama.cpp.
     */
    truncate?: boolean | undefined;
    /** Unset = backend chooses (512, capped at 8192). */
    batchSize?: number | undefined;
    /** UNSPECIFIED = use the component config. */
    normalizeMode: EmbeddingsNormalizeMode;
    pooling: EmbeddingsPoolingStrategy;
    /** 0 = auto */
    nThreads: number;
}
export interface EmbeddingVector {
    /** Length equals EmbeddingsResult.dimension. */
    values: number[];
    /**
     * Populated when the backend computes it, letting consumers score
     * similarity without recomputing.
     */
    norm?: number | undefined;
    /** Lets batch callers correlate vectors with inputs without tracking order. */
    text?: string | undefined;
    dimension: number;
    inputIndex: number;
    metadata: {
        [key: string]: string;
    };
}
export interface EmbeddingVector_MetadataEntry {
    key: string;
    value: string;
}
/** One text = embed, multiple texts = embed_batch. */
export interface EmbeddingsRequest {
    texts: string[];
    options?: EmbeddingsOptions | undefined;
    requestId: string;
    modelId?: string | undefined;
    metadata: {
        [key: string]: string;
    };
}
export interface EmbeddingsRequest_MetadataEntry {
    key: string;
    value: string;
}
export interface EmbeddingsResult {
    /** One vector per input text, in input order. */
    vectors: EmbeddingVector[];
    /** Duplicated from each vector so consumers can size buffers in O(1). */
    dimension: number;
    processingTimeMs: number;
    /** Across all inputs, post-truncation. */
    tokensUsed: number;
    modelId?: string | undefined;
    errorMessage?: string | undefined;
    errorCode: number;
    requestId: string;
}
export interface EmbeddingsCreateRequest {
    /** Registry id or absolute model path. */
    modelId: string;
    /** Unset = commons defaults; set fields override per-component defaults. */
    configuration?: EmbeddingsConfiguration | undefined;
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
    /** Mirrors rac_result_t; negative on failure. */
    errorCode: number;
    errorMessage: string;
}
export declare const EmbeddingsConfiguration: MessageFns<EmbeddingsConfiguration>;
export declare const EmbeddingsOptions: MessageFns<EmbeddingsOptions>;
export declare const EmbeddingVector: MessageFns<EmbeddingVector>;
export declare const EmbeddingVector_MetadataEntry: MessageFns<EmbeddingVector_MetadataEntry>;
export declare const EmbeddingsRequest: MessageFns<EmbeddingsRequest>;
export declare const EmbeddingsRequest_MetadataEntry: MessageFns<EmbeddingsRequest_MetadataEntry>;
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
