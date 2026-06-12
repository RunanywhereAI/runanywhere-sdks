import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
export declare const protobufPackage = "runanywhere.v1";
export interface DeviceInfo {
    /** e.g. "iPhone16,2", "Pixel 8 Pro". */
    deviceModel: string;
    /** User-facing device name. */
    deviceName: string;
    /** "ios" | "android" | "macos" | "web" | ... */
    platform: string;
    osVersion: string;
    /** "phone" | "tablet" | "desktop" | ... */
    formFactor: string;
    /** "arm64" | "x86_64" | "wasm32" | ... */
    architecture: string;
    /** e.g. "Apple A17 Pro". */
    chipName: string;
    /** Bytes. */
    totalMemory: number;
    /** Bytes. */
    availableMemory: number;
    hasNeuralEngine: boolean;
    neuralEngineCores: number;
    gpuFamily: string;
    /** 0.0–1.0; unset when unavailable. */
    batteryLevel?: number | undefined;
    /** "charging" | "unplugged" | "full" | ... */
    batteryState?: string | undefined;
    isLowPowerMode: boolean;
    coreCount: number;
    performanceCores: number;
    efficiencyCores: number;
    deviceFingerprint?: string | undefined;
    /**
     * Platform-specific fields that are not part of the cross-SDK core
     * (e.g. web: "has_webgpu", "has_shared_array_buffer"; android: "manufacturer",
     * "android_api_level", "os_build_id", ...).
     */
    platformExtras: {
        [key: string]: string;
    };
}
export interface DeviceInfo_PlatformExtrasEntry {
    key: string;
    value: string;
}
export declare const DeviceInfo: MessageFns<DeviceInfo>;
export declare const DeviceInfo_PlatformExtrasEntry: MessageFns<DeviceInfo_PlatformExtrasEntry>;
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
