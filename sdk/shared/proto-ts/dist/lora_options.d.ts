import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
import { SDKError } from "./errors";
export declare const protobufPackage = "runanywhere.v1";
export interface LoRAAdapterConfig {
    /** On-disk path to the GGUF file. */
    adapterPath: string;
    scale: number;
    /** Links back to a catalog entry when the adapter came from one. */
    adapterId?: string | undefined;
    metadata: {
        [key: string]: string;
    };
    /** Not read by commons. */
    targetModules: string[];
}
export interface LoRAAdapterConfig_MetadataEntry {
    key: string;
    value: string;
}
export interface LoRAAdapterInfo {
    /** Catalog id when known, else empty. */
    adapterId: string;
    adapterPath: string;
    scale: number;
    /** Whether it is currently applied to the context. */
    applied: boolean;
    loadedAtMs: number;
    /** Populated when applied is false. */
    error?: SDKError | undefined;
}
export interface LoraAdapterCatalogEntry {
    id: string;
    name: string;
    description: string;
    /** Direct .gguf download URL, and the filename to save it as. */
    url: string;
    filename: string;
    /** Explicit base model ids this adapter works with. */
    compatibleModels: string[];
    /** 0 if unknown. */
    sizeBytes: number;
    author?: string | undefined;
    defaultScale: number;
    /** Lowercase hex. */
    checksumSha256?: string | undefined;
    license?: string | undefined;
    tags: string[];
    metadata: {
        [key: string]: string;
    };
    /** Local artifact state, persisted only after the platform reports success. */
    localPath?: string | undefined;
    isDownloaded?: boolean | undefined;
    downloadedAtUnixMs?: number | undefined;
    isImported?: boolean | undefined;
    statusMessage?: string | undefined;
}
export interface LoraAdapterCatalogEntry_MetadataEntry {
    key: string;
    value: string;
}
export interface LoraAdapterCatalogQuery {
    adapterId?: string | undefined;
    modelId?: string | undefined;
    downloadedOnly?: boolean | undefined;
    searchQuery?: string | undefined;
    tags: string[];
}
export interface LoraAdapterCatalogListRequest {
    query?: LoraAdapterCatalogQuery | undefined;
    includeCounts: boolean;
}
export interface LoraAdapterCatalogListResult {
    entries: LoraAdapterCatalogEntry[];
    /** total_count is unfiltered; filtered_count reflects the query. */
    totalCount: number;
    filteredCount: number;
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
export interface LoraAdapterDownloadCompletedRequest {
    adapterId: string;
    localPath: string;
    sizeBytes?: number | undefined;
    checksumSha256?: string | undefined;
    completedAtUnixMs?: number | undefined;
    imported: boolean;
    statusMessage: string;
}
export interface LoraAdapterDownloadCompletedResult {
    entry?: LoraAdapterCatalogEntry | undefined;
    persisted: boolean;
    error?: SDKError | undefined;
}
export interface LoraAdapterImportRequest {
    /** Platform-readable path of the picked file. */
    sourcePath: string;
    /** Defaults to basename(source_path). */
    filename?: string | undefined;
}
export interface LoraAdapterImportResult {
    /** Stable SDK-owned path of the imported file. */
    localPath: string;
    /** Whether a catalog entry matched and was completed. */
    matched: boolean;
    entry?: LoraAdapterCatalogEntry | undefined;
    error?: SDKError | undefined;
}
export interface LoraCompatibilityResult {
    isCompatible: boolean;
    baseModelRequired?: string | undefined;
    warnings: string[];
    /** Populated when is_compatible is false. */
    error?: SDKError | undefined;
}
export interface LoRAApplyRequest {
    requestId: string;
    adapters: LoRAAdapterConfig[];
    /** Drop currently-applied adapters instead of stacking. */
    replaceExisting: boolean;
}
export interface LoRAApplyResult {
    requestId: string;
    adapters: LoRAAdapterInfo[];
    error?: SDKError | undefined;
}
export interface LoRARemoveRequest {
    requestId: string;
    /** Remove by id or by path; clear_all ignores both lists. */
    adapterIds: string[];
    adapterPaths: string[];
    clearAll: boolean;
}
/**
 * Also serves as the request for List and State, carrying optional
 * base_model_id filtering without a separate empty request type.
 */
export interface LoRAState {
    loadedAdapters: LoRAAdapterInfo[];
    hasActiveAdapters: boolean;
    baseModelId?: string | undefined;
    error?: SDKError | undefined;
}
export declare const LoRAAdapterConfig: MessageFns<LoRAAdapterConfig>;
export declare const LoRAAdapterConfig_MetadataEntry: MessageFns<LoRAAdapterConfig_MetadataEntry>;
export declare const LoRAAdapterInfo: MessageFns<LoRAAdapterInfo>;
export declare const LoraAdapterCatalogEntry: MessageFns<LoraAdapterCatalogEntry>;
export declare const LoraAdapterCatalogEntry_MetadataEntry: MessageFns<LoraAdapterCatalogEntry_MetadataEntry>;
export declare const LoraAdapterCatalogQuery: MessageFns<LoraAdapterCatalogQuery>;
export declare const LoraAdapterCatalogListRequest: MessageFns<LoraAdapterCatalogListRequest>;
export declare const LoraAdapterCatalogListResult: MessageFns<LoraAdapterCatalogListResult>;
export declare const LoraAdapterCatalogGetRequest: MessageFns<LoraAdapterCatalogGetRequest>;
export declare const LoraAdapterCatalogGetResult: MessageFns<LoraAdapterCatalogGetResult>;
export declare const LoraAdapterDownloadCompletedRequest: MessageFns<LoraAdapterDownloadCompletedRequest>;
export declare const LoraAdapterDownloadCompletedResult: MessageFns<LoraAdapterDownloadCompletedResult>;
export declare const LoraAdapterImportRequest: MessageFns<LoraAdapterImportRequest>;
export declare const LoraAdapterImportResult: MessageFns<LoraAdapterImportResult>;
export declare const LoraCompatibilityResult: MessageFns<LoraCompatibilityResult>;
export declare const LoRAApplyRequest: MessageFns<LoRAApplyRequest>;
export declare const LoRAApplyResult: MessageFns<LoRAApplyResult>;
export declare const LoRARemoveRequest: MessageFns<LoRARemoveRequest>;
export declare const LoRAState: MessageFns<LoRAState>;
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
