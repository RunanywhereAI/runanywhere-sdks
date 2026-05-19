import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
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
