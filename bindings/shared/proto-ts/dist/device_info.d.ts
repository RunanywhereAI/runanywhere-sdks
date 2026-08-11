import { BinaryReader, BinaryWriter } from "@bufbuild/protobuf/wire";
export declare const protobufPackage = "runanywhere.v1";
/**
 * Host OS family. Closed set — a producer that cannot classify itself sends
 * PLATFORM_UNSPECIFIED rather than inventing a spelling.
 */
export declare enum Platform {
    PLATFORM_UNSPECIFIED = 0,
    PLATFORM_IOS = 1,
    PLATFORM_ANDROID = 2,
    PLATFORM_MACOS = 3,
    PLATFORM_WEB = 4,
    PLATFORM_LINUX = 5,
    PLATFORM_WINDOWS = 6,
    PLATFORM_TVOS = 7,
    PLATFORM_WATCHOS = 8,
    PLATFORM_VISIONOS = 9,
    UNRECOGNIZED = -1
}
export declare function platformFromJSON(object: any): Platform;
export declare function platformToJSON(object: Platform): string;
/** Physical device class. */
export declare enum FormFactor {
    /** FORM_FACTOR_UNSPECIFIED - replaces the hand-written "unknown" token */
    FORM_FACTOR_UNSPECIFIED = 0,
    FORM_FACTOR_PHONE = 1,
    FORM_FACTOR_TABLET = 2,
    FORM_FACTOR_DESKTOP = 3,
    FORM_FACTOR_LAPTOP = 4,
    FORM_FACTOR_TV = 5,
    FORM_FACTOR_WATCH = 6,
    FORM_FACTOR_HEADSET = 7,
    UNRECOGNIZED = -1
}
export declare function formFactorFromJSON(object: any): FormFactor;
export declare function formFactorToJSON(object: FormFactor): string;
/** Charging state of the main battery. */
export declare enum BatteryState {
    /** BATTERY_STATE_UNSPECIFIED - unreadable (desktop, tvOS, browser) */
    BATTERY_STATE_UNSPECIFIED = 0,
    BATTERY_STATE_CHARGING = 1,
    BATTERY_STATE_UNPLUGGED = 2,
    BATTERY_STATE_FULL = 3,
    UNRECOGNIZED = -1
}
export declare function batteryStateFromJSON(object: any): BatteryState;
export declare function batteryStateToJSON(object: BatteryState): string;
export interface DeviceInfo {
    /** e.g. "iPhone16,2", "Pixel 8 Pro". */
    deviceModel: string;
    platform: Platform;
    osVersion: string;
    formFactor: FormFactor;
    /**
     * ABI name as the OS reports it: Android sends Build.SUPPORTED_ABIS[0]
     * ("arm64-v8a"), Apple "arm64", Web "wasm32". Kept a string because no
     * industry API enumerates ABIs — but the spelling is the OS's, not ours.
     */
    architecture: string;
    /** e.g. "Apple A17 Pro". */
    chipName: string;
    /**
     * Physical RAM installed, in BYTES. Never the JVM heap cap — Android must
     * read ActivityManager.MemoryInfo.totalMem, not Runtime.maxMemory().
     */
    totalMemoryBytes: number;
    /**
     * Free + reclaimable system RAM at snapshot time, in BYTES.
     * 0 = UNKNOWN (the Web producer cannot read it). A consumer MUST NOT read
     * 0 as "no memory left" and refuse to load.
     */
    availableMemoryBytes: number;
    /** Dedicated neural accelerator present (ANE, Hexagon, APU, ...). */
    hasNpu: boolean;
    /** 0 = none OR present-but-unreported. */
    npuCores: number;
    gpuFamily: string;
    /**
     * Remaining charge as a fraction of full. ABSENT is the ONLY encoding of
     * "unknown" — 0.0 means a flat battery, not an unreadable one. Producers
     * bridging through rac_device_registration_info_t (which uses a negative
     * sentinel) MUST map negative -> absent, never negative -> 0.
     */
    batteryLevel?: number | undefined;
    /**
     * ABSENT when the platform reports no battery at all; UNSPECIFIED when a
     * battery exists but its state could not be read. The C ABI member is
     * documented NULL-if-unavailable, which is why this stays `optional`.
     */
    batteryState?: BatteryState | undefined;
    isLowPowerMode: boolean;
    coreCount: number;
    performanceCores: number;
    deviceFingerprint?: string | undefined;
    /**
     * Vendor escape hatch, CLOSED key set:
     *   android: "manufacturer", "device_id", "os_build_id", "sdk_version",
     *            "android_api_level", "locale", "timezone"
     *   web:     "has_webgpu", "has_shared_array_buffer"
     *
     * "manufacturer" and "device_id" are the only two the native parser reads
     * ("device_id" arrives as a promoted top-level JSON key). Keys not listed
     * here are NOT dropped: the Kotlin serializer flattens them into the
     * outbound registration body verbatim, where no client code reads them.
     *
     * A key that restates a typed field above MUST NOT be sent — "device_type",
     * "os_name", "processor_count" and "is_simulator" were removed for exactly
     * that reason, and "device_id" duplicates device_fingerprint and should
     * follow once the native parser reads the typed field instead.
     *
     * Values are always strings. This map does not cross the C ABI on Apple
     * platforms, so nothing load-bearing may live here.
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
