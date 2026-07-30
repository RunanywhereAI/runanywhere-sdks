import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
export declare const protobufPackage = "runanywhere.v1";
export declare enum NPUChip {
    NPU_CHIP_UNSPECIFIED = 0,
    NPU_CHIP_NONE = 1,
    /** NPU_CHIP_APPLE_NEURAL_ENGINE - A-series and M-series */
    NPU_CHIP_APPLE_NEURAL_ENGINE = 2,
    NPU_CHIP_QUALCOMM_HEXAGON = 3,
    /** NPU_CHIP_MEDIATEK_APU - Dimensity APU */
    NPU_CHIP_MEDIATEK_APU = 4,
    /** NPU_CHIP_GOOGLE_TPU - Pixel Tensor */
    NPU_CHIP_GOOGLE_TPU = 5,
    /** NPU_CHIP_INTEL_NPU - Core Ultra */
    NPU_CHIP_INTEL_NPU = 6,
    /** NPU_CHIP_OTHER - Detected but vendor unmapped */
    NPU_CHIP_OTHER = 99,
    UNRECOGNIZED = -1
}
export declare function nPUChipFromJSON(object: any): NPUChip;
export declare function nPUChipToJSON(object: NPUChip): string;
export interface DeviceStorageInfo {
    totalBytes: number;
    freeBytes: number;
    usedBytes: number;
    /** 0.0 to 100.0, and 0.0 when total_bytes is 0. */
    usedPercent: number;
}
export interface AppStorageInfo {
    documentsBytes: number;
    cacheBytes: number;
    appSupportBytes: number;
    totalBytes: number;
}
export interface ModelStorageMetrics {
    modelId: string;
    sizeOnDiskBytes: number;
    /** Epoch ms of the last load. */
    lastUsedMs?: number | undefined;
}
export interface StorageInfo {
    app?: AppStorageInfo | undefined;
    device?: DeviceStorageInfo | undefined;
    models: ModelStorageMetrics[];
    totalModels: number;
    totalModelsBytes: number;
}
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
    /** Headroom multiplier applied on top of required_bytes. */
    safetyMargin: number;
    /** Count bytes already occupied by this model as reclaimable. */
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
    /** Evict by least-recently-used rather than by size. */
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
    /** Deleting this needs an unload first, or a platform-side delete. */
    requiresUnload: boolean;
    requiresPlatformDelete: boolean;
    storageKey: string;
}
/** Non-destructive: describes what could be reclaimed without doing it. */
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
    /** Refuse to execute if the plan no longer matches current state. */
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
