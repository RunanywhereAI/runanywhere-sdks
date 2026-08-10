import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
import { NPUChip } from "./storage_types";
export declare const protobufPackage = "runanywhere.v1";
/**
 * ---------------------------------------------------------------------------
 * Hardware acceleration preference for inference. Device CLASS, not graphics
 * API. A hint, never a hard requirement — the runtime may fall back.
 * UNSPECIFIED means "you choose".
 *
 * Canonical single enum. It lives in this file rather than model_types.proto
 * because model_types.proto already imports this file; placing it here avoids
 * a cyclic import.
 * ---------------------------------------------------------------------------
 */
export declare enum AccelerationPreference {
    /** ACCELERATION_PREFERENCE_UNSPECIFIED - let the runtime choose */
    ACCELERATION_PREFERENCE_UNSPECIFIED = 0,
    /** ACCELERATION_PREFERENCE_AUTO - DEPRECATED: alias of UNSPECIFIED */
    ACCELERATION_PREFERENCE_AUTO = 1,
    ACCELERATION_PREFERENCE_CPU = 2,
    /** ACCELERATION_PREFERENCE_GPU - covers Metal / Vulkan / WebGPU */
    ACCELERATION_PREFERENCE_GPU = 3,
    /**
     * ACCELERATION_PREFERENCE_NPU - WEBGPU / METAL / VULKAN were removed: they are spellings of GPU, not
     * device classes. The concrete API is the runtime's choice; pass vendor
     * knobs as engine options instead.
     */
    ACCELERATION_PREFERENCE_NPU = 4,
    UNRECOGNIZED = -1
}
export declare function accelerationPreferenceFromJSON(object: any): AccelerationPreference;
export declare function accelerationPreferenceToJSON(object: AccelerationPreference): string;
/**
 * Pre-flight Qualcomm Hexagon NPU probe. Mirrors QHexRT's engine-owned C ABI
 * (`rac/qhexrt/rac_qhexrt.h`) and is serialized by
 * rac_qhexrt_probe_proto(). Enum values equal the Hexagon HTP version number
 * to stay in lock-step with rac_qhexrt_hexagon_arch_t.
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
/**
 * The single NPU-capability description in this IDL. Static device
 * description lives in exactly one other place: device_info.proto's
 * DeviceInfo.
 */
export interface NpuCapability {
    /** Vendor SoC model (e.g. "SM8750"); empty when unknown. */
    socModel: string;
    /**
     * /sys/devices/soc0/soc_id value. ABSENT when unavailable — never a -1 or 0
     * sentinel; a default-constructed message is already "unavailable".
     */
    socId?: number | undefined;
    hexagonArch: HexagonArch;
    /**
     * True iff this accelerator generation is in the device-validated supported
     * set (Hexagon v75/v79/v81 today). Engine-agnostic on purpose: a second NPU
     * engine must not require a second boolean.
     */
    supported: boolean;
    /**
     * NPU vendor family. Re-homed here so a non-Qualcomm device gets a
     * meaningful answer instead of an empty message.
     */
    npu: NPUChip;
}
export declare const NpuCapability: MessageFns<NpuCapability>;
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
