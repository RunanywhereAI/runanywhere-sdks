import _m0 from "protobufjs/minimal";
export declare const protobufPackage = "runanywhere.v1";
/**
 * ---------------------------------------------------------------------------
 * Configuration for loading a LoRA adapter.
 *
 * `adapter_path` is a path on disk to a LoRA GGUF file. `scale` controls the
 * adapter's effect strength (default 1.0; e.g. 0.3 for F16 adapters on
 * quantized bases). `adapter_id` is optional and, when present, links the
 * runtime config back to a `LoraAdapterCatalogEntry.id` — none of the current
 * SDK shapes carry it, so it is encoded as a `proto3 optional` field.
 * ---------------------------------------------------------------------------
 */
export interface LoRAAdapterConfig {
    /** path on disk to the GGUF file */
    adapterPath: string;
    /** default 1.0 (set by codegen layer) */
    scale: number;
    /** optional link to catalog entry id */
    adapterId?: string | undefined;
    metadata: {
        [key: string]: string;
    };
    targetModules: string[];
}
export interface LoRAAdapterConfig_MetadataEntry {
    key: string;
    value: string;
}
/**
 * ---------------------------------------------------------------------------
 * Info about a currently-loaded LoRA adapter (read-only snapshot).
 *
 * `adapter_id` and `error_message` are not present in any current SDK shape;
 * they are encoded as `proto3 optional` so the existing fields (path, scale,
 * applied) round-trip exactly while reserving room for richer status reports.
 * ---------------------------------------------------------------------------
 */
export interface LoRAAdapterInfo {
    /** catalog id if known, else empty */
    adapterId: string;
    /** path used when loading */
    adapterPath: string;
    /** active scale factor */
    scale: number;
    /** currently applied to the context */
    applied: boolean;
    /** populated when applied = false */
    errorMessage?: string | undefined;
    errorCode: number;
    loadedAtMs: number;
}
/**
 * ---------------------------------------------------------------------------
 * Catalog entry for a LoRA adapter registered with the SDK.
 * Apps register entries at startup; SDKs query "which adapters work with this
 * model" without reinventing detection logic per platform.
 *
 * `author` is not present in any current SDK shape (Swift, Kotlin, Dart, RN,
 * Web, C ABI) — it is encoded as `proto3 optional` so codegen produces a
 * nullable / has-bit-tracked field.
 * ---------------------------------------------------------------------------
 */
export interface LoraAdapterCatalogEntry {
    /** unique adapter identifier */
    id: string;
    /** human-readable display name */
    name: string;
    /** short description */
    description: string;
    /** direct download URL (.gguf) */
    url: string;
    /** filename to save as on disk */
    filename: string;
    /** explicit base model IDs */
    compatibleModels: string[];
    /** file size, 0 if unknown */
    sizeBytes: number;
    /** optional adapter author */
    author?: string | undefined;
    /** recommended adapter scale */
    defaultScale: number;
    /** lowercase hex SHA-256 */
    checksumSha256?: string | undefined;
    license?: string | undefined;
    tags: string[];
    metadata: {
        [key: string]: string;
    };
    /**
     * Stable platform-normalized local artifact path after native/Web has
     * completed download/import and reported the result back to commons.
     */
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
    success: boolean;
    entries: LoraAdapterCatalogEntry[];
    errorMessage: string;
    totalCount: number;
    filteredCount: number;
    downloadedCount: number;
}
export interface LoraAdapterCatalogGetRequest {
    adapterId: string;
}
export interface LoraAdapterCatalogGetResult {
    found: boolean;
    entry?: LoraAdapterCatalogEntry | undefined;
    errorMessage: string;
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
    success: boolean;
    entry?: LoraAdapterCatalogEntry | undefined;
    errorMessage: string;
    persisted: boolean;
}
/**
 * ---------------------------------------------------------------------------
 * Result of a LoRA compatibility pre-check.
 *
 * `base_model_required` is not present in any current SDK shape — it is
 * encoded as `proto3 optional` so a future implementation can surface "this
 * adapter requires base model X" without breaking wire compatibility.
 * ---------------------------------------------------------------------------
 */
export interface LoraCompatibilityResult {
    isCompatible: boolean;
    /** populated when is_compatible = false */
    errorMessage?: string | undefined;
    /** base model id this adapter expects */
    baseModelRequired?: string | undefined;
    warnings: string[];
    errorCode: number;
}
export interface LoRAApplyRequest {
    requestId: string;
    adapters: LoRAAdapterConfig[];
    replaceExisting: boolean;
}
export interface LoRAApplyResult {
    requestId: string;
    adapters: LoRAAdapterInfo[];
    success: boolean;
    errorMessage?: string | undefined;
    errorCode: number;
}
export interface LoRARemoveRequest {
    requestId: string;
    adapterIds: string[];
    adapterPaths: string[];
    clearAll: boolean;
}
export interface LoRAState {
    loadedAdapters: LoRAAdapterInfo[];
    hasActiveAdapters: boolean;
    baseModelId?: string | undefined;
    errorMessage?: string | undefined;
    errorCode: number;
}
export declare const LoRAAdapterConfig: {
    encode(message: LoRAAdapterConfig, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): LoRAAdapterConfig;
    fromJSON(object: any): LoRAAdapterConfig;
    toJSON(message: LoRAAdapterConfig): unknown;
    create<I extends Exact<DeepPartial<LoRAAdapterConfig>, I>>(base?: I): LoRAAdapterConfig;
    fromPartial<I extends Exact<DeepPartial<LoRAAdapterConfig>, I>>(object: I): LoRAAdapterConfig;
};
export declare const LoRAAdapterConfig_MetadataEntry: {
    encode(message: LoRAAdapterConfig_MetadataEntry, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): LoRAAdapterConfig_MetadataEntry;
    fromJSON(object: any): LoRAAdapterConfig_MetadataEntry;
    toJSON(message: LoRAAdapterConfig_MetadataEntry): unknown;
    create<I extends Exact<DeepPartial<LoRAAdapterConfig_MetadataEntry>, I>>(base?: I): LoRAAdapterConfig_MetadataEntry;
    fromPartial<I extends Exact<DeepPartial<LoRAAdapterConfig_MetadataEntry>, I>>(object: I): LoRAAdapterConfig_MetadataEntry;
};
export declare const LoRAAdapterInfo: {
    encode(message: LoRAAdapterInfo, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): LoRAAdapterInfo;
    fromJSON(object: any): LoRAAdapterInfo;
    toJSON(message: LoRAAdapterInfo): unknown;
    create<I extends Exact<DeepPartial<LoRAAdapterInfo>, I>>(base?: I): LoRAAdapterInfo;
    fromPartial<I extends Exact<DeepPartial<LoRAAdapterInfo>, I>>(object: I): LoRAAdapterInfo;
};
export declare const LoraAdapterCatalogEntry: {
    encode(message: LoraAdapterCatalogEntry, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): LoraAdapterCatalogEntry;
    fromJSON(object: any): LoraAdapterCatalogEntry;
    toJSON(message: LoraAdapterCatalogEntry): unknown;
    create<I extends Exact<DeepPartial<LoraAdapterCatalogEntry>, I>>(base?: I): LoraAdapterCatalogEntry;
    fromPartial<I extends Exact<DeepPartial<LoraAdapterCatalogEntry>, I>>(object: I): LoraAdapterCatalogEntry;
};
export declare const LoraAdapterCatalogEntry_MetadataEntry: {
    encode(message: LoraAdapterCatalogEntry_MetadataEntry, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): LoraAdapterCatalogEntry_MetadataEntry;
    fromJSON(object: any): LoraAdapterCatalogEntry_MetadataEntry;
    toJSON(message: LoraAdapterCatalogEntry_MetadataEntry): unknown;
    create<I extends Exact<DeepPartial<LoraAdapterCatalogEntry_MetadataEntry>, I>>(base?: I): LoraAdapterCatalogEntry_MetadataEntry;
    fromPartial<I extends Exact<DeepPartial<LoraAdapterCatalogEntry_MetadataEntry>, I>>(object: I): LoraAdapterCatalogEntry_MetadataEntry;
};
export declare const LoraAdapterCatalogQuery: {
    encode(message: LoraAdapterCatalogQuery, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): LoraAdapterCatalogQuery;
    fromJSON(object: any): LoraAdapterCatalogQuery;
    toJSON(message: LoraAdapterCatalogQuery): unknown;
    create<I extends Exact<DeepPartial<LoraAdapterCatalogQuery>, I>>(base?: I): LoraAdapterCatalogQuery;
    fromPartial<I extends Exact<DeepPartial<LoraAdapterCatalogQuery>, I>>(object: I): LoraAdapterCatalogQuery;
};
export declare const LoraAdapterCatalogListRequest: {
    encode(message: LoraAdapterCatalogListRequest, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): LoraAdapterCatalogListRequest;
    fromJSON(object: any): LoraAdapterCatalogListRequest;
    toJSON(message: LoraAdapterCatalogListRequest): unknown;
    create<I extends Exact<DeepPartial<LoraAdapterCatalogListRequest>, I>>(base?: I): LoraAdapterCatalogListRequest;
    fromPartial<I extends Exact<DeepPartial<LoraAdapterCatalogListRequest>, I>>(object: I): LoraAdapterCatalogListRequest;
};
export declare const LoraAdapterCatalogListResult: {
    encode(message: LoraAdapterCatalogListResult, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): LoraAdapterCatalogListResult;
    fromJSON(object: any): LoraAdapterCatalogListResult;
    toJSON(message: LoraAdapterCatalogListResult): unknown;
    create<I extends Exact<DeepPartial<LoraAdapterCatalogListResult>, I>>(base?: I): LoraAdapterCatalogListResult;
    fromPartial<I extends Exact<DeepPartial<LoraAdapterCatalogListResult>, I>>(object: I): LoraAdapterCatalogListResult;
};
export declare const LoraAdapterCatalogGetRequest: {
    encode(message: LoraAdapterCatalogGetRequest, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): LoraAdapterCatalogGetRequest;
    fromJSON(object: any): LoraAdapterCatalogGetRequest;
    toJSON(message: LoraAdapterCatalogGetRequest): unknown;
    create<I extends Exact<DeepPartial<LoraAdapterCatalogGetRequest>, I>>(base?: I): LoraAdapterCatalogGetRequest;
    fromPartial<I extends Exact<DeepPartial<LoraAdapterCatalogGetRequest>, I>>(object: I): LoraAdapterCatalogGetRequest;
};
export declare const LoraAdapterCatalogGetResult: {
    encode(message: LoraAdapterCatalogGetResult, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): LoraAdapterCatalogGetResult;
    fromJSON(object: any): LoraAdapterCatalogGetResult;
    toJSON(message: LoraAdapterCatalogGetResult): unknown;
    create<I extends Exact<DeepPartial<LoraAdapterCatalogGetResult>, I>>(base?: I): LoraAdapterCatalogGetResult;
    fromPartial<I extends Exact<DeepPartial<LoraAdapterCatalogGetResult>, I>>(object: I): LoraAdapterCatalogGetResult;
};
export declare const LoraAdapterDownloadCompletedRequest: {
    encode(message: LoraAdapterDownloadCompletedRequest, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): LoraAdapterDownloadCompletedRequest;
    fromJSON(object: any): LoraAdapterDownloadCompletedRequest;
    toJSON(message: LoraAdapterDownloadCompletedRequest): unknown;
    create<I extends Exact<DeepPartial<LoraAdapterDownloadCompletedRequest>, I>>(base?: I): LoraAdapterDownloadCompletedRequest;
    fromPartial<I extends Exact<DeepPartial<LoraAdapterDownloadCompletedRequest>, I>>(object: I): LoraAdapterDownloadCompletedRequest;
};
export declare const LoraAdapterDownloadCompletedResult: {
    encode(message: LoraAdapterDownloadCompletedResult, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): LoraAdapterDownloadCompletedResult;
    fromJSON(object: any): LoraAdapterDownloadCompletedResult;
    toJSON(message: LoraAdapterDownloadCompletedResult): unknown;
    create<I extends Exact<DeepPartial<LoraAdapterDownloadCompletedResult>, I>>(base?: I): LoraAdapterDownloadCompletedResult;
    fromPartial<I extends Exact<DeepPartial<LoraAdapterDownloadCompletedResult>, I>>(object: I): LoraAdapterDownloadCompletedResult;
};
export declare const LoraCompatibilityResult: {
    encode(message: LoraCompatibilityResult, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): LoraCompatibilityResult;
    fromJSON(object: any): LoraCompatibilityResult;
    toJSON(message: LoraCompatibilityResult): unknown;
    create<I extends Exact<DeepPartial<LoraCompatibilityResult>, I>>(base?: I): LoraCompatibilityResult;
    fromPartial<I extends Exact<DeepPartial<LoraCompatibilityResult>, I>>(object: I): LoraCompatibilityResult;
};
export declare const LoRAApplyRequest: {
    encode(message: LoRAApplyRequest, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): LoRAApplyRequest;
    fromJSON(object: any): LoRAApplyRequest;
    toJSON(message: LoRAApplyRequest): unknown;
    create<I extends Exact<DeepPartial<LoRAApplyRequest>, I>>(base?: I): LoRAApplyRequest;
    fromPartial<I extends Exact<DeepPartial<LoRAApplyRequest>, I>>(object: I): LoRAApplyRequest;
};
export declare const LoRAApplyResult: {
    encode(message: LoRAApplyResult, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): LoRAApplyResult;
    fromJSON(object: any): LoRAApplyResult;
    toJSON(message: LoRAApplyResult): unknown;
    create<I extends Exact<DeepPartial<LoRAApplyResult>, I>>(base?: I): LoRAApplyResult;
    fromPartial<I extends Exact<DeepPartial<LoRAApplyResult>, I>>(object: I): LoRAApplyResult;
};
export declare const LoRARemoveRequest: {
    encode(message: LoRARemoveRequest, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): LoRARemoveRequest;
    fromJSON(object: any): LoRARemoveRequest;
    toJSON(message: LoRARemoveRequest): unknown;
    create<I extends Exact<DeepPartial<LoRARemoveRequest>, I>>(base?: I): LoRARemoveRequest;
    fromPartial<I extends Exact<DeepPartial<LoRARemoveRequest>, I>>(object: I): LoRARemoveRequest;
};
export declare const LoRAState: {
    encode(message: LoRAState, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): LoRAState;
    fromJSON(object: any): LoRAState;
    toJSON(message: LoRAState): unknown;
    create<I extends Exact<DeepPartial<LoRAState>, I>>(base?: I): LoRAState;
    fromPartial<I extends Exact<DeepPartial<LoRAState>, I>>(object: I): LoRAState;
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
