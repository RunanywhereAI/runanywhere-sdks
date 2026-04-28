import _m0 from "protobufjs/minimal";
export declare const protobufPackage = "runanywhere.v1";
/**
 * ---------------------------------------------------------------------------
 * NPU chipset detected on the host device. Used to drive Genie / vendor-NPU
 * model-download URL selection and runtime backend wiring.
 * Sources pre-IDL:
 *   Dart   npu_chip.dart:14    (snapdragon8Elite, snapdragon8EliteGen5)
 * Canonical superset (this file): vendor-grouped, vendor-agnostic.
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
 * `last_used_ms` (epoch ms, optional) preserves the field that lived on the
 * older Kotlin `StoredModel` (`models/storage/StorageInfo.kt:131`). All
 * other SDKs lacked it pre-IDL; canonicalizing it here lets the SDK surface
 * LRU eviction without another type round-trip.
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
}
/**
 * ---------------------------------------------------------------------------
 * Backward-compatible "stored model" projection. Older Swift / Kotlin / Dart
 * surfaces (`StoredModel`) wrapped a full `ModelInfo`; this canonical form
 * flattens to the columns those SDKs actually exposed via computed
 * properties (id, name, size, local path, downloaded-at), so RN / Web can
 * emit the same shape without round-tripping through `ModelInfo`.
 *
 * Sources pre-IDL: see header drift table.
 * ---------------------------------------------------------------------------
 */
export interface StoredModel {
    modelId: string;
    name: string;
    sizeBytes: number;
    localPath: string;
    /** Unix epoch ms of download completion */
    downloadedAtMs?: number | undefined;
}
export declare const DeviceStorageInfo: {
    encode(message: DeviceStorageInfo, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): DeviceStorageInfo;
    fromJSON(object: any): DeviceStorageInfo;
    toJSON(message: DeviceStorageInfo): unknown;
    create<I extends Exact<DeepPartial<DeviceStorageInfo>, I>>(base?: I): DeviceStorageInfo;
    fromPartial<I extends Exact<DeepPartial<DeviceStorageInfo>, I>>(object: I): DeviceStorageInfo;
};
export declare const AppStorageInfo: {
    encode(message: AppStorageInfo, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): AppStorageInfo;
    fromJSON(object: any): AppStorageInfo;
    toJSON(message: AppStorageInfo): unknown;
    create<I extends Exact<DeepPartial<AppStorageInfo>, I>>(base?: I): AppStorageInfo;
    fromPartial<I extends Exact<DeepPartial<AppStorageInfo>, I>>(object: I): AppStorageInfo;
};
export declare const ModelStorageMetrics: {
    encode(message: ModelStorageMetrics, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): ModelStorageMetrics;
    fromJSON(object: any): ModelStorageMetrics;
    toJSON(message: ModelStorageMetrics): unknown;
    create<I extends Exact<DeepPartial<ModelStorageMetrics>, I>>(base?: I): ModelStorageMetrics;
    fromPartial<I extends Exact<DeepPartial<ModelStorageMetrics>, I>>(object: I): ModelStorageMetrics;
};
export declare const StorageInfo: {
    encode(message: StorageInfo, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): StorageInfo;
    fromJSON(object: any): StorageInfo;
    toJSON(message: StorageInfo): unknown;
    create<I extends Exact<DeepPartial<StorageInfo>, I>>(base?: I): StorageInfo;
    fromPartial<I extends Exact<DeepPartial<StorageInfo>, I>>(object: I): StorageInfo;
};
export declare const StorageAvailability: {
    encode(message: StorageAvailability, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): StorageAvailability;
    fromJSON(object: any): StorageAvailability;
    toJSON(message: StorageAvailability): unknown;
    create<I extends Exact<DeepPartial<StorageAvailability>, I>>(base?: I): StorageAvailability;
    fromPartial<I extends Exact<DeepPartial<StorageAvailability>, I>>(object: I): StorageAvailability;
};
export declare const StoredModel: {
    encode(message: StoredModel, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): StoredModel;
    fromJSON(object: any): StoredModel;
    toJSON(message: StoredModel): unknown;
    create<I extends Exact<DeepPartial<StoredModel>, I>>(base?: I): StoredModel;
    fromPartial<I extends Exact<DeepPartial<StoredModel>, I>>(object: I): StoredModel;
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
//# sourceMappingURL=storage_types.d.ts.map