import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
import { NPUChip } from "./storage_types";
export declare const protobufPackage = "runanywhere.v1";
/**
 * ---------------------------------------------------------------------------
 * Hardware acceleration preference for inference. Canonical single enum —
 * previously duplicated as `AcceleratorPreference` (ANE/GPU/CPU/AUTO) in this
 * file and `AccelerationPreference` in model_types.proto. Consolidated here
 * because it is a pure hardware concept and
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
/**
 * Logical hardware service contract. Mirrors the C ABI in
 * sdk/runanywhere-commons/include/rac/router/rac_hardware_abi.h:
 *   - rac_hardware_profile_get → GetProfile
 *   - rac_hardware_get_accelerators → GetAccelerators
 *   - rac_hardware_set_accelerator_preference → SetAcceleratorPreference
 *
 * Native device probes (chip detection, neural engine queries, GPU
 * discovery, memory/cores) remain platform-adapter owned. C++ caches and
 * serves the normalized HardwareProfile/AcceleratorInfo messages.
 * Pre-flight Qualcomm Hexagon NPU probe. Mirrors the C ABI struct
 * rac_npu_info_t (rac/infrastructure/device/rac_npu_capability.h); served
 * over the proto-buffer ABI by rac_npu_probe_proto(). Enum values equal the
 * Hexagon HTP version number to stay in lock-step with rac_hexagon_arch_t.
 */
export declare enum HexagonArch {
    HEXAGON_ARCH_UNKNOWN = 0,
    HEXAGON_ARCH_V68 = 68,
    HEXAGON_ARCH_V69 = 69,
    HEXAGON_ARCH_V73 = 73,
    HEXAGON_ARCH_V75 = 75,
    HEXAGON_ARCH_V79 = 79,
    HEXAGON_ARCH_V81 = 81,
    UNRECOGNIZED = -1
}
export declare function hexagonArchFromJSON(object: any): HexagonArch;
export declare function hexagonArchToJSON(object: HexagonArch): string;
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
    /** resolved NPU vendor family (commons-classified) */
    npuChip: NPUChip;
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
export interface NpuCapability {
    /** Vendor SoC model (e.g. "SM8750"); empty when unknown. */
    socModel: string;
    /** /sys/devices/soc0/soc_id value; -1 when unavailable. */
    socId: number;
    hexagonArch: HexagonArch;
    /** True iff hexagon_arch is in the QHexRT-supported set (v75/v79/v81 today). */
    qhexrtSupported: boolean;
    /**
     * rac_hexagon_arch_name(): "v68" ... "v81", "unknown". Materialized so
     * SDKs never re-derive the display name from the enum.
     */
    archName: string;
}
/** Empty request for the NPU probe; mirrors HardwareProfileRequest. */
export interface NpuProbeRequest {
}
export declare const HardwareProfile: MessageFns<HardwareProfile>;
export declare const AcceleratorInfo: MessageFns<AcceleratorInfo>;
export declare const HardwareProfileResult: MessageFns<HardwareProfileResult>;
export declare const HardwareProfileRequest: MessageFns<HardwareProfileRequest>;
export declare const HardwareAcceleratorsRequest: MessageFns<HardwareAcceleratorsRequest>;
export declare const HardwareAcceleratorPreferenceRequest: MessageFns<HardwareAcceleratorPreferenceRequest>;
export declare const HardwareAcceleratorPreferenceResult: MessageFns<HardwareAcceleratorPreferenceResult>;
export declare const NpuCapability: MessageFns<NpuCapability>;
export declare const NpuProbeRequest: MessageFns<NpuProbeRequest>;
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
