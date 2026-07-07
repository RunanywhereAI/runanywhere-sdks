import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
export declare const protobufPackage = "runanywhere.v1";
export declare enum RAGStreamEventKind {
    RAG_STREAM_EVENT_KIND_UNSPECIFIED = 0,
    RAG_STREAM_EVENT_KIND_RETRIEVAL_STARTED = 1,
    RAG_STREAM_EVENT_KIND_CHUNK_RETRIEVED = 2,
    RAG_STREAM_EVENT_KIND_CONTEXT_READY = 3,
    RAG_STREAM_EVENT_KIND_TOKEN = 4,
    RAG_STREAM_EVENT_KIND_COMPLETED = 5,
    RAG_STREAM_EVENT_KIND_ERROR = 6,
    UNRECOGNIZED = -1
}
export declare function rAGStreamEventKindFromJSON(object: any): RAGStreamEventKind;
export declare function rAGStreamEventKindToJSON(object: RAGStreamEventKind): string;
/**
 * ---------------------------------------------------------------------------
 * RAGConfiguration — low-level pipeline config.
 *
 * This message carries *model ids*, not filesystem paths.
 * The commons RAG session ABI (rac_rag_session_create_proto) is responsible
 * for resolving those ids to on-disk paths through the canonical model
 * registry. SDK callers MUST register the embedding / LLM / reranker models
 * first and pass only their ids here.
 * ---------------------------------------------------------------------------
 */
export interface RAGConfiguration {
    /**
     * Registered id of the embedding model (required, e.g. "bge-small-en-v1.5").
     * Commons resolves this to the primary artifact path via the model registry.
     */
    embeddingModelId: string;
    /**
     * Registered id of the LLM model (e.g. "qwen3-4b-q4_k_m"). Optional —
     * leave empty to create an embed-only / retrieval-only pipeline.
     */
    llmModelId: string;
    /**
     * Embedding vector dimension — must match the embedding model.
     * Common: 384 (all-MiniLM-L6-v2), 768 (bge-base), 1024 (bge-large).
     * Leave UNSET: commons derives the dimension from the loaded embedding
     * model at session create (rac_embeddings_get_info). Set only to
     * override. No rac_default on purpose — a generated defaults() that
     * stamped 384 would mark the field present and defeat the derivation.
     */
    embeddingDimension?: number | undefined;
    /**
     * Number of top chunks to retrieve per query.
     * Optional so callers can distinguish "unset" from an explicit value.
     */
    topK?: number | undefined;
    /**
     * Minimum cosine similarity threshold (0.0–1.0). Chunks below this
     * score are discarded before being passed to the LLM as context.
     * Optional so callers can distinguish "unset" from explicit 0.0
     * (accept-everything) without losing the canonical default.
     * Default is 0.0 (accept-everything): MiniLM-class sentence embeddings
     * produce cosine similarities that rarely exceed ~0.5 even for relevant
     * chunks, and chunking a document lowers each chunk's similarity further, so
     * any positive floor filters out real matches — a multi-chunk document then
     * retrieves nothing and the answer model reports "no information". top_k
     * bounds the result count instead of a similarity floor.
     */
    similarityThreshold?: number | undefined;
    /**
     * Tokens per chunk when splitting documents during ingestion.
     * Optional so callers can distinguish "unset" from an explicit value.
     */
    chunkSize?: number | undefined;
    /**
     * Overlap tokens between consecutive chunks. Must be < chunk_size.
     * Optional so callers can explicitly request zero overlap (no overlap)
     * without it being silently replaced by the canonical default of 64.
     */
    chunkOverlap?: number | undefined;
    /**
     * Maximum tokens of retrieved context passed to the LLM.
     * Optional so callers can distinguish "unset" from an explicit value.
     */
    maxContextTokens?: number | undefined;
    /** Prompt template with `{context}` and `{query}` placeholders. */
    promptTemplate?: string | undefined;
    /** Backend-specific config JSON passed to the embedding model/provider. */
    embeddingConfigJson?: string | undefined;
    /** Backend-specific config JSON passed to the LLM provider. */
    llmConfigJson?: string | undefined;
    /** Index persistence and retrieval behavior. Empty path = in-memory index. */
    indexPath?: string | undefined;
    persistIndex: boolean;
    rerankResults: boolean;
    /** Registered id of the reranker model (optional). */
    rerankerModelId?: string | undefined;
}
/**
 * ---------------------------------------------------------------------------
 * RAGDocument — batch-ingest input item.
 * ---------------------------------------------------------------------------
 */
export interface RAGDocument {
    /** Optional caller-supplied document id. */
    id: string;
    /** Plain text content to chunk/embed. */
    text: string;
    /** Typed metadata map for generated-proto callers. */
    metadata: {
        [key: string]: string;
    };
    /**
     * Adapter-normalized document source. Pickers, sandbox bookmarks, and
     * platform file access remain SDK-owned.
     */
    sourceUri?: string | undefined;
    adapterHandle?: string | undefined;
    mediaType?: string | undefined;
    sizeBytes: number;
}
export interface RAGDocument_MetadataEntry {
    key: string;
    value: string;
}
export interface RAGIngestRequest {
    requestId: string;
    documents: RAGDocument[];
    replaceExisting: boolean;
    metadata: {
        [key: string]: string;
    };
}
export interface RAGIngestRequest_MetadataEntry {
    key: string;
    value: string;
}
/**
 * ---------------------------------------------------------------------------
 * RAGQueryOptions — per-query sampling and prompt overrides.
 * ---------------------------------------------------------------------------
 */
export interface RAGQueryOptions {
    /** The user question to answer. Required (empty = no-op). */
    question: string;
    /** Optional system prompt override. Unset uses the pipeline default. */
    systemPrompt?: string | undefined;
    /** Maximum tokens to generate in the answer. */
    maxTokens: number;
    /** Sampling temperature. 0.0 = greedy, higher = more random. */
    temperature: number;
    /** Nucleus (top-p) sampling parameter. 1.0 = disabled. */
    topP: number;
    /** Top-k sampling parameter. 0 = disabled. */
    topK: number;
    /** Retrieval overrides. 0/unset = use RAGConfiguration defaults. */
    retrievalTopK: number;
    /**
     * Per-query similarity floor. `optional` so an explicit 0.0 (accept
     * everything) is distinguishable from "unset" and can override a positive
     * session-level default; unset falls back to RAGConfiguration.
     */
    similarityThreshold?: number | undefined;
    stream: boolean;
    /**
     * When true, suppress the answer model's thinking phase (maps to
     * LLMGenerationOptions.disable_thinking so commons prepends the no-think
     * directive instead of the app injecting "/no_think"). Default false.
     */
    disableThinking: boolean;
    /**
     * Multi-query expansion: when true, the answer LLM rewrites the question
     * into `multi_query_count` variants; retrieval runs for the original plus
     * each variant and the rankings are RRF-fused before rerank. Falls back to
     * a single query if expansion yields nothing.
     */
    enableMultiQuery: boolean;
    multiQueryCount?: number | undefined;
    /**
     * Scoped retrieval: when set, only chunks whose document id begins with
     * this prefix are eligible (e.g. a chat/collection namespace). Unset =
     * search the whole index.
     */
    scopePrefix?: string | undefined;
}
export interface RAGQueryRequest {
    requestId: string;
    options?: RAGQueryOptions | undefined;
    metadata: {
        [key: string]: string;
    };
}
export interface RAGQueryRequest_MetadataEntry {
    key: string;
    value: string;
}
/**
 * ---------------------------------------------------------------------------
 * RAGSearchResult — a single retrieved document chunk with similarity score.
 * ---------------------------------------------------------------------------
 */
export interface RAGSearchResult {
    /** Unique identifier of the chunk (assigned at ingestion time). */
    chunkId: string;
    /** Text content of the chunk (the actual snippet shown to the LLM). */
    text: string;
    /** Cosine similarity score (0.0–1.0). Higher = more relevant. */
    similarityScore: number;
    /**
     * Optional source document identifier (filename, URL, or document ID).
     * Set when the chunk's origin is tracked at ingestion time.
     */
    sourceDocument?: string | undefined;
    /**
     * Free-form metadata associated with the chunk (e.g. page number, section,
     * ingestion timestamp). Pre-IDL all SDKs encoded this as a JSON string;
     * canonicalized here as a typed map so consumers don't re-parse.
     */
    metadata: {
        [key: string]: string;
    };
    rank: number;
    startOffset: number;
    endOffset: number;
    tokenCount: number;
}
export interface RAGSearchResult_MetadataEntry {
    key: string;
    value: string;
}
/**
 * ---------------------------------------------------------------------------
 * RAGResult — the full result of a RAG query.
 * ---------------------------------------------------------------------------
 */
export interface RAGResult {
    /** The LLM-generated answer grounded in the retrieved context. */
    answer: string;
    /**
     * Document chunks retrieved during vector search and used as context.
     * Order matches retrieval rank (highest similarity first).
     */
    retrievedChunks: RAGSearchResult[];
    /**
     * Full context string passed to the LLM (chunks joined into a prompt).
     * May be empty for queries with no matching chunks.
     */
    contextUsed: string;
    /** Time spent in the retrieval phase (vector search), in milliseconds. */
    retrievalTimeMs: number;
    /** Time spent in the LLM generation phase, in milliseconds. */
    generationTimeMs: number;
    /**
     * Total end-to-end query time (retrieval + generation + overhead),
     * in milliseconds.
     */
    totalTimeMs: number;
    promptTokens: number;
    completionTokens: number;
    totalTokens: number;
    errorMessage?: string | undefined;
    errorCode: number;
    requestId: string;
    /** Optional thinking/reasoning content extracted from the answer. */
    thinkingContent?: string | undefined;
}
/**
 * ---------------------------------------------------------------------------
 * RAGStatistics — index-level counters for the RAG pipeline.
 *
 * Returned by RunAnywhere.rag.statistics() / ragGetStatistics().
 * ---------------------------------------------------------------------------
 */
export interface RAGStatistics {
    /** Total number of documents ever ingested into the index. */
    indexedDocuments: number;
    /** Total number of chunks across all indexed documents. */
    indexedChunks: number;
    /** Approximate total token count across all indexed chunks. */
    totalTokensIndexed: number;
    /**
     * Wall-clock timestamp of the most recent ingestion, in milliseconds
     * since Unix epoch. 0 = no ingestion yet.
     */
    lastUpdatedMs: number;
    /**
     * Filesystem path to the on-disk index, when applicable. Unset for
     * in-memory-only indexes.
     */
    indexPath?: string | undefined;
    /**
     * Raw backend statistics JSON for implementations that cannot yet project
     * every counter into typed fields.
     */
    statsJson?: string | undefined;
    /** Approximate vector-store footprint in bytes, when known. */
    vectorStoreSizeBytes: number;
    isPersistent: boolean;
    lastQueryMs: number;
    errorMessage?: string | undefined;
    errorCode: number;
}
export interface RAGIngestResult {
    requestId: string;
    documentsIngested: number;
    chunksIngested: number;
    statistics?: RAGStatistics | undefined;
    errorMessage?: string | undefined;
    errorCode: number;
}
export interface RAGStreamEvent {
    seq: number;
    timestampUs: number;
    requestId: string;
    kind: RAGStreamEventKind;
    chunk?: RAGSearchResult | undefined;
    token: string;
    result?: RAGResult | undefined;
    errorMessage?: string | undefined;
    errorCode: number;
}
export interface RAGServiceState {
    isReady: boolean;
    statistics?: RAGStatistics | undefined;
    isIndexing: boolean;
    isQuerying: boolean;
    activeRequestId?: string | undefined;
    errorMessage?: string | undefined;
    errorCode: number;
}
export declare const RAGConfiguration: MessageFns<RAGConfiguration>;
export declare const RAGDocument: MessageFns<RAGDocument>;
export declare const RAGDocument_MetadataEntry: MessageFns<RAGDocument_MetadataEntry>;
export declare const RAGIngestRequest: MessageFns<RAGIngestRequest>;
export declare const RAGIngestRequest_MetadataEntry: MessageFns<RAGIngestRequest_MetadataEntry>;
export declare const RAGQueryOptions: MessageFns<RAGQueryOptions>;
export declare const RAGQueryRequest: MessageFns<RAGQueryRequest>;
export declare const RAGQueryRequest_MetadataEntry: MessageFns<RAGQueryRequest_MetadataEntry>;
export declare const RAGSearchResult: MessageFns<RAGSearchResult>;
export declare const RAGSearchResult_MetadataEntry: MessageFns<RAGSearchResult_MetadataEntry>;
export declare const RAGResult: MessageFns<RAGResult>;
export declare const RAGStatistics: MessageFns<RAGStatistics>;
export declare const RAGIngestResult: MessageFns<RAGIngestResult>;
export declare const RAGStreamEvent: MessageFns<RAGStreamEvent>;
export declare const RAGServiceState: MessageFns<RAGServiceState>;
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
