import _m0 from "protobufjs/minimal";
export declare const protobufPackage = "runanywhere.v1";
/**
 * ---------------------------------------------------------------------------
 * Hardware acceleration preference for inference. Canonical single enum —
 * previously duplicated as `AcceleratorPreference` (ANE/GPU/CPU/AUTO) in this
 * file and `AccelerationPreference` in model_types.proto. Consolidated here
 * (Wave H-2 / IDL-01) because it is a pure hardware concept and
 * hardware_profile.proto has no imports (model_types.proto already imports
 * this file — placing the enum here avoids a cyclic import). Sources pre-IDL:
 *   Web    enums.ts:165   (Auto / WebGPU / CPU)
 *   Swift  extensions     (CPU / GPU / NPU / Metal)
 *   Kotlin enum           (CPU / GPU / NPU / Vulkan)
 * Canonicalized union below.
 * ---------------------------------------------------------------------------
 */
export declare enum AccelerationPreference {
    ACCELERATION_PREFERENCE_UNSPECIFIED = 0,
    ACCELERATION_PREFERENCE_AUTO = 1,
    ACCELERATION_PREFERENCE_CPU = 2,
    ACCELERATION_PREFERENCE_GPU = 3,
    ACCELERATION_PREFERENCE_NPU = 4,
    ACCELERATION_PREFERENCE_WEBGPU = 5,
    ACCELERATION_PREFERENCE_METAL = 6,
    ACCELERATION_PREFERENCE_VULKAN = 7,
    UNRECOGNIZED = -1
}
export declare function accelerationPreferenceFromJSON(object: any): AccelerationPreference;
export declare function accelerationPreferenceToJSON(object: AccelerationPreference): string;
export interface HardwareProfile {
    chip: string;
    hasNeuralEngine: boolean;
    /** "ane", "gpu", "cpu" */
    accelerationMode: string;
    totalMemoryBytes: number;
    coreCount: number;
    performanceCores: number;
    efficiencyCores: number;
    /** "arm64", "x86_64" */
    architecture: string;
    /** "ios", "android", "web", "macos", "linux", "windows" */
    platform: string;
}
export interface AcceleratorInfo {
    name: string;
    type: AccelerationPreference;
    available: boolean;
}
export interface HardwareProfileResult {
    profile?: HardwareProfile | undefined;
    accelerators: AcceleratorInfo[];
}
/**
 * Empty request for the cached hardware profile. The native probe is owned by
 * platform adapters; this request carries no portable parameters today.
 */
export interface HardwareProfileRequest {
}
/**
 * Empty request for the accelerator list. Mirrors HardwareProfileRequest:
 * platform probes own all OS-level acceleration discovery.
 */
export interface HardwareAcceleratorsRequest {
}
/**
 * Result-shaped response for SetAcceleratorPreference so the service contract
 * stays consistent (every rpc returns a non-empty message).
 */
export interface HardwareAcceleratorPreferenceRequest {
    preference: AccelerationPreference;
}
export interface HardwareAcceleratorPreferenceResult {
    success: boolean;
    errorMessage: string;
}
export declare const HardwareProfile: {
    encode(message: HardwareProfile, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): HardwareProfile;
    fromJSON(object: any): HardwareProfile;
    toJSON(message: HardwareProfile): unknown;
    create<I extends Exact<DeepPartial<HardwareProfile>, I>>(base?: I): HardwareProfile;
    fromPartial<I extends Exact<DeepPartial<HardwareProfile>, I>>(object: I): HardwareProfile;
};
export declare const AcceleratorInfo: {
    encode(message: AcceleratorInfo, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): AcceleratorInfo;
    fromJSON(object: any): AcceleratorInfo;
    toJSON(message: AcceleratorInfo): unknown;
    create<I extends Exact<DeepPartial<AcceleratorInfo>, I>>(base?: I): AcceleratorInfo;
    fromPartial<I extends Exact<DeepPartial<AcceleratorInfo>, I>>(object: I): AcceleratorInfo;
};
export declare const HardwareProfileResult: {
    encode(message: HardwareProfileResult, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): HardwareProfileResult;
    fromJSON(object: any): HardwareProfileResult;
    toJSON(message: HardwareProfileResult): unknown;
    create<I extends Exact<DeepPartial<HardwareProfileResult>, I>>(base?: I): HardwareProfileResult;
    fromPartial<I extends Exact<DeepPartial<HardwareProfileResult>, I>>(object: I): HardwareProfileResult;
};
export declare const HardwareProfileRequest: {
    encode(_: HardwareProfileRequest, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): HardwareProfileRequest;
    fromJSON(_: any): HardwareProfileRequest;
    toJSON(_: HardwareProfileRequest): unknown;
    create<I extends Exact<DeepPartial<HardwareProfileRequest>, I>>(base?: I): HardwareProfileRequest;
    fromPartial<I extends Exact<DeepPartial<HardwareProfileRequest>, I>>(_: I): HardwareProfileRequest;
};
export declare const HardwareAcceleratorsRequest: {
    encode(_: HardwareAcceleratorsRequest, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): HardwareAcceleratorsRequest;
    fromJSON(_: any): HardwareAcceleratorsRequest;
    toJSON(_: HardwareAcceleratorsRequest): unknown;
    create<I extends Exact<DeepPartial<HardwareAcceleratorsRequest>, I>>(base?: I): HardwareAcceleratorsRequest;
    fromPartial<I extends Exact<DeepPartial<HardwareAcceleratorsRequest>, I>>(_: I): HardwareAcceleratorsRequest;
};
export declare const HardwareAcceleratorPreferenceRequest: {
    encode(message: HardwareAcceleratorPreferenceRequest, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): HardwareAcceleratorPreferenceRequest;
    fromJSON(object: any): HardwareAcceleratorPreferenceRequest;
    toJSON(message: HardwareAcceleratorPreferenceRequest): unknown;
    create<I extends Exact<DeepPartial<HardwareAcceleratorPreferenceRequest>, I>>(base?: I): HardwareAcceleratorPreferenceRequest;
    fromPartial<I extends Exact<DeepPartial<HardwareAcceleratorPreferenceRequest>, I>>(object: I): HardwareAcceleratorPreferenceRequest;
};
export declare const HardwareAcceleratorPreferenceResult: {
    encode(message: HardwareAcceleratorPreferenceResult, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): HardwareAcceleratorPreferenceResult;
    fromJSON(object: any): HardwareAcceleratorPreferenceResult;
    toJSON(message: HardwareAcceleratorPreferenceResult): unknown;
    create<I extends Exact<DeepPartial<HardwareAcceleratorPreferenceResult>, I>>(base?: I): HardwareAcceleratorPreferenceResult;
    fromPartial<I extends Exact<DeepPartial<HardwareAcceleratorPreferenceResult>, I>>(object: I): HardwareAcceleratorPreferenceResult;
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
