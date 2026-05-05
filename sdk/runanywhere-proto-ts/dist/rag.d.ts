import _m0 from "protobufjs/minimal";
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
 * As of D-6 (Wave D) this message carries *model ids*, not filesystem paths.
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
     */
    embeddingDimension: number;
    /** Number of top chunks to retrieve per query. */
    topK: number;
    /**
     * Minimum cosine similarity threshold (0.0–1.0). Chunks below this
     * score are discarded before being passed to the LLM as context.
     */
    similarityThreshold: number;
    /** Tokens per chunk when splitting documents during ingestion. */
    chunkSize: number;
    /** Overlap tokens between consecutive chunks. Must be < chunk_size. */
    chunkOverlap: number;
    /** Maximum tokens of retrieved context passed to the LLM. */
    maxContextTokens: number;
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
    similarityThreshold: number;
    stream: boolean;
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
export declare const RAGConfiguration: {
    encode(message: RAGConfiguration, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): RAGConfiguration;
    fromJSON(object: any): RAGConfiguration;
    toJSON(message: RAGConfiguration): unknown;
    create<I extends Exact<DeepPartial<RAGConfiguration>, I>>(base?: I): RAGConfiguration;
    fromPartial<I extends Exact<DeepPartial<RAGConfiguration>, I>>(object: I): RAGConfiguration;
};
export declare const RAGDocument: {
    encode(message: RAGDocument, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): RAGDocument;
    fromJSON(object: any): RAGDocument;
    toJSON(message: RAGDocument): unknown;
    create<I extends Exact<DeepPartial<RAGDocument>, I>>(base?: I): RAGDocument;
    fromPartial<I extends Exact<DeepPartial<RAGDocument>, I>>(object: I): RAGDocument;
};
export declare const RAGDocument_MetadataEntry: {
    encode(message: RAGDocument_MetadataEntry, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): RAGDocument_MetadataEntry;
    fromJSON(object: any): RAGDocument_MetadataEntry;
    toJSON(message: RAGDocument_MetadataEntry): unknown;
    create<I extends Exact<DeepPartial<RAGDocument_MetadataEntry>, I>>(base?: I): RAGDocument_MetadataEntry;
    fromPartial<I extends Exact<DeepPartial<RAGDocument_MetadataEntry>, I>>(object: I): RAGDocument_MetadataEntry;
};
export declare const RAGIngestRequest: {
    encode(message: RAGIngestRequest, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): RAGIngestRequest;
    fromJSON(object: any): RAGIngestRequest;
    toJSON(message: RAGIngestRequest): unknown;
    create<I extends Exact<DeepPartial<RAGIngestRequest>, I>>(base?: I): RAGIngestRequest;
    fromPartial<I extends Exact<DeepPartial<RAGIngestRequest>, I>>(object: I): RAGIngestRequest;
};
export declare const RAGIngestRequest_MetadataEntry: {
    encode(message: RAGIngestRequest_MetadataEntry, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): RAGIngestRequest_MetadataEntry;
    fromJSON(object: any): RAGIngestRequest_MetadataEntry;
    toJSON(message: RAGIngestRequest_MetadataEntry): unknown;
    create<I extends Exact<DeepPartial<RAGIngestRequest_MetadataEntry>, I>>(base?: I): RAGIngestRequest_MetadataEntry;
    fromPartial<I extends Exact<DeepPartial<RAGIngestRequest_MetadataEntry>, I>>(object: I): RAGIngestRequest_MetadataEntry;
};
export declare const RAGQueryOptions: {
    encode(message: RAGQueryOptions, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): RAGQueryOptions;
    fromJSON(object: any): RAGQueryOptions;
    toJSON(message: RAGQueryOptions): unknown;
    create<I extends Exact<DeepPartial<RAGQueryOptions>, I>>(base?: I): RAGQueryOptions;
    fromPartial<I extends Exact<DeepPartial<RAGQueryOptions>, I>>(object: I): RAGQueryOptions;
};
export declare const RAGQueryRequest: {
    encode(message: RAGQueryRequest, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): RAGQueryRequest;
    fromJSON(object: any): RAGQueryRequest;
    toJSON(message: RAGQueryRequest): unknown;
    create<I extends Exact<DeepPartial<RAGQueryRequest>, I>>(base?: I): RAGQueryRequest;
    fromPartial<I extends Exact<DeepPartial<RAGQueryRequest>, I>>(object: I): RAGQueryRequest;
};
export declare const RAGQueryRequest_MetadataEntry: {
    encode(message: RAGQueryRequest_MetadataEntry, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): RAGQueryRequest_MetadataEntry;
    fromJSON(object: any): RAGQueryRequest_MetadataEntry;
    toJSON(message: RAGQueryRequest_MetadataEntry): unknown;
    create<I extends Exact<DeepPartial<RAGQueryRequest_MetadataEntry>, I>>(base?: I): RAGQueryRequest_MetadataEntry;
    fromPartial<I extends Exact<DeepPartial<RAGQueryRequest_MetadataEntry>, I>>(object: I): RAGQueryRequest_MetadataEntry;
};
export declare const RAGSearchResult: {
    encode(message: RAGSearchResult, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): RAGSearchResult;
    fromJSON(object: any): RAGSearchResult;
    toJSON(message: RAGSearchResult): unknown;
    create<I extends Exact<DeepPartial<RAGSearchResult>, I>>(base?: I): RAGSearchResult;
    fromPartial<I extends Exact<DeepPartial<RAGSearchResult>, I>>(object: I): RAGSearchResult;
};
export declare const RAGSearchResult_MetadataEntry: {
    encode(message: RAGSearchResult_MetadataEntry, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): RAGSearchResult_MetadataEntry;
    fromJSON(object: any): RAGSearchResult_MetadataEntry;
    toJSON(message: RAGSearchResult_MetadataEntry): unknown;
    create<I extends Exact<DeepPartial<RAGSearchResult_MetadataEntry>, I>>(base?: I): RAGSearchResult_MetadataEntry;
    fromPartial<I extends Exact<DeepPartial<RAGSearchResult_MetadataEntry>, I>>(object: I): RAGSearchResult_MetadataEntry;
};
export declare const RAGResult: {
    encode(message: RAGResult, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): RAGResult;
    fromJSON(object: any): RAGResult;
    toJSON(message: RAGResult): unknown;
    create<I extends Exact<DeepPartial<RAGResult>, I>>(base?: I): RAGResult;
    fromPartial<I extends Exact<DeepPartial<RAGResult>, I>>(object: I): RAGResult;
};
export declare const RAGStatistics: {
    encode(message: RAGStatistics, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): RAGStatistics;
    fromJSON(object: any): RAGStatistics;
    toJSON(message: RAGStatistics): unknown;
    create<I extends Exact<DeepPartial<RAGStatistics>, I>>(base?: I): RAGStatistics;
    fromPartial<I extends Exact<DeepPartial<RAGStatistics>, I>>(object: I): RAGStatistics;
};
export declare const RAGIngestResult: {
    encode(message: RAGIngestResult, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): RAGIngestResult;
    fromJSON(object: any): RAGIngestResult;
    toJSON(message: RAGIngestResult): unknown;
    create<I extends Exact<DeepPartial<RAGIngestResult>, I>>(base?: I): RAGIngestResult;
    fromPartial<I extends Exact<DeepPartial<RAGIngestResult>, I>>(object: I): RAGIngestResult;
};
export declare const RAGStreamEvent: {
    encode(message: RAGStreamEvent, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): RAGStreamEvent;
    fromJSON(object: any): RAGStreamEvent;
    toJSON(message: RAGStreamEvent): unknown;
    create<I extends Exact<DeepPartial<RAGStreamEvent>, I>>(base?: I): RAGStreamEvent;
    fromPartial<I extends Exact<DeepPartial<RAGStreamEvent>, I>>(object: I): RAGStreamEvent;
};
export declare const RAGServiceState: {
    encode(message: RAGServiceState, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): RAGServiceState;
    fromJSON(object: any): RAGServiceState;
    toJSON(message: RAGServiceState): unknown;
    create<I extends Exact<DeepPartial<RAGServiceState>, I>>(base?: I): RAGServiceState;
    fromPartial<I extends Exact<DeepPartial<RAGServiceState>, I>>(object: I): RAGServiceState;
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
//# sourceMappingURL=rag.d.ts.map