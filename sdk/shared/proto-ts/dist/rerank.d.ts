import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
export declare const protobufPackage = "runanywhere.v1";
/**
 * A single candidate document/passage to be scored against the query. The id is
 * caller-supplied and echoed back on the scored item so callers can correlate
 * results with their own records without relying on ordering.
 */
export interface RerankCandidate {
    id: string;
    text: string;
}
export interface RerankOptions {
    /**
     * When > 0, only the top_n highest-scoring candidates are returned (every
     * candidate is still scored). 0 = return all candidates, ranked.
     */
    topN: number;
}
export interface RerankRequest {
    query: string;
    candidates: RerankCandidate[];
    options?: RerankOptions | undefined;
}
export interface RerankScoredItem {
    /** Echo of RerankCandidate.id for correlation. */
    id: string;
    /**
     * Raw relevance score from the reranker (higher = more relevant). Not
     * normalized to a fixed range; comparable only within one result set.
     */
    score: number;
    /** Index of this candidate in the original RerankRequest.candidates list. */
    originalIndex: number;
    /** 0-based position after sorting by score descending (0 = most relevant). */
    rank: number;
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
export declare const RerankCandidate: MessageFns<RerankCandidate>;
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
