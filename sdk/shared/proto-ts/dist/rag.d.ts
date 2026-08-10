import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
import { SDKError } from "./errors";
import { LLMGenerationOptions } from "./llm_options";
import { TokenUsage } from "./token_usage";
export declare const protobufPackage = "runanywhere.v1";
export declare enum RAGStreamEventKind {
    RAG_STREAM_EVENT_KIND_UNSPECIFIED = 0,
    RAG_STREAM_EVENT_KIND_TOKEN = 1,
    RAG_STREAM_EVENT_KIND_COMPLETED = 2,
    RAG_STREAM_EVENT_KIND_ERROR = 3,
    UNRECOGNIZED = -1
}
export declare function rAGStreamEventKindFromJSON(object: any): RAGStreamEventKind;
export declare function rAGStreamEventKindToJSON(object: RAGStreamEventKind): string;
export interface RAGConfiguration {
    embeddingModelId: string;
    llmModelId: string;
    embeddingDimension?: number | undefined;
    /** Retrieval depth, not sampling top_k. */
    topK?: number | undefined;
    /** Drop hits scoring below this. 0.0 = no filtering. */
    scoreThreshold?: number | undefined;
    /** Tokens per chunk, and the overlap carried between adjacent chunks. */
    chunkSize?: number | undefined;
    chunkOverlap?: number | undefined;
    maxContextTokens?: number | undefined;
    promptTemplate?: string | undefined;
    embeddingConfigJson?: string | undefined;
    /** Pointwise rerank of the retrieved chunks using the session LLM. */
    rerankResults: boolean;
}
export interface RAGDocument {
    /** Caller-owned stable id. Re-ingesting an existing id REPLACES its chunks. */
    id: string;
    text: string;
    metadata: {
        [key: string]: string;
    };
    /**
     * Where this document came from. Copied into every chunk's metadata as
     * "source" and returned as RAGSearchResult.source_document.
     */
    sourceUri?: string | undefined;
}
export interface RAGDocument_MetadataEntry {
    key: string;
    value: string;
}
/** Remove whole documents from the index for `rac_rag_delete_proto`. */
export interface RAGDeleteRequest {
    /** RAGDocument.id values given at ingest. Empty is an error — use clear(). */
    documentIds: string[];
}
export interface RAGDeleteResponse {
    deletedChunks: number;
    /** Ids that were not in the index. Not an error. */
    missingIds: string[];
    error?: SDKError | undefined;
}
/** The retrieval knobs, declared once. Every field unset = inherit RAGConfiguration. */
export interface RAGRetrievalOptions {
    /** Retrieval depth for this call. Unset inherits RAGConfiguration.top_k. */
    topK?: number | undefined;
    /** Drop hits scoring below this. Unset inherits RAGConfiguration.score_threshold. */
    scoreThreshold?: number | undefined;
    /**
     * Expand the query into several phrasings and merge the results.
     * Requires a session LLM.
     */
    enableMultiQuery: boolean;
    multiQueryCount?: number | undefined;
    /** Keep only chunks whose document id starts with this prefix. */
    scopePrefix?: string | undefined;
}
export interface RAGQueryOptions {
    query: string;
    retrieval?: RAGRetrievalOptions | undefined;
    generation?: LLMGenerationOptions | undefined;
}
/**
 * Retrieval-only request for `rac_rag_search_proto` / SDK `rag.search()`.
 * Intentionally omits generation options — that is `RAGQueryOptions` /
 * `rac_rag_query_proto` / SDK `rag.query()`.
 */
export interface RAGSearchRequest {
    query: string;
    retrieval?: RAGRetrievalOptions | undefined;
}
export interface RAGSearchResult {
    chunkId: string;
    text: string;
    /**
     * Relevance, higher-is-better, normalised to 0..1. Fused dense + BM25 (RRF),
     * not a raw cosine similarity.
     */
    score: number;
    sourceDocument?: string | undefined;
    metadata: {
        [key: string]: string;
    };
    /** Character offsets into the source document. */
    startOffset: number;
    endOffset: number;
    tokenCount: number;
}
export interface RAGSearchResult_MetadataEntry {
    key: string;
    value: string;
}
/** Retrieval-only response for `rac_rag_search_proto`. */
export interface RAGSearchResponse {
    chunks: RAGSearchResult[];
    retrievalTimeMs: number;
    requestId: string;
    error?: SDKError | undefined;
}
export interface RAGResult {
    answer: string;
    retrievedChunks: RAGSearchResult[];
    contextUsed: string;
    /** Measured directly, not by subtraction: embed the query + search + fuse. */
    retrievalTimeMs: number;
    generationTimeMs: number;
    /** MUST be set by rac_rag_proto_abi (event_id()). */
    requestId: string;
    thinkingContent?: string | undefined;
    /** MUST be copied from the LLM result the pipeline already holds. */
    usage?: TokenUsage | undefined;
    error?: SDKError | undefined;
}
export interface RAGStatistics {
    indexedDocuments: number;
    indexedChunks: number;
    totalTokensIndexed: number;
    /** Milliseconds since the Unix epoch when the index last changed. */
    lastUpdatedMs: number;
    /**
     * Bytes the index occupies (industry: VectorStore.usage_bytes).
     * MUST be populated by make_stats() — it is surfaced as RagStats.indexSizeBytes.
     */
    vectorStoreSizeBytes: number;
    error?: SDKError | undefined;
}
export interface RAGStreamEvent {
    /** Microseconds since the Unix epoch, matching every other modality. */
    timestampUs: number;
    requestId: string;
    kind: RAGStreamEventKind;
    token: string;
    result?: RAGResult | undefined;
    error?: SDKError | undefined;
}
export declare const RAGConfiguration: MessageFns<RAGConfiguration>;
export declare const RAGDocument: MessageFns<RAGDocument>;
export declare const RAGDocument_MetadataEntry: MessageFns<RAGDocument_MetadataEntry>;
export declare const RAGDeleteRequest: MessageFns<RAGDeleteRequest>;
export declare const RAGDeleteResponse: MessageFns<RAGDeleteResponse>;
export declare const RAGRetrievalOptions: MessageFns<RAGRetrievalOptions>;
export declare const RAGQueryOptions: MessageFns<RAGQueryOptions>;
export declare const RAGSearchRequest: MessageFns<RAGSearchRequest>;
export declare const RAGSearchResult: MessageFns<RAGSearchResult>;
export declare const RAGSearchResult_MetadataEntry: MessageFns<RAGSearchResult_MetadataEntry>;
export declare const RAGSearchResponse: MessageFns<RAGSearchResponse>;
export declare const RAGResult: MessageFns<RAGResult>;
export declare const RAGStatistics: MessageFns<RAGStatistics>;
export declare const RAGStreamEvent: MessageFns<RAGStreamEvent>;
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
