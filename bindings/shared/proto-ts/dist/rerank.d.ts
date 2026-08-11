import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
export declare const protobufPackage = "runanywhere.v1";
export interface RerankOptions {
    /**
     * When > 0, only the top_n highest-scoring candidates are returned (every
     * candidate is still scored). 0 = return all candidates, ranked.
     * Industry name (Cohere rerank `top_n`).
     */
    topN: number;
    /**
     * Per-document token budget; longer documents are truncated (tail
     * dropped) before scoring. 0 = the SDK default budget. This is the
     * direct knob on peak memory and per-pair latency on device.
     * Industry name (Cohere v2 / vLLM `max_tokens_per_doc`).
     */
    maxTokensPerDoc: number;
}
export interface RerankRequest {
    query: string;
    options?: RerankOptions | undefined;
    /**
     * The passages to score, in caller order. Results point back at these by
     * index. Cost is LINEAR (one model pass per document), so this is a
     * second-stage reranker over a retriever's output, not a corpus scan;
     * commons rejects more than 100,000 entries with
     * RAC_ERROR_INVALID_PARAMETER. Industry name (Cohere/Voyage/Jina `documents`).
     */
    documents: string[];
    /**
     * Registry id of the reranker to score with. Unset = whatever model is
     * already resident under the rerank component. Mirrors
     * EmbeddingsRequest.model_id and the industry-universal `model` field.
     */
    modelId?: string | undefined;
}
export interface RerankScoredItem {
    /**
     * Relevance of this document to the query, normalized to [0, 1] (sigmoid
     * of the cross-encoder logit). Ordinal, not cardinal: 0.9 is not "twice
     * as relevant" as 0.45, and scores are not comparable across models.
     * Industry name (Cohere/Voyage `relevance_score`).
     */
    relevanceScore: number;
    /**
     * Index of this document in the original RerankRequest.documents list.
     * Industry name (`index`).
     */
    index: number;
}
export interface RerankResult {
    /**
     * Sorted by score descending. When RerankOptions.top_n > 0, truncated to the
     * top_n most relevant items.
     */
    items: RerankScoredItem[];
    processingTimeMs: number;
    modelId: string;
}
export declare const RerankOptions: MessageFns<RerankOptions>;
export declare const RerankRequest: MessageFns<RerankRequest>;
export declare const RerankScoredItem: MessageFns<RerankScoredItem>;
export declare const RerankResult: MessageFns<RerankResult>;
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
