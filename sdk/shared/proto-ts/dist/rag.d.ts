import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
import { SDKError } from "./errors";
import { LLMGenerationOptions } from "./llm_options";
import { TokenUsage } from "./token_usage";
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
export interface RAGConfiguration {
    embeddingModelId: string;
    llmModelId: string;
    embeddingDimension?: number | undefined;
    /** Retrieval depth, not sampling top_k. */
    topK?: number | undefined;
    similarityThreshold?: number | undefined;
    /** Tokens per chunk, and the overlap carried between adjacent chunks. */
    chunkSize?: number | undefined;
    chunkOverlap?: number | undefined;
    maxContextTokens?: number | undefined;
    promptTemplate?: string | undefined;
    embeddingConfigJson?: string | undefined;
    llmConfigJson?: string | undefined;
    /** Where the vector index lives, and whether it survives the session. */
    indexPath?: string | undefined;
    persistIndex: boolean;
    rerankResults: boolean;
    rerankerModelId?: string | undefined;
}
export interface RAGDocument {
    id: string;
    text: string;
    metadata: {
        [key: string]: string;
    };
    sourceUri?: string | undefined;
    adapterHandle?: string | undefined;
    mediaType?: string | undefined;
    sizeBytes: number;
}
export interface RAGDocument_MetadataEntry {
    key: string;
    value: string;
}
export interface RAGQueryOptions {
    question: string;
    generation?: LLMGenerationOptions | undefined;
    /** Retrieval depth for this call, overriding RAGConfiguration.top_k. */
    retrievalTopK: number;
    similarityThreshold?: number | undefined;
    stream: boolean;
    /** Expand the question into several queries and merge the results. */
    enableMultiQuery: boolean;
    multiQueryCount?: number | undefined;
    /** Restrict retrieval to chunks whose source matches this prefix. */
    scopePrefix?: string | undefined;
}
/**
 * Retrieval-only request for `rac_rag_search_proto` / SDK `rag.search()`.
 * Intentionally omits generation options — that is `RAGQueryOptions` /
 * `rac_rag_query_proto` / SDK `rag.query()`.
 */
export interface RAGSearchRequest {
    question: string;
    /**
     * Retrieval depth for this call, overriding RAGConfiguration.top_k.
     * Zero means "use the session default".
     */
    retrievalTopK: number;
    similarityThreshold?: number | undefined;
    /**
     * Expand the question into several queries and merge the results.
     * Requires a session LLM (same as RAGQueryOptions.enable_multi_query).
     */
    enableMultiQuery: boolean;
    multiQueryCount?: number | undefined;
    /** Restrict retrieval to chunks whose source matches this prefix. */
    scopePrefix?: string | undefined;
}
export interface RAGSearchResult {
    chunkId: string;
    text: string;
    similarityScore: number;
    sourceDocument?: string | undefined;
    metadata: {
        [key: string]: string;
    };
    rank: number;
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
    retrievalTimeMs: number;
    generationTimeMs: number;
    totalTimeMs: number;
    requestId: string;
    thinkingContent?: string | undefined;
    usage?: TokenUsage | undefined;
    error?: SDKError | undefined;
}
export interface RAGStatistics {
    indexedDocuments: number;
    indexedChunks: number;
    totalTokensIndexed: number;
    lastUpdatedMs: number;
    indexPath?: string | undefined;
    statsJson?: string | undefined;
    vectorStoreSizeBytes: number;
    isPersistent: boolean;
    lastQueryMs: number;
    error?: SDKError | undefined;
}
export interface RAGStreamEvent {
    timestampUs: number;
    requestId: string;
    kind: RAGStreamEventKind;
    chunk?: RAGSearchResult | undefined;
    token: string;
    result?: RAGResult | undefined;
    error?: SDKError | undefined;
}
export declare const RAGConfiguration: MessageFns<RAGConfiguration>;
export declare const RAGDocument: MessageFns<RAGDocument>;
export declare const RAGDocument_MetadataEntry: MessageFns<RAGDocument_MetadataEntry>;
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
