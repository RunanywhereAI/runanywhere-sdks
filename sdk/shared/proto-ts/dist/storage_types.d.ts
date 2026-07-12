import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
export declare const protobufPackage = "runanywhere.v1";
/**
 * ---------------------------------------------------------------------------
 * NPU chipset detected on the host device. Used to drive vendor-NPU
 * model-download URL selection and runtime backend wiring.
 * ---------------------------------------------------------------------------
 */
export declare enum NPUChip {
    NPU_CHIP_UNSPECIFIED = 0,
    /** NPU_CHIP_NONE - No NPU detected on this device */
    NPU_CHIP_NONE = 1,
    /** NPU_CHIP_APPLE_NEURAL_ENGINE - Apple Neural Engine (A-series / M-series) */
    NPU_CHIP_APPLE_NEURAL_ENGINE = 2,
    /** NPU_CHIP_QUALCOMM_HEXAGON - Snapdragon 8 Elite, 8 Elite Gen 5, etc. */
    NPU_CHIP_QUALCOMM_HEXAGON = 3,
    /** NPU_CHIP_MEDIATEK_APU - MediaTek Dimensity APU */
    NPU_CHIP_MEDIATEK_APU = 4,
    /** NPU_CHIP_GOOGLE_TPU - Pixel Tensor / TPU */
    NPU_CHIP_GOOGLE_TPU = 5,
    /** NPU_CHIP_INTEL_NPU - Intel Core Ultra NPU */
    NPU_CHIP_INTEL_NPU = 6,
    /** NPU_CHIP_OTHER - Detected NPU but vendor unmapped */
    NPU_CHIP_OTHER = 99,
    UNRECOGNIZED = -1
}
export declare function nPUChipFromJSON(object: any): NPUChip;
export declare function nPUChipToJSON(object: NPUChip): string;
/**
 * ---------------------------------------------------------------------------
 * Whole-device storage capacity. Reported by the platform OS (e.g. iOS
 * `URLResourceKey.volumeAvailableCapacity*`, Android `StatFs`, browser
 * `navigator.storage.estimate()`).
 *
 * `used_percent` is materialized rather than computed at the receiver so
 * every binding (Swift, Kotlin, Dart, RN, Web) reports the same number even
 * when total_bytes == 0 (in which case used_percent MUST be 0.0).
 *
 * Sources pre-IDL: see header drift table.
 * ---------------------------------------------------------------------------
 */
export interface DeviceStorageInfo {
    totalBytes: number;
    freeBytes: number;
    usedBytes: number;
    /** 0.0 — 100.0; 0.0 if total_bytes == 0 */
    usedPercent: number;
}
/**
 * ---------------------------------------------------------------------------
 * Per-app storage breakdown by directory type. Mirrors the iOS notion of
 * Documents / Caches / Application Support; on Android these map to
 * filesDir / cacheDir / a stable app-support sub-directory; on Web they map
 * to OPFS / FSAccess buckets (collapsed to documents_bytes by default).
 *
 * Sources pre-IDL: see header drift table.
 * ---------------------------------------------------------------------------
 */
export interface AppStorageInfo {
    documentsBytes: number;
    cacheBytes: number;
    appSupportBytes: number;
    totalBytes: number;
}
/**
 * ---------------------------------------------------------------------------
 * On-disk metrics for a single downloaded model. The full ModelInfo is *not*
 * embedded here — callers cross-reference `model_id` against ModelInfo from
 * model_types.proto. This avoids circular embeds and keeps the wire payload
 * for storage queries small.
 *
 * `last_used_ms` supports LRU presentation and eviction without another type
 * round-trip.
 *
 * Sources pre-IDL: see header drift table.
 * ---------------------------------------------------------------------------
 */
export interface ModelStorageMetrics {
    modelId: string;
    sizeOnDiskBytes: number;
    /** Unix epoch ms of last load */
    lastUsedMs?: number | undefined;
}
/**
 * ---------------------------------------------------------------------------
 * Aggregate storage view: device capacity + app footprint + per-model rows.
 * `total_models` and `total_models_bytes` are denormalized for receivers that
 * would otherwise re-iterate `models` to compute them (Web binding, RN host).
 *
 * Sources pre-IDL: see header drift table.
 * ---------------------------------------------------------------------------
 */
export interface StorageInfo {
    app?: AppStorageInfo | undefined;
    device?: DeviceStorageInfo | undefined;
    models: ModelStorageMetrics[];
    totalModels: number;
    totalModelsBytes: number;
}
/**
 * ---------------------------------------------------------------------------
 * Result of a "do I have room to download X bytes?" probe. SDKs use this to
 * pre-flight `downloadModel(...)` and surface user-facing warnings (e.g.
 * "you only have 1.2 GB free; this model needs 4 GB").
 *
 * `warning_message` and `recommendation` are independently optional —
 * `warning_message` describes the current shortfall, `recommendation`
 * suggests an action (delete cache, free models, etc.).
 *
 * Sources pre-IDL: see header drift table.
 * ---------------------------------------------------------------------------
 */
export interface StorageAvailability {
    isAvailable: boolean;
    requiredBytes: number;
    availableBytes: number;
    warningMessage?: string | undefined;
    recommendation?: string | undefined;
    shortfallBytes: number;
    requiredToAvailableRatio: number;
}
export interface StorageInfoRequest {
    includeDevice: boolean;
    includeApp: boolean;
    includeModels: boolean;
    includeCache: boolean;
}
export interface StorageInfoResult {
    success: boolean;
    info?: StorageInfo | undefined;
    errorMessage: string;
    warnings: string[];
}
export interface StorageAvailabilityRequest {
    modelId: string;
    requiredBytes: number;
    safetyMargin: number;
    includeExistingModelBytes: boolean;
    includeDeletePlan: boolean;
    allowCacheReclamation: boolean;
}
export interface StorageAvailabilityResult {
    success: boolean;
    availability?: StorageAvailability | undefined;
    warnings: string[];
    errorMessage: string;
    deletePlan?: StorageDeletePlan | undefined;
}
export interface StorageDeletePlanRequest {
    modelIds: string[];
    requiredBytes: number;
    includeCache: boolean;
    oldestFirst: boolean;
    allowLoadedModels: boolean;
    includeDownloadPartials: boolean;
}
export interface StorageDeleteCandidate {
    modelId: string;
    reclaimableBytes: number;
    lastUsedMs?: number | undefined;
    isLoaded: boolean;
    localPath: string;
    requiresUnload: boolean;
    requiresPlatformDelete: boolean;
    storageKey: string;
}
export interface StorageDeletePlan {
    canReclaimRequiredBytes: boolean;
    requiredBytes: number;
    reclaimableBytes: number;
    candidates: StorageDeleteCandidate[];
    warnings: string[];
    errorMessage: string;
    requiresUnload: boolean;
    requiresPlatformDelete: boolean;
    candidateCount: number;
}
export interface StorageDeleteRequest {
    modelIds: string[];
    deleteFiles: boolean;
    clearRegistryPaths: boolean;
    unloadIfLoaded: boolean;
    dryRun: boolean;
    plan?: StorageDeletePlan | undefined;
    requirePlanMatch: boolean;
    allowPlatformDelete: boolean;
}
export interface StorageDeleteResult {
    success: boolean;
    deletedBytes: number;
    deletedModelIds: string[];
    failedModelIds: string[];
    warnings: string[];
    errorMessage: string;
    skippedModelIds: string[];
    dryRun: boolean;
    registryUpdated: boolean;
    filesDeleted: boolean;
}
export declare const DeviceStorageInfo: MessageFns<DeviceStorageInfo>;
export declare const AppStorageInfo: MessageFns<AppStorageInfo>;
export declare const ModelStorageMetrics: MessageFns<ModelStorageMetrics>;
export declare const StorageInfo: MessageFns<StorageInfo>;
export declare const StorageAvailability: MessageFns<StorageAvailability>;
export declare const StorageInfoRequest: MessageFns<StorageInfoRequest>;
export declare const StorageInfoResult: MessageFns<StorageInfoResult>;
export declare const StorageAvailabilityRequest: MessageFns<StorageAvailabilityRequest>;
export declare const StorageAvailabilityResult: MessageFns<StorageAvailabilityResult>;
export declare const StorageDeletePlanRequest: MessageFns<StorageDeletePlanRequest>;
export declare const StorageDeleteCandidate: MessageFns<StorageDeleteCandidate>;
export declare const StorageDeletePlan: MessageFns<StorageDeletePlan>;
export declare const StorageDeleteRequest: MessageFns<StorageDeleteRequest>;
export declare const StorageDeleteResult: MessageFns<StorageDeleteResult>;
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
