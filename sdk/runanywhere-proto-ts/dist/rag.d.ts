import _m0 from "protobufjs/minimal";
export declare const protobufPackage = "runanywhere.v1";
/**
 * ---------------------------------------------------------------------------
 * RAGConfiguration — low-level pipeline config (pre-IDL hand-rolled).
 *
 * This is the runtime configuration consumed by the RAG pipeline directly,
 * distinct from solutions.proto::RAGConfig (which is the high-level solution
 * spec resolved through the model registry). RAGConfiguration takes raw model
 * paths because the pipeline runs after model resolution has already happened.
 * ---------------------------------------------------------------------------
 */
export interface RAGConfiguration {
    /** Filesystem path to the embedding model (typically ONNX). */
    embeddingModelPath: string;
    /** Filesystem path to the LLM model (typically GGUF). */
    llmModelPath: string;
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
    /** Legacy metadata JSON blob. */
    metadataJson?: string | undefined;
    /** Typed metadata map for generated-proto callers. */
    metadata: {
        [key: string]: string;
    };
}
export interface RAGDocument_MetadataEntry {
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
    /**
     * Legacy metadata JSON blob preserved for C ABI / SDK surfaces that still
     * pass metadata without parsing it.
     */
    metadataJson?: string | undefined;
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
export declare const RAGQueryOptions: {
    encode(message: RAGQueryOptions, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): RAGQueryOptions;
    fromJSON(object: any): RAGQueryOptions;
    toJSON(message: RAGQueryOptions): unknown;
    create<I extends Exact<DeepPartial<RAGQueryOptions>, I>>(base?: I): RAGQueryOptions;
    fromPartial<I extends Exact<DeepPartial<RAGQueryOptions>, I>>(object: I): RAGQueryOptions;
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