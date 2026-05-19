import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
import { InferenceFramework } from "./model_types";
export declare const protobufPackage = "runanywhere.v1";
/**
 * ---------------------------------------------------------------------------
 * Embedding normalization mode. Mirrors rac_embeddings_normalize_t.
 * ---------------------------------------------------------------------------
 */
export declare enum EmbeddingsNormalizeMode {
    EMBEDDINGS_NORMALIZE_MODE_UNSPECIFIED = 0,
    EMBEDDINGS_NORMALIZE_MODE_NONE = 1,
    EMBEDDINGS_NORMALIZE_MODE_L2 = 2,
    UNRECOGNIZED = -1
}
export declare function embeddingsNormalizeModeFromJSON(object: any): EmbeddingsNormalizeMode;
export declare function embeddingsNormalizeModeToJSON(object: EmbeddingsNormalizeMode): string;
/**
 * ---------------------------------------------------------------------------
 * Embedding pooling strategy. Mirrors rac_embeddings_pooling_t.
 * ---------------------------------------------------------------------------
 */
export declare enum EmbeddingsPoolingStrategy {
    EMBEDDINGS_POOLING_STRATEGY_UNSPECIFIED = 0,
    EMBEDDINGS_POOLING_STRATEGY_MEAN = 1,
    EMBEDDINGS_POOLING_STRATEGY_CLS = 2,
    EMBEDDINGS_POOLING_STRATEGY_LAST = 3,
    UNRECOGNIZED = -1
}
export declare function embeddingsPoolingStrategyFromJSON(object: any): EmbeddingsPoolingStrategy;
export declare function embeddingsPoolingStrategyToJSON(object: EmbeddingsPoolingStrategy): string;
/**
 * ---------------------------------------------------------------------------
 * Component-level configuration applied at service creation. Mirrors the
 * transport-portable subset of rac_embeddings_config_t. Backend selection
 * (preferred_framework) and pooling strategy live outside the wire schema.
 * ---------------------------------------------------------------------------
 */
export interface EmbeddingsConfiguration {
    /** Model identifier (registry id or local path). Required. */
    modelId: string;
    /**
     * Output vector dimension. Must match the loaded model's hidden size
     * (e.g. 384 for all-MiniLM-L6-v2, 768 for bge-base, 1024 for bge-large).
     */
    embeddingDimension: number;
    /**
     * Maximum tokens per input. Truncation/sliding window is backend-decided
     * when an input exceeds this length. C ABI default: 512.
     */
    maxSequenceLength: number;
    /**
     * Default L2 normalization for produced vectors. When unset the backend
     * applies its default (RAC_EMBEDDINGS_NORMALIZE_L2 in the C ABI).
     */
    normalize?: boolean | undefined;
    /** Preferred framework for the component. Absent = auto. */
    preferredFramework?: InferenceFramework | undefined;
    /**
     * C ABI name for max_sequence_length. 0 = use max_sequence_length or
     * backend default.
     */
    maxTokens: number;
    /**
     * Exact C ABI normalization/pooling modes for backends that need more
     * than the bool normalize flag.
     */
    normalizeMode: EmbeddingsNormalizeMode;
    pooling: EmbeddingsPoolingStrategy;
    /** Backend-specific JSON config (e.g. tokenizer/vocab companion paths). */
    configJson?: string | undefined;
}
/**
 * ---------------------------------------------------------------------------
 * Per-call generation options. Overrides for a single embed / embed_batch
 * invocation; any field left unset falls back to the configuration default.
 * ---------------------------------------------------------------------------
 */
export interface EmbeddingsOptions {
    /**
     * Apply L2 normalization to the produced vectors. Required so the wire
     * form is unambiguous on the most common knob; backends may still defer
     * to model defaults at load time.
     */
    normalize: boolean;
    /**
     * Truncate inputs longer than max_sequence_length instead of erroring.
     * Unset = backend default (currently truncate-on-overflow for ONNX,
     * sliding-window for llama.cpp).
     */
    truncate?: boolean | undefined;
    /**
     * Override batch size for embed_batch. Unset = backend chooses
     * (RAC_EMBEDDINGS_DEFAULT_BATCH_SIZE = 512, capped at 8192).
     */
    batchSize?: number | undefined;
    /** Exact C ABI per-call overrides. UNSPECIFIED = use component config. */
    normalizeMode: EmbeddingsNormalizeMode;
    pooling: EmbeddingsPoolingStrategy;
    /** 0 = auto */
    nThreads: number;
}
/**
 * ---------------------------------------------------------------------------
 * A single embedding produced for one input text. The C ABI ships dense
 * floats with an associated dimension; we additionally carry the source text
 * (helps multi-input batch consumers correlate vectors with inputs without
 * holding the request side-by-side) and an optional pre-computed L2 norm
 * (lets clients short-circuit cosine-similarity when both sides know the
 * vectors are already unit-normalized).
 * ---------------------------------------------------------------------------
 */
export interface EmbeddingVector {
    /** Dense float vector. Length equals EmbeddingsResult.dimension. */
    values: number[];
    /**
     * L2 norm of `values`. Optional — populated when the backend computes
     * it (typically when normalize=false and the consumer wants to score
     * similarity without recomputing).
     */
    norm?: number | undefined;
    /**
     * Source text that produced this vector. Optional — preserved for
     * multi-input batches where the caller wants to correlate without
     * tracking ordering separately.
     */
    text?: string | undefined;
    /**
     * Vector dimension for consumers that need per-vector sizing without
     * inspecting EmbeddingsResult.dimension.
     */
    dimension: number;
    /** Input index in the original request and optional caller metadata. */
    inputIndex: number;
    metadata: {
        [key: string]: string;
    };
}
export interface EmbeddingVector_MetadataEntry {
    key: string;
    value: string;
}
/**
 * ---------------------------------------------------------------------------
 * Request envelope for service-handle APIs. One text = embed, multiple texts =
 * embed_batch.
 * ---------------------------------------------------------------------------
 */
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
/**
 * ---------------------------------------------------------------------------
 * Result of an embed / embed_batch call. Mirrors rac_embeddings_result_t
 * (which is array-of-vectors + dimension + processing_time_ms +
 * total_tokens). `dimension` is duplicated at the result level so consumers
 * can size buffers without inspecting an arbitrary vector first.
 * ---------------------------------------------------------------------------
 */
export interface EmbeddingsResult {
    /** One vector per input text, in input order. */
    vectors: EmbeddingVector[];
    /**
     * Vector dimension. Duplicated from each EmbeddingVector for O(1)
     * sizing on the consumer side.
     */
    dimension: number;
    /** Total wall-clock time for the embed / embed_batch call, in ms. */
    processingTimeMs: number;
    /** Total tokens consumed across all inputs (post-truncation). */
    tokensUsed: number;
    modelId?: string | undefined;
    errorMessage?: string | undefined;
    errorCode: number;
    requestId: string;
}
export interface EmbeddingsServiceState {
    isReady: boolean;
    currentModel?: string | undefined;
    dimension: number;
    maxTokens: number;
    errorMessage?: string | undefined;
    errorCode: number;
}
/**
 * ---------------------------------------------------------------------------
 * Session/handle creation request envelope. Mirrors the public SDK
 * `embeddingsCreate(modelId, configJson?)` calls in RN/Web/Kotlin which
 * previously dropped down to the non-proto `rac_embeddings_create*` C ABI.
 * The result carries an opaque uint64 handle the SDK uses for subsequent
 * embed / embed_batch invocations.
 * ---------------------------------------------------------------------------
 */
export interface EmbeddingsCreateRequest {
    /** Required. Model identifier (registry id) or absolute model path. */
    modelId: string;
    /**
     * Optional component configuration. When unset, commons applies its
     * defaults (RAC_EMBEDDINGS_*); when set, the named fields override
     * the per-component defaults at create time.
     */
    configuration?: EmbeddingsConfiguration | undefined;
    /**
     * Provider-specific JSON config. Mirrors the legacy
     * rac_embeddings_create_with_config(config_json) parameter for backends
     * that need companion file paths (e.g. {"vocab_path":"..."}).
     */
    configJson?: string | undefined;
}
export interface EmbeddingsCreateResult {
    /** Opaque handle (rac_handle_t cast to u64). Zero on failure. */
    handle: number;
    /**
     * Echo of the model id the caller requested — so JS/Swift/Kotlin can
     * store it next to the handle without re-parsing the request.
     */
    modelId: string;
    /**
     * Backend-resolved dimension/max_tokens after load. 0 = unknown until
     * the first embed call.
     */
    dimension: number;
    maxTokens: number;
    /**
     * Negative on failure; mirrors rac_result_t. Empty error_message on
     * success.
     */
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
export declare const EmbeddingsServiceState: MessageFns<EmbeddingsServiceState>;
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
