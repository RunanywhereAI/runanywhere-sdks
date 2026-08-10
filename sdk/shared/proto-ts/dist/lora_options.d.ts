import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
import { SDKError } from "./errors";
export declare const protobufPackage = "runanywhere.v1";
export interface LoraAdapterConfig {
    /**
     * The handle. apply, remove, list and per-request selection all key on
     * this. Matches PEFT adapter_name / vLLM lora_name / Genie
     * loraAdapterName.
     */
    adapterId: string;
    /**
     * Escape hatch for a loose GGUF that was never registered. Commons still
     * loads strictly from this path: there is no catalog id -> path resolver
     * on the apply path yet.
     */
    adapterPath?: string | undefined;
    /**
     * 1.0 = as trained, 0.0 = applied but contributing nothing, negatives
     * subtract. Unbounded and signed. Unset falls back to the catalog entry's
     * default_scale, then to 1.0.
     */
    scale?: number | undefined;
}
export interface LoraAdapterInfo {
    /** Catalog id when known, else empty. */
    adapterId: string;
    adapterPath: string;
    scale: number;
    /** Whether it is currently applied to the context. */
    applied: boolean;
    /**
     * Read from the adapter artifact at load time. Never settable.
     * rank is PEFT's `r`, alpha is lora_alpha; effective strength is
     * scale * (alpha / rank), which is why 1.0 is not portable between
     * adapters trained with different alpha/rank.
     */
    rank?: number | undefined;
    alpha?: number | undefined;
    /**
     * Measured resident size of this adapter's weights. Absent when the
     * backend does not report it.
     */
    sizeBytes?: number | undefined;
    loadedAtMs: number;
    /** Populated when applied is false. */
    error?: SDKError | undefined;
}
/**
 * The adapter-specific facts only. Everything generic about the artifact —
 * where it is fetched from, how large it is, how to verify it, who published
 * it, and whether it has been fetched — lives on the ModelInfo record for
 * this adapter.
 */
export interface LoraAdapterCatalogEntry {
    id: string;
    name: string;
    /** Explicit base model ids this adapter works with. */
    compatibleModels: string[];
    /** Publisher-recommended strength. Unset means 1.0. */
    defaultScale?: number | undefined;
    tags: string[];
    /**
     * Non-empty means the adapter file is on disk. This is the single
     * definition of "downloaded".
     */
    localPath?: string | undefined;
}
export interface LoraAdapterCatalogQuery {
    adapterId?: string | undefined;
    modelId?: string | undefined;
    downloadedOnly?: boolean | undefined;
    /** Substring match against name. */
    searchQuery?: string | undefined;
    tags: string[];
}
export interface LoraAdapterCatalogListRequest {
    query?: LoraAdapterCatalogQuery | undefined;
}
export interface LoraAdapterCatalogListResult {
    entries: LoraAdapterCatalogEntry[];
    /**
     * total_count is unfiltered. Callers that want a filtered count read
     * entries.size(); a downloaded count is entries with a local_path.
     */
    totalCount: number;
    downloadedCount: number;
    error?: SDKError | undefined;
}
export interface LoraAdapterCatalogGetRequest {
    adapterId: string;
}
export interface LoraAdapterCatalogGetResult {
    found: boolean;
    entry?: LoraAdapterCatalogEntry | undefined;
    error?: SDKError | undefined;
}
export interface LoraCompatibilityResult {
    isCompatible: boolean;
    baseModelRequired?: string | undefined;
    /** Populated when is_compatible is false. */
    error?: SDKError | undefined;
}
export interface LoraApplyRequest {
    requestId: string;
    /**
     * SET semantics, matching Diffusers set_adapters and
     * llama_set_adapters_lora: `adapters` becomes the complete active set and
     * anything not listed is detached.
     */
    adapters: LoraAdapterConfig[];
    /** Stack on top of the currently-applied set instead of replacing it. */
    keepExisting: boolean;
}
export interface LoraApplyResult {
    requestId: string;
    adapters: LoraAdapterInfo[];
    error?: SDKError | undefined;
}
export interface LoraRemoveRequest {
    /** Remove the named adapters; clear_all ignores the list. */
    adapterIds: string[];
    clearAll: boolean;
}
/**
 * Response only. The state read takes no arguments; base_model_id is
 * reported, never a filter.
 */
export interface LoraState {
    loadedAdapters: LoraAdapterInfo[];
    baseModelId?: string | undefined;
    error?: SDKError | undefined;
}
export declare const LoraAdapterConfig: MessageFns<LoraAdapterConfig>;
export declare const LoraAdapterInfo: MessageFns<LoraAdapterInfo>;
export declare const LoraAdapterCatalogEntry: MessageFns<LoraAdapterCatalogEntry>;
export declare const LoraAdapterCatalogQuery: MessageFns<LoraAdapterCatalogQuery>;
export declare const LoraAdapterCatalogListRequest: MessageFns<LoraAdapterCatalogListRequest>;
export declare const LoraAdapterCatalogListResult: MessageFns<LoraAdapterCatalogListResult>;
export declare const LoraAdapterCatalogGetRequest: MessageFns<LoraAdapterCatalogGetRequest>;
export declare const LoraAdapterCatalogGetResult: MessageFns<LoraAdapterCatalogGetResult>;
export declare const LoraCompatibilityResult: MessageFns<LoraCompatibilityResult>;
export declare const LoraApplyRequest: MessageFns<LoraApplyRequest>;
export declare const LoraApplyResult: MessageFns<LoraApplyResult>;
export declare const LoraRemoveRequest: MessageFns<LoraRemoveRequest>;
export declare const LoraState: MessageFns<LoraState>;
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
