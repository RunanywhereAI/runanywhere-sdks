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
}
export declare const LoRAAdapterConfig: {
    encode(message: LoRAAdapterConfig, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): LoRAAdapterConfig;
    fromJSON(object: any): LoRAAdapterConfig;
    toJSON(message: LoRAAdapterConfig): unknown;
    create<I extends Exact<DeepPartial<LoRAAdapterConfig>, I>>(base?: I): LoRAAdapterConfig;
    fromPartial<I extends Exact<DeepPartial<LoRAAdapterConfig>, I>>(object: I): LoRAAdapterConfig;
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
export declare const LoraCompatibilityResult: {
    encode(message: LoraCompatibilityResult, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): LoraCompatibilityResult;
    fromJSON(object: any): LoraCompatibilityResult;
    toJSON(message: LoraCompatibilityResult): unknown;
    create<I extends Exact<DeepPartial<LoraCompatibilityResult>, I>>(base?: I): LoraCompatibilityResult;
    fromPartial<I extends Exact<DeepPartial<LoraCompatibilityResult>, I>>(object: I): LoraCompatibilityResult;
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
//# sourceMappingURL=lora_options.d.ts.map